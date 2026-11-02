"""Build bundled PV lookup CSVs from per-angle Excel simulations.

Run: python scripts/merge_pv_generation.py --source "E:/pv generation data/stride_1-1"
Each product writes data/pv_generation/stride_1-1/<model>_<power>W/{hourly,monthly_hourly}.csv.
Rows are angle pairs; columns are hourly intervals (8760) or monthly hourly means (288).
The source timestamps denote interval ends; output headers denote interval starts.
"""
import argparse
import calendar
import csv
import datetime as dt
import hashlib
import json
import os
import re
import sys
import shutil
import time
import numpy as np
from concurrent.futures import ProcessPoolExecutor
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = Path('E:/pv generation data/stride_1-1')
DEST = ROOT / 'data/pv_generation/stride_1-1'
NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
NAME = re.compile(r'^(\d+)-(\d+)-.*\.xlsx$', re.I)
A_CELLS = re.compile(rb'<c r="A(\d+)"[^>]*t="s"[^>]*><v>(\d+)</v></c>')
B_CELLS = re.compile(rb'<c r="B(\d+)"([^>]*)><v>([^<]*)</v></c>')
EXPECTED = {(a, b) for a in range(0, 360) for b in range(0, 91)}
STARTS = [dt.datetime(2001, 1, 1) + dt.timedelta(hours=i) for i in range(8760)]
ENDS = [t + dt.timedelta(hours=1) for t in STARTS]
TIME_LABELS = [f'Year {t.year - 2000} {calendar.month_abbr[t.month]} {t.day:02d} {t.hour}:00' for t in ENDS]
GROUPS = np.array([(t.month - 1) * 24 + t.hour for t in STARTS])
DAYS = [calendar.monthrange(2001, m)[1] for m in range(1, 13)]
HOURLY_HEADER = ['azimuth_deg', 'tilt_deg'] + [f'{t.month:02d}-{t.day:02d}_{t.hour:02d}:00-{t.hour+1:02d}:00_Wh' for t in STARTS]
MEAN_HEADER = ['azimuth_deg', 'tilt_deg'] + [f'{m:02d}_{h:02d}:00-{h+1:02d}:00_Wh' for m in range(1, 13) for h in range(24)]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def slug(model):
    return re.sub(r'[^A-Za-z0-9.-]+', '_', model).strip('_')


def products(source_root=RAW):
    data = (ROOT / 'data' / 'PV panel.csv').read_bytes()
    try:
        text = data.decode('utf-8-sig')
    except UnicodeDecodeError:
        text = data.decode('gb18030')
    result = []
    for row in csv.DictReader(text.splitlines()):
        power=float(row['STC-Pmax(W)'])
        if not (source_root/f'{power:g}_excel_files').is_dir():
            continue
        dimensions = re.fullmatch(r'(\d+(?:\.\d+)?)\s*[×xX*]\s*(\d+(?:\.\d+)?)\s*[×xX*]\s*(\d+(?:\.\d+)?)\s*mm', row['尺寸'].strip(), re.I)
        require(dimensions, f"Invalid dimensions: {row['型号']}")
        power = float(row['STC-Pmax(W)'])
        result.append({'model_id': row['型号'].strip(), 'manufacturer': row['生产商'], 'power_w': power,
                       'dimensions_mm': list(map(float, dimensions.groups()))})
    require(len({s['power_w'] for s in result})==len(result), 'Source power folder matches more than one model; provide unambiguous model folders.')
    return result


def xlsx_rows(path):
    with zipfile.ZipFile(path) as z:
        strings = [''.join(t.text or '' for t in si.findall('.//m:t', NS))
                   for si in ET.fromstring(z.read('xl/sharedStrings.xml'))]
        rows = []
        for row in ET.fromstring(z.read('xl/worksheets/sheet1.xml')).findall('m:sheetData/m:row', NS):
            values = {}
            for cell in row.findall('m:c', NS):
                v = cell.find('m:v', NS)
                value = v.text if v is not None else ''.join(t.text or '' for t in cell.findall('.//m:t', NS))
                if cell.get('t') == 's':
                    value = strings[int(value)]
                values[re.match(r'[A-Z]+', cell.get('r'))[0]] = value
            rows.append(values)
        return rows


