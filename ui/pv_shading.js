'use strict';
// Pure numerical experiment; no SketchUp API, mesh entities, network or stored sun tables.
// NOAA general equations: https://gml.noaa.gov/grad/solcalc/solareqns.PDF
(function install(root){
 const DEG=Math.PI/180,EPS=1e-8;
 const site=Object.freeze({name:'扬州实验点',latitude:32.4,longitude:119.4,timezone:8,year:2025});
 const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
 function validateLocation(location){
  solarPosition({...location,month:1,day:1,hour:12});
  if((Date.UTC(location.year+1,0,1)-Date.UTC(location.year,0,1))/86400000!==365)throw Error('当前出力表为365天，请选非闰年。');
  return {...location};
 }
 function solarPosition({latitude,longitude,timezone,year,month,day,hour}){
  if(![latitude,longitude,timezone,year,month,day,hour].every(Number.isFinite)||Math.abs(latitude)>90||Math.abs(longitude)>180||Math.abs(timezone)>14||!Number.isInteger(year)||year<1900||year>2100||hour<0||hour>=24)throw Error('太阳位置输入无效');
  const date=new Date(Date.UTC(year,month-1,day));
  if(date.getUTCFullYear()!==year||date.getUTCMonth()!==month-1||date.getUTCDate()!==day)throw Error('太阳位置日期无效');
  const doy=(date-Date.UTC(year,0,1))/86400000+1,days=(Date.UTC(year+1,0,1)-Date.UTC(year,0,1))/86400000;
  const g=2*Math.PI/days*(doy-1+(hour-12)/24);
  const eq=229.18*(.000075+.001868*Math.cos(g)-.032077*Math.sin(g)-.014615*Math.cos(2*g)-.040849*Math.sin(2*g));
  const dec=.006918-.399912*Math.cos(g)+.070257*Math.sin(g)-.006758*Math.cos(2*g)+.000907*Math.sin(2*g)-.002697*Math.cos(3*g)+.00148*Math.sin(3*g);
  const ha=(hour*60+eq+4*longitude-60*timezone)/4*DEG-Math.PI,lat=latitude*DEG;
  // Vector points from the array toward the sun; east +X, north +Y, up +Z.
  const vector=[-Math.cos(dec)*Math.sin(ha),Math.cos(lat)*Math.sin(dec)-Math.sin(lat)*Math.cos(dec)*Math.cos(ha),Math.sin(lat)*Math.sin(dec)+Math.cos(lat)*Math.cos(dec)*Math.cos(ha)];
  return {azimuth_deg:(Math.atan2(vector[0],vector[1])/DEG+360)%360,elevation_deg:Math.asin(Math.max(-1,Math.min(1,vector[2])))/DEG,vector};
 }
 function geometry(plan){
  const a=plan.settings.azimuth*DEG,b=plan.settings.tilt*DEG;
  const basis=plan.panel_axes||[[-Math.cos(a),Math.sin(a),0],[-Math.cos(b)*Math.sin(a),-Math.cos(b)*Math.cos(a),Math.sin(b)],[Math.sin(b)*Math.sin(a),Math.sin(b)*Math.cos(a),Math.cos(b)]];
  if(!Array.isArray(basis)||basis.length!==3||basis.some(axis=>!Array.isArray(axis)||axis.length!==3||axis.some(x=>!Number.isFinite(x))||Math.abs(dot(axis,axis)-1)>1e-6))throw Error('光伏板方向无效');
  const [u,v,n]=basis,cross=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
  if(Math.abs(dot(u,v))>1e-6||cross.some((x,i)=>Math.abs(x-n[i])>1e-6))throw Error('光伏板方向无效');
  const w=plan.spec.width_mm,l=plan.spec.length_mm;
  if(!(w>0&&l>0)||!Number.isFinite(w+l)||!Array.isArray(plan.positions)||plan.positions.length!==plan.count)throw Error('阵列计算几何无效');
  const origin=plan.positions[0]||[0,0,0];
  const panels=plan.positions.map(p=>{
   const world=[0,1,2].map(i=>plan.frame_axes.reduce((s,axis,k)=>s+(p[k]-origin[k])*axis[i],0));
   if(!world.every(Number.isFinite))throw Error('阵列坐标无效');
   return [dot(world,u),dot(world,v),dot(world,n)];
  });
  return {u,v,n,w,l,panels};
 }
 // Exact union of clipped, axis-aligned shadow rectangles. Overlapping shadows count once.
 function unionArea(rects){
  if(!rects.length)return 0;if(rects.length===1){const r=rects[0];return (r[2]-r[0])*(r[3]-r[1]);}
  const xs=[...new Set(rects.flatMap(r=>[r[0],r[2]]))].sort((a,b)=>a-b);let area=0;
  for(let k=1;k<xs.length;k++){
   const x=(xs[k-1]+xs[k])/2,ys=rects.filter(r=>r[0]<x&&r[2]>x).map(r=>[r[1],r[3]]).sort((a,b)=>a[0]-b[0]);
   let lo=0,hi=0,length=0,started=false;
   for(const y of ys){if(!started){[lo,hi]=y;started=true;}else if(y[0]<=hi)hi=Math.max(hi,y[1]);else{length+=hi-lo;[lo,hi]=y;}}
   if(started)length+=hi-lo;area+=(xs[k]-xs[k-1])*length;
  }
  return area;
 }
 function forSun(g,sun,details=false){
  const count=g.panels.length,sn=dot(sun,g.n),ratios=details?new Array(count).fill(1):null,shadows=details?Array.from({length:count},()=>[]):null;
  // Mutual-shade-only factor: without front beam, do not remove existing diffuse power.
  if(!count||sun[2]<=EPS||sn<=EPS)return {factor:1,ratios,shadows,front_beam:false};
  const su=dot(sun,g.u)/sn,sv=dot(sun,g.v)/sn,bins=new Map();
  const projected=g.panels.map(p=>[p[0]-p[2]*su,p[1]-p[2]*sv,p[2]]);
  projected.forEach((p,i)=>{const key=Math.floor(p[0]/g.w)+','+Math.floor(p[1]/g.l);if(!bins.has(key))bins.set(key,[]);bins.get(key).push(i);});
  let total=0;
  projected.forEach((p,i)=>{
   const bx=Math.floor(p[0]/g.w),by=Math.floor(p[1]/g.l),rects=[];let full=false;
   // Identical parallel panels cast identically sized rectangles in sun-projected UV.
   for(let dx=-1;dx<=1&&!full;dx++)for(let dy=-1;dy<=1&&!full;dy++){
    for(const j of bins.get((bx+dx)+','+(by+dy))||[]){
     const q=projected[j];if(q[2]<=p[2]+EPS)continue;
     const x0=Math.max(0,q[0]-p[0]),y0=Math.max(0,q[1]-p[1]),x1=Math.min(g.w,q[0]-p[0]+g.w),y1=Math.min(g.l,q[1]-p[1]+g.l);
     if(x1-x0<=EPS||y1-y0<=EPS)continue;
     if(shadows)shadows[i].push({rect:[x0,y0,x1,y1],blocker:j});
     if(x0<=EPS&&y0<=EPS&&x1>=g.w-EPS&&y1>=g.l-EPS){full=true;break;}
     rects.push([x0,y0,x1,y1]);
    }
   }
   const ratio=full?0:Math.max(0,Math.min(1,1-unionArea(rects)/(g.w*g.l)));
   if(ratios)ratios[i]=ratio;total+=ratio;
  });
  return {factor:total/count,ratios,shadows,front_beam:true};
 }
function sweepArea(rects){
 if(!rects.length)return 0;
 const ys=[...new Set(rects.flatMap(r=>[r[1],r[3]]))].sort((a,b)=>a-b),lookup=new Map(ys.map((v,i)=>[v,i]));
 const events=rects.flatMap(r=>[[r[0],1,lookup.get(r[1]),lookup.get(r[3])-1],[r[2],-1,lookup.get(r[1]),lookup.get(r[3])-1]]).sort((a,b)=>a[0]-b[0]);
 const count=new Int32Array(ys.length*4),length=new Float64Array(ys.length*4);
 function update(node,lo,hi,a,b,change){
  if(a<=lo&&hi<=b)count[node]+=change;
  else{const mid=(lo+hi)>>1;if(a<=mid)update(node*2,lo,mid,a,b,change);if(b>mid)update(node*2+1,mid+1,hi,a,b,change);}
  length[node]=count[node]>0?ys[hi+1]-ys[lo]:lo===hi?0:length[node*2]+length[node*2+1];
 }
 let area=0,previous=events[0][0];
 for(const [x,change,lo,hi] of events){area+=(x-previous)*length[1];update(1,0,ys.length-2,lo,hi,change);previous=x;}
 return area;
}
function aggregateFactor(g,sun){
 const sn=dot(sun,g.n);if(!g.panels.length||sun[2]<=1e-8||sn<=1e-8)return 1;
 const a=dot(sun,g.u)/sn,b=dot(sun,g.v)/sn;
 const rects=g.panels.map(p=>{const x=p[0]-p[2]*a,y=p[1]-p[2]*b;return [x,y,x+g.w,y+g.l];});
 return Math.max(0,Math.min(1,sweepArea(rects)/(g.panels.length*g.w*g.l)));
}
 function sunAtHour(index,location=site){
  const date=new Date(Date.UTC(location.year,0,1+Math.floor(index/24)));
  const sun=solarPosition({...location,month:date.getUTCMonth()+1,day:date.getUTCDate(),hour:index%24+.5});
  return sun;
 }
 function atHour(g,index,location=site,details=false){
  const sun=sunAtHour(index,location);return {...forSun(g,sun.vector,details),sun};
 }
 // Current same-model arrays use the aggregate union. Per-panel output stays internal
 // for shadow inspection and a future mixed-model evaluator with individual weights.
 function annual(plan,baseline,progress=()=>{},location=site,method='aggregate'){
  if(!['per_panel','aggregate'].includes(method))throw Error('未知遮挡算法');
  location=validateLocation(location);
  if(!Array.isArray(baseline)||baseline.length!==8760||baseline.some(v=>!Number.isFinite(v)||v<0))throw Error('全年原始出力不完整');
  const g=geometry(plan),factors=new Array(8760),values=new Array(8760);let original=0,corrected=0;
  for(let i=0;i<8760;i++){
   const sun=sunAtHour(i,location).vector;
   const factor=method==='aggregate'?aggregateFactor(g,sun):forSun(g,sun).factor;
   factors[i]=factor;values[i]=baseline[i]*factor;original+=baseline[i];corrected+=values[i];
   if(i%168===0)progress(Math.floor(i/8760*100));
  }
  return {values,factors,annual_kwh:corrected/1000,peak_wh:Math.max(...values),baseline_kwh:original/1000,loss_pct:original>0?(original-corrected)/original*100:0,site:location,method};
 }
 function workerSource(){
  // Blob worker avoids file:// cross-origin restrictions in HtmlDialog/Chromium.
  return '('+install.toString()+')(self);self.onmessage='+function(event){
   try{
    const result=self.SuPvShading.annual(event.data.plan,event.data.baseline,percent=>self.postMessage({type:'progress',percent}),event.data.location,event.data.method);
    self.postMessage({type:'result',result});
   }catch(error){self.postMessage({type:'error',message:error.message});}
  }.toString()+';';
 }
 const api={site,solarPosition,validateLocation,geometry,unionArea,forSun,atHour,annual,workerSource,sweepArea,aggregateFactor};
 root.SuPvShading=api;if(typeof module!=='undefined')module.exports=api;
})(typeof self!=='undefined'?self:globalThis);
