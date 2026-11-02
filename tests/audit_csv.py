"""Read-only source audit; output JSON evidence, never rewrites bundled CSVs."""
import csv, json
from pathlib import Path

BASE=Path(__file__).resolve().parents[1]
OUT=BASE/'output/checks'
fixture=json.loads((OUT/'ruby_fixtures.json').read_text(encoding='utf-8'))
DATA=BASE/'data/pv_generation/stride_1-1'
index=json.loads((DATA/'index.json').read_text(encoding='utf-8'))
samples=[]
sizes=[]
for case in fixture['cases']:
    settings=case['settings']; entry=index['models'][settings['model_id']]
    path=DATA/entry['hourly']
    sidecar=json.loads((DATA/entry['row_index']).read_text(encoding='utf-8'))
    number,a,b,offset=next((i+2,a,b,off) for i,(a,b,off) in enumerate(sidecar['rows']) if (a,b)==(settings['azimuth'],settings['tilt']))
    with path.open('rb') as file:
        header=next(csv.reader([file.readline().decode('utf-8-sig')]))
        file.seek(offset);row=next(csv.reader([file.readline().decode('utf-8')]))
        values=list(map(float,row[2:]))
    errors=[abs(a-b) for a,b in zip(values,case['values'])]
    assert len(values)==8760 and max(errors)<1e-10
    # Chosen daytime, nighttime, maximum and year-boundary values.
    hours=sorted(set([0,12,171*24+12,355*24+9,8759,values.index(max(values))]))
    records=[{'index':h,'column_1_based':h+3,'column_header':header[h+2],'csv_wh':values[h],'ruby_wh':case['values'][h]} for h in hours]
    monthly_path=DATA/entry['monthly_hourly']
    with monthly_path.open('rb') as file:
        file.readline()
        for line in file:
            first,second,payload=line.split(b',',2)
            if (int(first),int(second))==(settings['azimuth'],settings['tilt']):
                month_row=[first,second]+payload.decode('ascii').strip().split(',')
                break
        else:raise AssertionError('Monthly lookup row absent')
    monthly=list(map(float,month_row[2:]));offset=0;monthly_error=0
    for month,days in enumerate([31,28,31,30,31,30,31,31,30,31,30,31]):
        for h in range(24):
            avg=sum(values[offset+d*24+h] for d in range(days))/days
            monthly_error=max(monthly_error,abs(avg-monthly[month*24+h]))
        offset+=days*24
    assert monthly_error<1e-6
    samples.append({'model_id':settings['model_id'],'settings':settings,'source':path.relative_to(BASE).as_posix(),
                    'source_sha256':entry['hourly_sha256'],'csv_row_1_based':number,
                    'all_8760_max_abs_error_wh':max(errors),'monthly_mean_max_abs_error_wh':monthly_error,
                    'annual_kwh':sum(values)/1000,'peak_wh':max(values),'points':records})
for model,e in index['models'].items():
    p=DATA/e['hourly'];m=DATA/e['monthly_hourly']
    sizes.append({'model_id':model,'hourly_bytes':p.stat().st_size,'monthly_hourly_bytes':m.stat().st_size,
                  'angle_rows':e['angle_rows'],'hourly_sha256':e['hourly_sha256']})
result={'scope':'actual Ruby lookup + independent CSV row-position audit; source conversion verified every float64 value',
        'source_audit':samples,'angle_grid':index['angle_grid'],'angle_rows':360*91,
        'hourly_data_cells_per_model':360*91*8760,'csv_rows_including_header':360*91+1,'hourly_columns':8762,'models':sizes}
(OUT/'csv_audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'models':len(samples),'hourly_cells_checked':len(samples)*8760,'max_csv_error':max(s['all_8760_max_abs_error_wh'] for s in samples),'sizes':sizes},ensure_ascii=False))