def file_hash(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def serial(values):
    # Shortest round-trip decimal of each float64; zero is compact, no rounding.
    return ','.join('0' if x==0 else repr(x) for x in values.tolist())


def verify_csv(path, header, checks):
    with path.open('rb') as f:
        require(f.readline().decode('utf-8-sig').rstrip('\r\n').split(',')==header, f'Invalid saved header: {path}')
        for angle, expected in checks:
            row=f.readline().split(b',',2)
            require(len(row)==3 and tuple(map(int,row[:2]))==angle, f'Invalid saved angle: {path}')
            values=np.fromstring(row[2].decode('ascii'),sep=',',dtype=np.float64)
            require(len(values)==len(header)-2 and hashlib.sha256(values.tobytes()).digest()==expected, f'Saved values changed: {path} {angle}')
        require(not f.read(1), f'Unexpected extra rows: {path}')


def convert(job):
    spec, source, *segments = job
    source = Path(source)
    key = f"{slug(spec['model_id'])}_{spec['power_w']:g}W"
    folder = DEST / key
    lower,upper=segments[0] if segments else (0,359)
    expected={(a,b) for a in range(lower,upper+1) for b in range(91)}
    if segments:
        folder=folder/'.chunks'/f'{lower:03d}-{upper:03d}'
    label=key+(f' [{lower}-{upper}]' if segments else '')
    files = sorted((int(m[1]), int(m[2]), path) for path in source.iterdir() if (m := NAME.fullmatch(path.name)))
    files=[(a,b,p) for a,b,p in files if lower<=a<=upper]
    require(len(files) == len(expected) and {(a, b) for a, b, _ in files} == expected, f'Incomplete or duplicate angles: {source}')
    controls = xlsx_rows(source / 'results.xlsx')
    require(controls[0]['A'] == '方位角deg' and controls[0]['B'] == '倾角deg' and controls[0]['C']=='总发电量kWh', f'Unexpected controls: {source}')
    totals = {(int(float(row['A'])), int(float(row['B']))): [float(row[chr(68+m)]) for m in range(12)] + [float(row['C'])*1000] for row in controls[1:]}
    require(set(totals) == EXPECTED and len(controls)-1 == len(EXPECTED), f'Invalid control angles: {source}')
    first = files[0][2]
    reference = xlsx_rows(first)
    require(reference[0] == {'A': 'Date Time', 'B': 'Generation(Wh)'}, f'Unexpected hourly units: {first}')
    require([row['A'] for row in reference[1:]] == TIME_LABELS, f'Incomplete non-leap-year time axis: {first}')
    with zipfile.ZipFile(first) as z:
        strings = z.read('xl/sharedStrings.xml')
        xml = z.read('xl/worksheets/sheet1.xml')
        reference_a, reference_b = A_CELLS.findall(xml), B_CELLS.findall(xml)[0]
    folder.mkdir(parents=True, exist_ok=True)
    hourly, mean = folder/'hourly.csv', folder/'monthly_hourly.csv'
    partial_h, partial_m = folder/'hourly.csv.partial', folder/'monthly_hourly.csv.partial'
    require(not any(p.exists() for p in [hourly, mean, partial_h, partial_m]), f'Destination exists; stopped without overwriting: {folder}')
    checks_h, checks_m, offsets, annual = [], [], [], []
    row_ids = [str(n).encode('ascii') for n in range(2,8762)]
    started = time.monotonic()
    max_month_error = max_year_error = 0.0
    with partial_h.open('wb') as fh, partial_m.open('wb') as fm:
        fh.write(('\ufeff'+','.join(HOURLY_HEADER)+'\r\n').encode('utf-8'))
        fm.write(('\ufeff'+','.join(MEAN_HEADER)+'\r\n').encode('utf-8'))
        for i, (a, b, path) in enumerate(files, 1):
            with zipfile.ZipFile(path) as z:
                require(z.read('xl/sharedStrings.xml') == strings, f'Time strings changed: {path}')
                xml = z.read('xl/worksheets/sheet1.xml')
            require(A_CELLS.findall(xml) == reference_a, f'Time axis changed: {path}')
            cells = B_CELLS.findall(xml)
            require(len(cells) == 8761 and cells[0] == reference_b, f'Incomplete hourly cells: {path}')
            require([r for r,_,_ in cells[1:]] == row_ids and all(b't=' not in attrs for _,attrs,_ in cells[1:]), f'Invalid numeric cells: {path}')
            values = np.fromstring(b','.join(raw for _,_,raw in cells[1:]).decode('ascii'), sep=',', dtype=np.float64)
            require(len(values)==8760 and np.isfinite(values).all() and (values>=0).all(), f'Invalid hourly values: {path}')
            sums = np.bincount(GROUPS, weights=values, minlength=288)
            monthly = sums.reshape(12,24).sum(axis=1)
            month_error = float(np.max(np.abs(monthly-totals[(a,b)][:12])))
            year_error = abs(float(values.sum())-totals[(a,b)][12])
            require(month_error < 1e-5 and year_error < 1e-5, f'Month/year control mismatch: {path}: {month_error}, {year_error}')
            means = sums/np.repeat(DAYS,24)
            offsets.append([a,b,fh.tell()])
            annual.append(float(values.sum())/1000)
            fh.write((f'{a},{b},'+serial(values)+'\r\n').encode('ascii'))
            fm.write((f'{a},{b},'+serial(means)+'\r\n').encode('ascii'))
            checks_h.append(((a,b),hashlib.sha256(values.tobytes()).digest()))
            checks_m.append(((a,b),hashlib.sha256(means.tobytes()).digest()))
            max_month_error = max(max_month_error,month_error);max_year_error = max(max_year_error,year_error)
            if i%1000 == 0 or i == len(files):
                print(f'{label}: {i}/{len(files)} angle rows checked ({time.monotonic()-started:.0f}s)', flush=True)
                require(shutil.disk_usage(DEST).free>200_000_000, 'Output disk nearly full; stopped before publication.')
    print(f'{label}: checking all saved numeric values',flush=True)
    verify_csv(partial_h, HOURLY_HEADER, checks_h)
    verify_csv(partial_m, MEAN_HEADER, checks_m)
    hourly_hash,monthly_hash=file_hash(partial_h),file_hash(partial_m)
    sidecar=folder/'row_index.json'
    sidecar_partial=folder/'row_index.json.partial'
    sidecar_partial.write_text(json.dumps({'schema':1,'csv_bytes':partial_h.stat().st_size,'csv_sha256':hourly_hash,'rows':offsets,'annual_kwh':annual},separators=(',',':')),encoding='utf-8')
    # Publish only after both complete numeric round-trip checks succeed.
    os.rename(partial_h, hourly);os.rename(partial_m, mean);os.rename(sidecar_partial,sidecar)
    print(f'{label}: complete; monthly max error {max_month_error:.3g} Wh, annual {max_year_error:.3g} Wh',flush=True)
    entry=dict(spec, source_dir=source.as_posix(), hourly=hourly.relative_to(DEST).as_posix(),
                monthly_hourly=mean.relative_to(DEST).as_posix(), angle_rows=len(files), hourly_columns=8762,
                monthly_hourly_columns=290, row_index=sidecar.relative_to(DEST).as_posix(),
                hourly_bytes=hourly.stat().st_size,monthly_hourly_bytes=mean.stat().st_size,
                hourly_sha256=hourly_hash, monthly_hourly_sha256=monthly_hash,
                max_month_error_wh=max_month_error, max_annual_error_wh=max_year_error)
    return entry


def assemble(spec, parts):
    """Join verified byte streams; no numeric reformatting or angle interpolation."""
    key=f"{slug(spec['model_id'])}_{spec['power_w']:g}W"
    folder=DEST/key
    require(not any((folder/name).exists() for name in ('hourly.csv','monthly_hourly.csv')),f'Published model exists: {key}')
    offsets=[];annual=[];hashes={}
    for kind,header in [('hourly',HOURLY_HEADER),('monthly_hourly',MEAN_HEADER)]:
        partial=folder/f'{kind}.csv.assembled'
        digest=hashlib.sha256()
        expected_header=('\ufeff'+','.join(header)+'\r\n').encode('utf-8')
        with partial.open('wb') as dst:
            dst.write(expected_header);digest.update(expected_header)
            for part in parts:
                with (DEST/part[kind]).open('rb') as src:
                    h=src.readline();require(h==expected_header,f'Segment header changed: {key}')
                    if kind=='hourly':
                        idx=json.loads((DEST/part['row_index']).read_text(encoding='utf-8'))
                        require(idx['csv_sha256']==part['hourly_sha256'],f'Segment index changed: {key}')
                        shift=dst.tell()-len(h)
                        offsets.extend([a,b,off+shift] for a,b,off in idx['rows'])
                        annual.extend(idx.get('annual_kwh',[]))
                    while (block:=src.read(4*1024*1024)):
                        digest.update(block);dst.write(block)
        hashes[kind]=digest.hexdigest()
        require(file_hash(partial)==hashes[kind],f'Concatenated bytes changed: {key}/{kind}')
    require([(a,b) for a,b,_ in offsets]==sorted(EXPECTED),'Segment grid is incomplete or duplicated')
    sidecar={'schema':1,'csv_bytes':(folder/'hourly.csv.assembled').stat().st_size,
             'csv_sha256':hashes['hourly'],'rows':offsets}
    if annual:
        require(len(annual)==len(EXPECTED),'Segment annual cache is incomplete')
        sidecar['annual_kwh']=annual
    (folder/'row_index.json.assembled').write_text(json.dumps(sidecar,separators=(',',':')),encoding='utf-8')
    for name in ('hourly.csv','monthly_hourly.csv','row_index.json'):
        os.replace(folder/(name+'.assembled'),folder/name)
    entry=dict(spec,source_dir=parts[0]['source_dir'],hourly=f'{key}/hourly.csv',monthly_hourly=f'{key}/monthly_hourly.csv',
               row_index=f'{key}/row_index.json',angle_rows=len(EXPECTED),hourly_columns=8762,monthly_hourly_columns=290,
               hourly_bytes=(folder/'hourly.csv').stat().st_size,monthly_hourly_bytes=(folder/'monthly_hourly.csv').stat().st_size,
               hourly_sha256=hashes['hourly'],monthly_hourly_sha256=hashes['monthly_hourly'],
               max_month_error_wh=max(p['max_month_error_wh'] for p in parts),max_annual_error_wh=max(p['max_annual_error_wh'] for p in parts))
    # Only remove explicitly named temporary files generated by this conversion.
    for part in parts:
        sub=(DEST/part['hourly']).parent
        require(sub.resolve().is_relative_to((folder/'.chunks').resolve()),'Unexpected segment cleanup path')
        for name in ('hourly.csv','monthly_hourly.csv','row_index.json'):
            (sub/name).unlink()
        sub.rmdir()
    (folder/'.chunks').rmdir()
    for name in ('hourly.csv.partial','monthly_hourly.csv.partial'):
        (folder/name).unlink(missing_ok=True)
    print(f'{key}: complete; all verified segments joined without changing numeric bytes',flush=True)
    return entry


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=RAW)
    parser.add_argument('--finalize',action='store_true',help='Verify all published models and atomically activate the complete dataset.')
    parser.add_argument('--workers',type=int,choices=range(1,5),default=2)
    parser.add_argument('--shards',type=int,choices=(1,2,4),default=1,help='Split one selected model into balanced azimuth segments.')
    parser.add_argument('--model', help='Convert only this exact model ID; merge it into the index.')
    args=parser.parse_args()
    require(args.shards==1 or args.model,'--shards requires one exact --model')
    DEST.mkdir(parents=True,exist_ok=True)
    index_path=DEST/'index.json'
    index=json.loads(index_path.read_text(encoding='utf-8')) if index_path.exists() else {'schema':1,'unit':'Wh','calendar':'non_leap','hourly_intervals':8760,'monthly_hourly_intervals':288,'angle_grid':{'azimuth_min':0,'azimuth_max':359,'azimuth_step':1,'tilt_min':0,'tilt_max':90,'tilt_step':1},'models':{}}
    if args.finalize:
        for spec in products(args.source):
            key=f"{slug(spec['model_id'])}_{spec['power_w']:g}W"
            entry=index['models'].get(spec['model_id'])
            require(entry and all(entry[k]==spec[k] for k in spec), f'Missing or mismatched model: {key}')
            require(entry['angle_rows']==len(EXPECTED), f'Incomplete model: {key}')
            for name in ('hourly','monthly_hourly'):
                require(file_hash(DEST/entry[name])==entry[name+'_sha256'], f'Changed CSV: {key}/{name}')
            sidecar=DEST/entry['row_index']
            rows=json.loads(sidecar.read_text(encoding='utf-8'))
            require(rows['csv_sha256']==entry['hourly_sha256'] and rows['csv_bytes']==(DEST/entry['hourly']).stat().st_size
                    and [(a,b) for a,b,_ in rows['rows']]==sorted(EXPECTED), f'Invalid row index: {key}')
            # Annual values also serve the retained design-advice calculation without
            # parsing all 9.4 million monthly-hourly cells again inside SketchUp.
            annual=[]
            with (DEST/entry['monthly_hourly']).open('rb') as f:
                f.readline()
                for expected,line in zip(sorted(EXPECTED),f):
                    a,b,payload=line.split(b',',2)
                    require((int(a),int(b))==expected, f'Invalid monthly angle: {key}')
                    v=np.fromstring(payload.decode('ascii'),sep=',',dtype=np.float64)
                    require(len(v)==288 and np.isfinite(v).all() and (v>=0).all(), f'Invalid monthly values: {key}')
                    annual.append(float(np.sum(v*np.repeat(DAYS,24)))/1000)
                require(not f.read(1) and len(annual)==len(EXPECTED), f'Invalid monthly row count: {key}')
            rows['annual_kwh']=annual
            partial=sidecar.with_suffix('.json.partial')
            partial.write_text(json.dumps(rows,separators=(',',':')),encoding='utf-8')
            os.replace(partial,sidecar)
            index['models'][spec['model_id']]=entry
            print(f'{key}: final hashes, row positions and annual cache verified',flush=True)
        require(len(index['models'])==len(products(args.source)),'Unexpected active model set')
        temporary=index_path.with_suffix('.json.partial')
        temporary.write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf-8')
        os.replace(temporary,index_path)
        print(f'ACTIVE: {index_path}',flush=True)
        return
    available=[]
    for spec in products(args.source):
        if args.model and spec['model_id'] != args.model:continue
        source=args.source/f"{spec['power_w']:g}_excel_files"
        if source.is_dir():available.append((spec,source))
    require(available, 'No matching standardized source folders found.')
    jobs=[]
    for spec,source in available:
        if spec['model_id'] in index['models']:
            entry=index['models'][spec['model_id']]
            require(all(file_hash(DEST/entry[name])==entry[name+'_sha256'] for name in ['hourly','monthly_hourly']), 'Existing bundled data differs; stopped.')
            print(f"{spec['model_id']}: verified existing tables; skipped",flush=True)
        else:
            if args.shards==1:
                jobs.append((spec,str(source)))
            else:
                for i in range(args.shards):
                    jobs.append((spec,str(source),(360*i//args.shards,360*(i+1)//args.shards-1)))
    # Bounded processes keep memory independent of the total number of XLSX files.
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        results=pool.map(convert,jobs)
        if args.shards>1:
            parts=list(results)
            results=[assemble(jobs[0][0],parts)] if parts else []
        for entry in results:
            index['models'][entry['model_id']]=entry
            temporary=index_path.with_suffix('.json.partial')
            temporary.write_text(json.dumps(index,ensure_ascii=False,indent=2),encoding='utf-8')
            os.replace(temporary,index_path)
    print(f"Ready: {len(index['models'])} bundled products; index: {index_path}",flush=True)

if __name__=='__main__':
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8')
    main()
