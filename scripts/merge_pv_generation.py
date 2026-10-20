"""Build bundled PV lookup CSVs from per-angle Excel simulations.

Run: python scripts/merge_pv_generation.py
Each product writes data/pv_generation/<model>_<power>W/{hourly,monthly_hourly}.csv.
Rows are angle pairs; columns are hourly intervals (8760) or monthly hourly means (288).
The source timestamps denote interval ends; output headers denote interval starts.
"""
import argparse
import calendar
import csv
import datetime as dt
import hashlib
import json
import math
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / 'data' / 'PV output'
DEST = ROOT / 'data' / 'pv_generation'
NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
NAME = re.compile(r'^(\d+)-(\d+)-逐时发电量\.xlsx$')
A_CELLS = re.compile(rb'<c r="A(\d+)"[^>]*t="s"[^>]*><v>(\d+)</v></c>')
B_CELLS = re.compile(rb'<c r="B(\d+)"([^>]*)><v>([^<]*)</v></c>')
EXPECTED = {(a, b) for a in range(90, 271, 5) for b in range(0, 91, 3)}
STARTS = [dt.datetime(2001, 1, 1) + dt.timedelta(hours=i) for i in range(8760)]
ENDS = [t + dt.timedelta(hours=1) for t in STARTS]
TIME_LABELS = [f'Year {t.year - 2000} {calendar.month_abbr[t.month]} {t.day:02d} {t.hour}:00' for t in ENDS]
GROUPS = [(t.month - 1) * 24 + t.hour for t in STARTS]
DAYS = [calendar.monthrange(2001, m)[1] for m in range(1, 13)]
HOURLY_HEADER = ['azimuth_deg', 'tilt_deg'] + [f'{t.month:02d}-{t.day:02d}_{t.hour:02d}:00-{t.hour+1:02d}:00_Wh' for t in STARTS]
MEAN_HEADER = ['azimuth_deg', 'tilt_deg'] + [f'{m:02d}_{h:02d}:00-{h+1:02d}:00_Wh' for m in range(1, 13) for h in range(24)]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def slug(model):
    return re.sub(r'[^A-Za-z0-9.-]+', '_', model).strip('_')


def products():
    data = (ROOT / 'data' / 'PV panel.csv').read_bytes()
    try:
        text = data.decode('utf-8-sig')
    except UnicodeDecodeError:
        text = data.decode('gb18030')
    # The bundled index defines the products currently in scope; unused source rows stay archived in the original CSV.
    active_ids = set(json.loads((DEST / 'index.json').read_text(encoding='utf-8'))['models'])
    result = []
    for row in csv.DictReader(text.splitlines()):
        if row['型号'].strip() not in active_ids:
            continue
        dimensions = re.fullmatch(r'(\d+(?:\.\d+)?)\s*[×xX*]\s*(\d+(?:\.\d+)?)\s*[×xX*]\s*(\d+(?:\.\d+)?)\s*mm', row['尺寸'].strip(), re.I)
        require(dimensions, f"Invalid dimensions: {row['型号']}")
        power = float(row['STC-Pmax(W)'])
        result.append({'model_id': row['型号'].strip(), 'manufacturer': row['生产商'], 'power_w': power,
                       'dimensions_mm': list(map(float, dimensions.groups()))})
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


def digest(values):
    return hashlib.sha256(array('d', values).tobytes()).digest()


def file_hash(path):
    with path.open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def verify_csv(path, header, checks):
    with path.open(encoding='utf-8-sig', newline='') as handle:
        reader = csv.reader(handle)
        require(next(reader) == header, f'Invalid saved header: {path}')
        count = 0
        for count, row in enumerate(reader, 1):
            require(count <= len(checks) and len(row) == len(header), f'Invalid saved dimensions: {path}')
            key, expected = checks[count - 1]
            require(tuple(map(int, row[:2])) == key and digest(list(map(float, row[2:]))) == expected, f'Saved values changed: {path}')
        require(count == len(checks), f'Missing saved rows: {path}')


