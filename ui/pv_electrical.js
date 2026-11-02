'use strict';
(function(){
 const el=id=>document.getElementById(id);let snapshot=null,result=null,request=0,timer=null,signature=null,curveSamples=null,betaBasis='entered',objective='inverters';
 const fields=[
 ['voc','开路电压 Voc / V',0.001,3000],['vmp','最大功率点电压 Vmp / V',0.001,3000],['isc','短路电流 Isc / A',0.001,3000],['imp','最大功率点电流 Imp / A',0.001,3000],
 ['beta_voc','Voc温度系数 / %·℃⁻¹',-2,0],['beta_vmp','Vmp温度系数 / %·℃⁻¹',-2,0],['module_max','组件最大系统电压 / V',1,3000],['tmin','最低设计温度 / ℃',-80,40],['tmax','最高电池温度 / ℃',25,120],['isc_factor','短路电流设计系数',1,3],
 ['dc_max','最大直流电压 / V',1,3000],['mppt_min','MPPT下限 / V',1,3000],['mppt_max','MPPT上限 / V',1,3000],['mppt_current','每路MPPT工作电流 / A',0.001,5000],['mppt_isc','每路MPPT短路电流 / A',0.001,5000],['port_current','单端口工作电流 / A',0.001,5000],['port_isc','单端口短路电流 / A',0.001,5000],['mppts','MPPT路数',1,64],['ports','每路输入串数上限',1,64],['ac_kw','额定交流功率 / kW',0.01,100000],['dc_kw','厂家直流容量上限 / kWp',0.01,150000],['dc_ac_max','设计容配比上限',0.1,3]
 ];
 const designKeys=['tmin','tmax','isc_factor','dc_ac_max'];
 const inverterKeys=fields.slice(10).map(f=>f[0]).filter(id=>!designKeys.includes(id));
 fields.forEach(([id,label,min,max],i)=>{const node=document.createElement('label');node.textContent=label;node.htmlFor=id;node.title=id==='isc_factor'?'项目初设值；按适用标准、厂家要求及双面增益调整':designKeys.includes(id)?'项目初设值，可调；不是组件出厂参数':id==='beta_vmp'?'≈：由γP−αIsc估算，假定αImp≈αIsc；可改为厂家实值':id==='dc_kw'?'可选：厂家明确规定时填写；留空仅按设计容配比限制':'';const input=document.createElement('input');Object.assign(input,{id,type:'number',min,max,step:['mppts','ports'].includes(id)?'1':'any',required:id!=='dc_kw',placeholder:id==='dc_kw'?'未规定':'待填写'});node.append(input);el(designKeys.includes(id)?'designFields':i<10?'moduleFields':'inverterFields').append(node);});
 const optionalFields=[['alpha_isc','Isc温度系数 / %·℃⁻¹',-2,2],['gamma_p','Pmax温度系数 / %·℃⁻¹',-2,2]];
 optionalFields.forEach(([id,label,min,max])=>{const node=document.createElement('label');node.textContent=label+'（温度图）';node.htmlFor=id;const input=document.createElement('input');Object.assign(input,{id,type:'number',min,max,step:'any',placeholder:'可选，待核实'});node.append(input);el('moduleFields').append(node);});
 const betaBadge=document.createElement('button');betaBadge.type='button';betaBadge.id='estimateBeta';betaBadge.setAttribute('aria-label','估算Vmp温度系数');betaBadge.className='estimate-badge';betaBadge.textContent='≈';betaBadge.title='以 γP − αIsc 估算 βVmp；αImp≈αIsc。点击重新估算。';el('beta_vmp').parentElement.append(betaBadge);
 function estimateBeta(){const gamma=el('gamma_p').value,alpha=el('alpha_isc').value;if(gamma!==''&&alpha!==''){el('beta_vmp').value=Number((Number(gamma)-Number(alpha)).toFixed(5));betaBasis='estimated';}else{el('beta_vmp').value='';betaBasis='entered';}betaBadge.classList.toggle('active',betaBasis==='estimated');}
 function selectObjective(value){objective=['inverters','strings','balanced'].includes(value)?value:'inverters';document.querySelectorAll('[data-objective]').forEach(button=>{const active=button.dataset.objective===objective;button.classList.toggle('active',active);button.setAttribute('aria-pressed',String(active));});}
 function setValues(values){Object.entries(values||{}).forEach(([id,value])=>{if(el(id))el(id).value=value??'';});}
 function applyInverter(id){const profile=snapshot?.presets?.inverters?.find(p=>p.id===id);if(!profile){el('inverterPreset').title='';return;}setValues(profile.values);el('inverterPreset').title=profile.note+'\n'+profile.source;['mppt_current','mppt_isc','port_isc'].forEach(key=>el(key).title=profile.note);}
 function resetPresets(){selectObjective('inverters');fields.forEach(([id])=>el(id).value='');optionalFields.forEach(([id])=>el(id).value='');setValues(snapshot.presets?.module_values||snapshot.spec.electrical);setValues(snapshot.presets?.design?.values||{isc_factor:1.25});el('series_count').replaceChildren(new Option('自动配置','0'));const profiles=snapshot.presets?.inverters||[];el('inverterPreset').replaceChildren(...profiles.map(p=>new Option(p.label,p.id)),new Option('自定义','custom'));if(profiles.length){el('inverterPreset').value=profiles[0].id;applyInverter(profiles[0].id);}else el('device_name').value='';estimateBeta();curveSamples=null;el('ivStatus').textContent='';invalidate();constraints(null);}
 function renderCurves(){if(!snapshot)return;const p=params();el('ivCurve').innerHTML=PVCharacteristics.iv(p,curveSamples);el('temperatureCurve').innerHTML=PVCharacteristics.thermal(p);el('curveBasis').textContent=curveSamples?'实测曲线':'STC · 25℃ · 1000 W/m² · 参数拟合';const missing=[['Isc',p.alpha_isc],['Voc',p.beta_voc],['Pmax',p.gamma_p]].filter(([,v])=>v===null).map(([name])=>name);el('temperatureStatus').textContent=missing.length?'待补：'+missing.map(name=>'μ'+name).join('、'):'';el('clearCurves').hidden=!curveSamples;}
 const palette=['#3f7eae','#8c83b2','#58a294','#b59b55','#b17fa0','#729bb6','#8fa35f','#bc8c74','#5a9fae','#a99c77','#777db0','#799d86'];
 const stringColor=id=>id==='unassigned'?'#aab5bd':palette[id-1]||`hsl(${((id-1)*137.508)%360},32%,48%)`;
 let focusedString=null;
 function params(){const data={device_name:el('device_name').value,inverter_preset:el('inverterPreset').value,beta_vmp_basis:betaBasis,objective,series_count:Number(el('series_count').value)};fields.forEach(([id])=>data[id]=el(id).value===''?null:Number(el(id).value));optionalFields.forEach(([id])=>data[id]=el(id).value===''?null:Number(el(id).value));data.curve_samples=curveSamples;return data;}
 function setStatus(kind,text){
  const node=el('status');node.replaceChildren();node.className=kind==='error'?'error':'';
  if(!text)return;
  const icon=document.createElement('span');icon.className='status-symbol';icon.setAttribute('aria-hidden','true');icon.textContent=kind==='error'?'!':kind==='saved'?'✓':'…';
  const label=document.createElement('span');label.textContent=text;node.append(icon,label);
 }
 function normalizeResult(data){
  if((objective!=='inverters'&&data.selection?.objective!==objective)||(data.selection?.objective&&data.selection.objective!==objective))throw Error('请重新加载插件后切换配置目标。');
  const expected=new Set(snapshot.records.map(record=>record.key)),assigned=new Set(),byId=new Map();
  if(!Array.isArray(data.strings)||!Array.isArray(data.inverters))throw Error('电气结果不完整，请重新生成。');
  const strings=data.strings.map(str=>{
   if(!Array.isArray(str.panels)||!str.panels.length||byId.has(str.id))throw Error('组串数据无效，请重新生成。');
   for(const key of str.panels){if(!expected.has(key)||assigned.has(key))throw Error('组串存在重复或遗漏，请重新生成。');assigned.add(key);}
   const item={...str,series_count:str.panels.length};byId.set(str.id,item);return item;
  });
  if(assigned.size!==expected.size||Number(data.connected_count)!==expected.size)throw Error('方案未覆盖全部组件，请重新加载插件后生成。');
  const referenced=new Set();
  const inverters=data.inverters.map(inv=>({...inv,mppts:inv.mppts.map(slot=>{
   const linked=slot.strings.map(id=>{const str=byId.get(id);if(!str||referenced.has(id)||str.inverter!==inv.id||str.mppt!==slot.id)throw Error('MPPT连接数据无效，请重新生成。');referenced.add(id);return str;});
   const lengths=[...new Set(linked.map(str=>str.series_count))];if(lengths.length!==1)throw Error('同一MPPT的并联组串须等长。');
   return {...slot,series_count:lengths[0]};
  })}));
  if(referenced.size!==strings.length)throw Error('组串未完整分配至MPPT。');
  const histogram=new Map();strings.forEach(str=>histogram.set(str.series_count,(histogram.get(str.series_count)||0)+1));
  const series_sizes=[...histogram].sort((a,b)=>b[0]-a[0]).map(([series_count,string_count])=>({series_count,string_count}));
  if(!Number.isInteger(Number(data.series_count))||Number(data.series_count)<Math.max(...strings.map(str=>str.series_count)))throw Error('串长上限数据无效，请重新生成。');
  const current={series_count:Number(data.series_count),connected_count:assigned.size,unassigned:0,string_count:strings.length,string_sizes:series_sizes,inverter_count:inverters.length,mppt_count:inverters.reduce((sum,inv)=>sum+inv.mppts.length,0)};
  const candidates=(Array.isArray(data.candidates)?data.candidates:[]).map(item=>{
   const n=Number(item.series_count),connected=Number(item.connected_count);
   if(connected!==expected.size||!Number.isInteger(n)||n<1)return null;
   const sizes=item.string_sizes||item.series_sizes||(Number.isInteger(connected/n)?[{series_count:n,string_count:connected/n}]:null);
   if(!sizes||sizes.some(size=>!Number.isInteger(size.series_count)||!Number.isInteger(size.string_count)||size.series_count<1||size.string_count<1||size.series_count>n)||sizes.reduce((sum,size)=>sum+size.series_count*size.string_count,0)!==connected)return null;
   return {...item,series_count:n,connected_count:connected,string_sizes:sizes,string_count:sizes.reduce((sum,size)=>sum+size.string_count,0),unassigned:0};
  }).filter(Boolean);
  const merged=new Map(candidates.map(candidate=>[candidate.series_count,candidate]));merged.set(current.series_count,current);
  return {...data,series_count:current.series_count,strings,inverters,series_sizes,unassigned:[],candidates:[...merged.values()]};
 }
 function invalidate(preservePlan=false){clearTimeout(timer);if(!preservePlan)PVStringPlan.clear(snapshot?.records.length);request++;signature=null;result=null;focusedString=null;el('map').classList.remove('has-focus');el('save').disabled=el('export').disabled=true;['map','assignments','diagram','stringLegend','circuitSummary'].forEach(id=>el(id).replaceChildren());['connected','strings','inverters'].forEach(id=>el(id).textContent='—');setStatus('','');renderCurves();constraints(null);}
 function submit(save=false){clearTimeout(timer);if(!snapshot)return;if(!el('electricalForm').reportValidity())return;PVStringPlan.pending();request++;signature=JSON.stringify(params());setStatus('busy',save?'保存中…':'计算中…');if(window.sketchup)window.sketchup[save?'save':'calculate'](JSON.stringify({input:params(),request_id:request}));}
 function calculateIfValid(){if(snapshot&&el('electricalForm').checkValidity()&&!snapshot.module_errors.length)submit();}
 const fmt=(v,n=2)=>Number(v).toFixed(n);
 function diagram(r){return PVElectricalDiagram.render(r,params(),snapshot.spec);}
 function focusString(id){focusedString=focusedString===id?null:id;el('map').classList.toggle('has-focus',focusedString!==null);el('map').querySelectorAll('[data-string]').forEach(node=>node.classList.toggle('is-focused',node.dataset.string===focusedString));el('stringLegend').querySelectorAll('button').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.string===focusedString)));el('assignments').querySelectorAll('tr[data-string]').forEach(row=>row.classList.toggle('is-focused',row.dataset.string===focusedString));}
 function renderCircuitSummary(r){const items=[['接入组件',r.connected_count,'块'],['组串',r.strings.length,'串'],['逆变器',r.inverters.length,'台'],['交流额定功率',fmt(r.inverters.length*params().ac_kw,1),'kW']];el('circuitSummary').innerHTML=items.map(([label,value,unit])=>`<article><span>${label}</span><div><strong>${value}</strong><small>${unit}</small></div></article>`).join('');}
 function map(r){
  const first=snapshot.records[0],u=first.axes[0],v=first.axes[1],dot=(a,b)=>a.reduce((s,x,i)=>s+x*b[i],0),origin=first.origin_mm;
  const coords=snapshot.records.map(p=>{const local=p.origin_mm.map((x,i)=>x-origin[i]);return {key:p.key,x:dot(local,u),y:dot(local,v),width:snapshot.spec.width_mm,length:snapshot.spec.length_mm};});
  const xs=coords.map(p=>p.x),ys=coords.map(p=>p.y),loX=Math.min(...xs),loY=Math.min(...ys),width=Math.max(...coords.map(p=>p.x+p.width))-loX,height=Math.max(...coords.map(p=>p.y+p.length))-loY;
  const pad=Math.max(width,height)*.06,sw=Math.max(width,1)+2*pad,sh=Math.max(height,1)+2*pad;const ids=new Map();r.strings.forEach(s=>s.panels.forEach((key,i)=>ids.set(key,[s,i])));
  let svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${loX-pad} ${loY-pad} ${sw} ${sh}"><title>沿首块组件法线查看组串分配；不同朝向分组计算</title>`;
  coords.forEach(p=>{const a=ids.get(p.key),id=a?String(a[0].id):'unassigned',col=stringColor(a?a[0].id:'unassigned'),label=a?'S'+a[0].id:'—';svg+=`<g data-string="${id}"><title>${a?`S${a[0].id} · INV ${a[0].inverter} · MPPT ${a[0].mppt} · ${a[1]+1}/${a[0].panels.length}`:'未接入'}</title><rect x="${p.x}" y="${p.y}" width="${p.width*.94}" height="${p.length*.97}" fill="${col}" fill-opacity="${a?'.5':'.15'}" stroke="${col}" stroke-width="${Math.max(width,height)/950}"/><text x="${p.x+p.width*.47}" y="${p.y+p.length*.56}" text-anchor="middle" font-family="Microsoft YaHei" font-size="${p.width*(label.length>3?.25:.34)}" fill="#29485d">${label}</text></g>`;});
  el('map').innerHTML=svg+'</svg>';
  el('stringLegend').innerHTML=r.strings.map(s=>`<button type="button" data-string="${s.id}" aria-pressed="false" title="INV ${s.inverter} · MPPT ${s.mppt} · ${s.panels.length}块"><i style="--swatch:${stringColor(s.id)}"></i>S${s.id}</button>`).join('')+(r.unassigned.length?`<button type="button" data-string="unassigned" aria-pressed="false"><i style="--swatch:${stringColor('unassigned')}"></i>未接入 · ${r.unassigned.length}块</button>`:'');
  focusedString=null;el('map').classList.remove('has-focus');
 }
 function constraints(r){
  const p=params(),math=tex=>'<div class="math-equation">'+PVMath.html(tex)+'</div>',raw=String.raw;
  const card=(title,formula,answer)=>'<article class="formula-card"><strong>'+title+'</strong>'+formula+'<div class="formula-answer">'+answer+'</div></article>';
  const empty='<span class="muted">—</span>';
  el('formulae').innerHTML=[
   card('温度修正',math(raw`V(T)=V_{\mathrm{STC}}\!\left[1+\frac{\beta}{100}(T-25)\right]`)+math(raw`\beta_{V_{\mathrm{mp}}}\approx\gamma_P-\alpha_{I_{\mathrm{sc}}}`),r?math(raw`\begin{aligned}V_{\mathrm{oc,cold}}&=${fmt(r.voc_cold)}\,\mathrm V\\V_{\mathrm{mp,cold}}&=${fmt(r.vmp_cold)}\,\mathrm V\\V_{\mathrm{mp,hot}}&=${fmt(r.vmp_hot)}\,\mathrm V\end{aligned}`):empty),
   card('串联数量',math(raw`N_sV_{\mathrm{oc,cold}}<\min(V_{\mathrm{dc,max}},V_{\mathrm{sys}})`)+math(raw`\begin{aligned}N_s&\ge\left\lceil\frac{V_{\mathrm{MPPT,min}}}{V_{\mathrm{mp,hot}}}\right\rceil\\N_s&\le\left\lfloor\frac{V_{\mathrm{MPPT,max}}}{V_{\mathrm{mp,cold}}}\right\rfloor\end{aligned}`),r?math(raw`${r.range[0]}\le N_s\le ${r.range[1]},\qquad N_s\in\{${r.series_sizes.map(s=>s.series_count).join(',')}\}`):empty),
   card('单端口电流',math(raw`\begin{aligned}I_{\mathrm{mp}}&\le I_{\mathrm{port,max}}\\k_I I_{\mathrm{sc}}&\le I_{\mathrm{port,sc}}\end{aligned}`),r?math(raw`I_{\mathrm{mp}}=${fmt(p.imp)}\,\mathrm A,\quad k_I I_{\mathrm{sc}}=${fmt(r.isc_design)}\,\mathrm A`):empty),
   card('每路并联串数',math(raw`\begin{aligned}N_pI_{\mathrm{mp}}&\le I_{\mathrm{MPPT,max}}\\N_pk_I I_{\mathrm{sc}}&\le I_{\mathrm{sc,max}}\\N_p&\le n_{\mathrm{ports}}\end{aligned}`),r?math(raw`N_p\le ${r.parallel_max},\qquad k_I I_{\mathrm{sc}}=${fmt(r.isc_design)}\,\mathrm A`):empty),
   card('逆变器容量',math(p.dc_kw===null?raw`P_{\mathrm{DC},k}\le r_{\max}P_{\mathrm{AC},k}`:raw`P_{\mathrm{DC},k}\le\min(P_{\mathrm{DC,max}},r_{\max}P_{\mathrm{AC},k})`)+math(raw`n_{\mathrm{MPPT,used},k}\le n_{\mathrm{MPPT}}`),r?math(raw`P_{\mathrm{DC,lim}}=${fmt(r.dc_capacity_w/1000)}\,\mathrm{kWp},\quad r=${fmt(r.dc_ac_ratio)}`):empty),
   card('接入数量',math(raw`\begin{aligned}N_{\mathrm{in}}&=\sum_{s=1}^{m}n_s=N_{\mathrm{selected}}\\n_s&=n_t\quad(s,t\in\mathrm{MPPT}_j)\end{aligned}`),r?math(raw`N_{\mathrm{in}}=${r.connected_count},\quad m=${r.strings.length},\quad R=0`):empty)
  ].join('');
 }
 window.PVElectrical={receive(data){snapshot=data;el('product').textContent=data.spec.manufacturer+' · '+data.spec.model;el('selection').textContent=data.records.length+' 块 · '+fmt(data.records.length*data.spec.power_w/1000)+' kWp';resetPresets();el('catalogErrors').hidden=!data.module_errors.length;el('catalogErrors').textContent='参数冲突：'+data.module_errors.join('；');if(data.saved){if(data.saved.series_count>0)el('series_count').add(new Option(data.saved.series_count+' 块',String(data.saved.series_count)));setValues(data.saved);selectObjective(data.saved.objective);el('inverterPreset').value=data.saved.inverter_preset||'custom';betaBasis=data.saved.beta_vmp_basis||'entered';betaBadge.classList.toggle('active',betaBasis==='estimated');curveSamples=data.saved.curve_samples||null;renderCurves();}calculateIfValid();},
  result(data){if(data.request_id!==request||signature!==JSON.stringify(params()))return;try{data=normalizeResult(data);result=data;const selected=Number(el('series_count').value);PVStringPlan.show(data,snapshot.records.length,selected);el('connected').textContent=data.connected_count+' / '+snapshot.records.length;const lengths=data.series_sizes.map(s=>s.series_count),span=Math.min(...lengths)===Math.max(...lengths)?lengths[0]:Math.min(...lengths)+'–'+Math.max(...lengths);el('strings').textContent=data.strings.length+'串 / '+span+'块';el('inverters').textContent=data.inverters.length+'台';setStatus(data.saved?'saved':'',data.saved?'已保存':'');el('save').disabled=el('export').disabled=false;map(data);el('diagram').innerHTML=diagram(data);renderCircuitSummary(data);constraints(data);el('assignments').innerHTML='<table><thead><tr><th>组串</th><th>逆变器</th><th>MPPT</th><th>组件数</th></tr></thead><tbody>'+data.strings.map(s=>`<tr data-string="${s.id}"><td><span class="table-swatch" style="--swatch:${stringColor(s.id)}"></span>S${s.id}</td><td>INV ${s.inverter}</td><td>${s.mppt}</td><td>${s.panels.length}</td></tr>`).join('')+'</tbody></table>';}catch(error){PVElectrical.fail(/[\u4e00-\u9fff]/.test(error.message)?error.message:'结果显示失败，请关闭窗口并重新加载插件。',data.request_id,'internal');}},
  fail(message,id,kind='constraint'){if(id!=null&&id!==request)return;invalidate();setStatus('error',message);PVStringPlan.unavailable(kind);}
 };
 window.PV={exported(data){if(data.error)PVElectrical.fail(data.error);}};
 el('stringLegend').addEventListener('click',event=>{const button=event.target.closest('button[data-string]');if(button)focusString(button.dataset.string);});
 el('map').addEventListener('click',event=>{const group=event.target.closest('g[data-string]');if(group)focusString(group.dataset.string);});
 el('electricalForm').addEventListener('submit',event=>{event.preventDefault();submit();});
 el('electricalForm').addEventListener('input',event=>{if(event.target.id==='beta_vmp'){betaBasis='entered';betaBadge.classList.remove('active');}if(['alpha_isc','gamma_p'].includes(event.target.id)&&betaBasis==='estimated')estimateBeta();if(inverterKeys.includes(event.target.id)||event.target.id==='device_name'){if(el('inverterPreset').value!=='custom'&&event.target.id!=='device_name')el('device_name').value+='（自定义）';el('inverterPreset').value='custom';el('inverterPreset').title='';}invalidate();clearTimeout(timer);if(el('electricalForm').checkValidity())timer=setTimeout(()=>submit(),350);});
 document.querySelectorAll('[data-objective]').forEach(button=>button.addEventListener('click',()=>{if(!snapshot)return;selectObjective(button.dataset.objective);invalidate();calculateIfValid();}));
 el('series_count').addEventListener('change',()=>{invalidate(true);submit();});
 PVStringPlan.onSelect(()=>{invalidate(true);submit();});
 el('resetPresets').addEventListener('click',()=>{if(snapshot){resetPresets();calculateIfValid();}});
 el('inverterPreset').addEventListener('change',()=>{applyInverter(el('inverterPreset').value);invalidate();calculateIfValid();});
 el('importCurve').addEventListener('keydown',event=>{if(['Enter',' '].includes(event.key)){event.preventDefault();el('curveFile').click();}});
 betaBadge.addEventListener('click',()=>{estimateBeta();invalidate();calculateIfValid();});
 el('save').addEventListener('click',()=>{if(result)submit(true);});el('repick').addEventListener('click',()=>window.sketchup&&window.sketchup.repick());
 el('export').addEventListener('click',()=>{if(result&&window.sketchup)window.sketchup.export_figure(JSON.stringify({format:'svg',body:diagram(result)}));});
 document.querySelectorAll('[data-pane]').forEach(button=>button.addEventListener('click',()=>{document.querySelectorAll('[data-pane]').forEach(b=>b.classList.toggle('active',b===button));['characteristics','constraints','layout','circuit'].forEach(id=>el(id).hidden=id!==button.dataset.pane);}));
 el('curveFile').addEventListener('change',async()=>{const file=el('curveFile').files[0];if(!file)return;try{if(file.size>1024*1024)throw Error('曲线文件请控制在1 MB内。');curveSamples=PVCharacteristics.parse(await file.text());el('ivStatus').textContent=file.name+' · '+curveSamples.length+'组工况';renderCurves();}catch(error){el('ivStatus').textContent=error.message;}finally{el('curveFile').value='';}});
 el('clearCurves').addEventListener('click',()=>{curveSamples=null;el('ivStatus').textContent='';renderCurves();});
 PVMath.render();constraints(null);
 if(window.sketchup)window.sketchup.ready();
})();
