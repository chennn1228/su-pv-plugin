'use strict';
(function(root){
 const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
 const finite=v=>v!==null&&v!==''&&Number.isFinite(Number(v));
 function fit(p){
  const {voc,vmp,isc,imp}=p;
  if(![voc,vmp,isc,imp].every(v=>Number.isFinite(v)&&v>0)||!(vmp<voc&&imp<isc))return null;
  // Two-parameter characteristic-point interpolation, NOT a diode model.
  // I=Isc*[1-(V/Voc)^k]^m. Fit I(Vmp)=Imp and d(VI)/dV(Vmp)=0.
  const A=-Math.log(vmp/voc),target=Math.log(imp/isc);
  const logAtMPP=k=>{const t=k*A;return t>40?-1/k:Math.expm1(t)/k*Math.log(-Math.expm1(-t));};
  let lo=1e-7,hi=Math.max(100,2/-target);
  for(let i=0;i<100;i++){const k=(lo+hi)/2;if(logAtMPP(k)<target)lo=k;else hi=k;}
  const k=(lo+hi)/2,t=k*A,logM=(t>40?t:Math.log(Math.expm1(t)))-Math.log(k);
  function current(V){
   if(V<=0)return isc;if(V>=voc)return 0;
   const q=k*Math.log(V/voc),logFactor=q<-40?-Math.exp(logM+q):Math.exp(logM)*Math.log(-Math.expm1(q));
   return isc*Math.exp(logFactor);
  }
  return {k,logM,current,points:[...Array.from({length:181},(_,i)=>voc*i/180),vmp].sort((a,b)=>a-b).map(V=>({v:V,i:current(V),p:V*current(V)}))};
 }
 function parse(text){
  const rows=text.replace(/^\uFEFF/,'').trim().split(/\r?\n/).filter(s=>s.trim());
  if(rows.length<4||rows.length>5001)throw Error('曲线文件须包含表头及3—5000个测点。');
  const delimiter=rows[0].includes('\t')?'\t':',',header=rows.shift().split(delimiter).map(s=>s.trim().toLowerCase());
  const vi=header.indexOf('voltage_v'),ii=header.indexOf('current_a'),gi=header.indexOf('irradiance_wm2'),ti=header.indexOf('temperature_c');
  if(vi<0||ii<0)throw Error('曲线表头需要voltage_v,current_a；可增加irradiance_wm2,temperature_c。');
  const groups=new Map();
  rows.forEach((line,index)=>{const values=line.split(delimiter).map(s=>s.trim()),v=Number(values[vi]),i=Number(values[ii]);
   if(values[vi]===''||values[ii]===''||!Number.isFinite(v)||!Number.isFinite(i)||v<0||i<0)throw Error(`第${index+2}行电压/电流无效。`);
   const g=gi<0?null:Number(values[gi]),t=ti<0?null:Number(values[ti]);
   if(gi>=0&&(!values[gi]||!Number.isFinite(g)||g<=0)||ti>=0&&(!values[ti]||!Number.isFinite(t)))throw Error(`第${index+2}行工况无效。`);
   const key=JSON.stringify([g,t]);if(!groups.has(key))groups.set(key,{g,t,points:[]});groups.get(key).points.push({v,i,p:v*i});
  });
  if(groups.size>12)throw Error('同图最多显示12组工况，请拆分文件。');
  groups.forEach(group=>{group.points.sort((a,b)=>a.v-b.v);if(group.points.length<3||group.points.some((p,i)=>i&&p.v<=group.points[i-1].v))throw Error('每组工况至少3个不同电压的测点。');});
  return [...groups.values()];
 }
 const colors=['#3b79a8','#ae8d61','#799b86','#8a7fa3','#899fb1','#aa8585'];
 function base(title,labels,xmax,ymax,rightMax=null,xmin=0){
  const W=650,H=350,L=65,R=rightMax?65:30,T=48,B=54,pw=W-L-R,ph=H-T-B;
  const x=v=>L+(v-xmin)/(xmax-xmin)*pw,y=v=>T+ph-v/ymax*ph;
  let svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(title)}"><rect width="${W}" height="${H}" fill="white"/><g font-family="Microsoft YaHei, sans-serif" font-size="11" fill="#728492"><text x="${L}" y="20" font-size="13" fill="#35556d">${esc(title)}</text>`;
  for(let i=0;i<=5;i++){
   const xx=L+pw*i/5,yy=T+ph*i/5;
   svg+=`<path d="M${xx} ${T}V${T+ph}M${L} ${yy}H${L+pw}" stroke="#e6edf2" stroke-width="1" fill="none"/><text x="${xx}" y="${T+ph+18}" text-anchor="middle">${((xmin+(xmax-xmin)*i/5)).toFixed(xmax<100?1:0)}</text><text x="${L-9}" y="${yy+4}" text-anchor="end">${(ymax*(1-i/5)).toFixed(ymax<=30?1:0)}</text>`;
   if(rightMax)svg+=`<text x="${L+pw+9}" y="${yy+4}">${(rightMax*(1-i/5)).toFixed(0)}</text>`;
  }
  svg+=`<path d="M${L} ${T}V${T+ph}H${L+pw}${rightMax?'V'+T:''}" stroke="#8295a4" fill="none"/><text x="${L+pw/2}" y="${H-9}" text-anchor="middle">${esc(labels[0])}</text><text transform="translate(16 ${T+ph/2}) rotate(-90)" text-anchor="middle">${esc(labels[1])}</text>`;
  if(rightMax)svg+=`<text transform="translate(${W-12} ${T+ph/2}) rotate(90)" text-anchor="middle">功率 / W</text>`;
  return {svg,x,y,pw,ph,T,L,finish:s=>s+'</g></svg>'};
 }
 function line(points,x,y,color,dash=''){
  return `<polyline points="${points.map(p=>`${x(p[0]).toFixed(2)},${y(p[1]).toFixed(2)}`).join(' ')}" fill="none" stroke="${color}" stroke-width="2"${dash?' stroke-dasharray="'+dash+'"':''}/>`;
 }
 function iv(p,samples){
  const model=fit(p);let groups;
  if(samples&&samples.length)groups=samples;
  else if(model)groups=[{g:1000,t:25,points:model.points}];
  else return '<div class="curve-empty">请核对Voc、Vmp、Isc、Imp；需满足Vmp＜Voc、Imp＜Isc。</div>';
  const all=groups.flatMap(g=>g.points),vmax=Math.max(...all.map(p=>p.v))*1.08,imax=Math.max(...all.map(p=>p.i))*1.12,pmax=Math.max(...all.map(p=>p.p))*1.12;
  if(!(vmax>0&&imax>0&&pmax>0))return '<div class="curve-empty">测点中没有有效功率。</div>';
  const chart=base('电流–电压与功率–电压',['电压 / V','电流 / A'],vmax,imax,pmax);let svg=chart.svg;
  groups.forEach((group,i)=>{const col=colors[i%colors.length];svg+=line(group.points.map(p=>[p.v,p.i]),chart.x,chart.y,col);svg+=line(group.points.map(p=>[p.v,p.p*imax/pmax]),chart.x,chart.y,col,'5 3');
   const mpp=group.points.reduce((a,b)=>a.p>b.p?a:b);svg+=`<circle cx="${chart.x(mpp.v)}" cy="${chart.y(mpp.p*imax/pmax)}" r="3.5" fill="white" stroke="${col}" stroke-width="1.8"><title>MPP：${mpp.v.toFixed(2)} V / ${mpp.i.toFixed(2)} A / ${mpp.p.toFixed(2)} W</title></circle>`;
   group.points.filter((_,j)=>j%3===0).forEach(p=>{svg+=`<circle cx="${chart.x(p.v)}" cy="${chart.y(p.i)}" r="5" fill="transparent"><title>${p.v.toFixed(2)} V · ${p.i.toFixed(2)} A · ${p.p.toFixed(2)} W</title></circle>`;});
   const label=`${group.g===null?'G未填':group.g+' W/m²'} / ${group.t===null?'T未填':group.t+'℃'}`;svg+=`<g class="curve-condition-legend"><path d="M${chart.L+12} ${chart.T+14+i*16}h22" fill="none" stroke="${col}" stroke-width="2"/><text x="${chart.L+42}" y="${chart.T+18+i*16}" fill="${col}">${esc(label)}</text></g>`;
  });
  svg+=`<g class="curve-type-legend" aria-label="实线为电流–电压，虚线为功率–电压"><path d="M360 16h27" fill="none" stroke="${colors[0]}" stroke-width="2"/><text x="394" y="20">I–V</text><path d="M465 16h27" fill="none" stroke="${colors[0]}" stroke-width="2" stroke-dasharray="5 3"/><text x="499" y="20">P–V</text></g>`;
  return chart.finish(svg);
 }
 function thermal(p){
  const series=[['Isc',p.alpha_isc,'#739780'],['Voc',p.beta_voc,'#4e82aa'],['Pmax',p.gamma_p,'#b18f5e']].filter(s=>finite(s[1]));
  if(!series.length)return '<div class="curve-empty">填写温度系数后显示Isc、Voc、Pmax归一化温度特性。</div>';
  const points=series.map(s=>({name:s[0],color:s[2],points:Array.from({length:126},(_,i)=>[-40+i,100*(1+Number(s[1])/100*(-40+i-25))])}));
  const ymax=Math.max(140,...points.flatMap(s=>s.points.map(p=>p[1])))*1.03;
  const chart=base('Isc、Voc、Pmax温度特性',['电池温度 / ℃','相对25℃数值 / %'],85,ymax,null,-40);let svg=chart.svg;
  svg+=`<path d="M${chart.x(25)} ${chart.T}V${chart.T+chart.ph}" stroke="#c4d1db" stroke-dasharray="4 4"/><text x="${chart.x(25)+5}" y="${chart.T+chart.ph-8}">25℃</text>`;
  points.forEach((s,i)=>{svg+=line(s.points,chart.x,chart.y,s.color);svg+=`<g class="temperature-legend"><path d="M${chart.L+12} ${chart.T+14+i*17}h22" fill="none" stroke="${s.color}" stroke-width="2"/><text x="${chart.L+42}" y="${chart.T+18+i*17}" fill="${s.color}">${s.name} · ${series[i][1]} %/℃</text></g>`;});
  return chart.finish(svg);
 }
 root.PVCharacteristics={fit,parse,iv,thermal};
 if(typeof module!=='undefined')module.exports=root.PVCharacteristics;
})(typeof window!=='undefined'?window:globalThis);