def convert(spec, source):
    key = f"{slug(spec['model_id'])}_{spec['power_w']:g}W"
    folder = DEST / key
    files = sorted((int(m[1]), int(m[2]), path) for path in source.iterdir() if (m := NAME.fullmatch(path.name)))
    require(len(files) == len(EXPECTED) and {(a, b) for a, b, _ in files} == EXPECTED, f'Incomplete or duplicate angles: {source}')
    controls = xlsx_rows(source / 'results.xlsx')
    require(controls[0]['A'] == '方位角deg' and controls[0]['B'] == '倾角deg', f'Unexpected controls: {source}')
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
    checks_h, checks_m = [], []
    max_month_error = max_year_error = 0.0
    with partial_h.open('x', encoding='utf-8-sig', newline='') as fh, partial_m.open('x', encoding='utf-8-sig', newline='') as fm:
        wh, wm = csv.writer(fh), csv.writer(fm)
        wh.writerow(HOURLY_HEADER);wm.writerow(MEAN_HEADER)
        for i, (a, b, path) in enumerate(files, 1):
            with zipfile.ZipFile(path) as z:
                require(z.read('xl/sharedStrings.xml') == strings, f'Time strings changed: {path}')
                xml = z.read('xl/worksheets/sheet1.xml')
            require(A_CELLS.findall(xml) == reference_a, f'Time axis changed: {path}')
            cells = B_CELLS.findall(xml)
            require(len(cells) == 8761 and cells[0] == reference_b, f'Incomplete hourly cells: {path}')
            values, sums = [], [0.0]*288
            for n, (row_id, attrs, raw) in enumerate(cells[1:]):
                value = float(raw)
                require(int(row_id) == n+2 and b't=' not in attrs and math.isfinite(value) and value >= 0, f'Invalid hourly value: {path}')
                values.append(value);sums[GROUPS[n]] += value
            monthly = [math.fsum(sums[m*24:(m+1)*24]) for m in range(12)]
            month_error = max(abs(x-y) for x, y in zip(monthly, totals[(a,b)][:12]))
            year_error = abs(math.fsum(values)-totals[(a,b)][12])
            require(month_error < 1e-5 and year_error < 1e-5, f'Month/year control mismatch: {path}')
            means = [sums[n]/DAYS[n//24] for n in range(288)]
            wh.writerow([a,b]+values);wm.writerow([a,b]+means)
            checks_h.append(((a,b),digest(values)));checks_m.append(((a,b),digest(means)))
            max_month_error = max(max_month_error,month_error);max_year_error = max(max_year_error,year_error)
            if i%200 == 0 or i == len(files):
                print(f'{key}: {i}/{len(files)} angle rows checked', flush=True)
    verify_csv(partial_h, HOURLY_HEADER, checks_h)
    verify_csv(partial_m, MEAN_HEADER, checks_m)
    # Rename only after both saved tables have passed the full numeric round-trip check.
    os.rename(partial_h, hourly);os.rename(partial_m, mean)
    print(f'{key}: complete; monthly max error {max_month_error:.3g} Wh, annual {max_year_error:.3g} Wh',flush=True)
    return dict(spec, source_dir=source.relative_to(ROOT).as_posix(), hourly=hourly.relative_to(DEST).as_posix(),
                monthly_hourly=mean.relative_to(DEST).as_posix(), angle_rows=len(files), hourly_columns=8762,
                monthly_hourly_columns=290, hourly_sha256=file_hash(hourly), monthly_hourly_sha256=file_hash(mean),
                max_month_error_wh=max_month_error, max_annual_error_wh=max_year_error)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', help='Convert only this exact model ID; merge it into the index.')
    args=parser.parse_args()
    DEST.mkdir(parents=True,exist_ok=True)
    index_path=DEST/'index.json'
    index=json.loads(index_path.read_text(encoding='utf-8')) if index_path.exists() else {'schema':1,'unit':'Wh','calendar':'non_leap','hourly_intervals':8760,'monthly_hourly_intervals':288,'models':{}}
    available=[]
    for spec in products():
        if args.model and spec['model_id'] != args.model:continue
        source=RAW/f"{slug(spec['model_id'])}_{spec['power_w']:g} W"
        if source.is_dir():available.append((spec,source))
    require(available, 'No matching standardized source folders found.')
    for spec,source in available:
        if spec['model_id'] in index['models']:
            entry=index['models'][spec['model_id']]
            require(all(file_hash(DEST/entry[name])==entry[name+'_sha256'] for name in ['hourly','monthly_hourly']), 'Existing bundled data differs; stopped.')
            print(f"{spec['model_id']}: verified existing tables; skipped",flush=True)
            continue
        index['models'][spec['model_id']]=convert(spec,source)
        temporary=index_path.with_suffix('.json.partial')
        with temporary.open('x',encoding='utf-8') as handle:json.dump(index,handle,ensure_ascii=False,indent=2)
        os.replace(temporary,index_path)
    print(f"Ready: {len(index['models'])} bundled products; index: {index_path}",flush=True)

if __name__=='__main__':
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8')
    main()
