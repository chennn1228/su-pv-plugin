'use strict';
const assert=require('assert');
const S=require('../ui/pv_shading.js');
const near=(a,b,t=1e-9)=>assert(Math.abs(a-b)<=t,`${a} != ${b}`);
const g={u:[1,0,0],v:[0,1,0],n:[0,0,1],w:2,l:2,panels:[[0,0,0],[1,0,1]]};
let result=S.forSun(g,[0,0,1],true);
near(result.ratios[0],.5);near(result.ratios[1],1);near(result.factor,.75);
near(S.forSun({...g,panels:[[0,0,0],[0,0,1]]},[0,0,1]).factor,.5);
near(S.forSun({...g,panels:[[0,0,0],[2,0,1]]},[0,0,1]).factor,1); // touching edge
near(S.forSun({...g,panels:[[0,0,0],[0,0,0]]},[0,0,1]).factor,1); // no positive ray distance
near(S.forSun(g,[0,0,-1]).factor,1); // no front beam: mutual loss is not inferred
near(S.forSun({...g,panels:[]},[0,0,1]).factor,1);
near(S.unionArea([[0,0,1.5,2],[.5,0,2,2],[.5,0,2,2]]),4);
const overlapping={...g,panels:[[0,0,0],[-.5,0,1],[.5,0,2]]};
near(S.forSun(overlapping,[0,0,1],true).ratios[0],0); // union, never double subtraction
const shown=S.forSun(overlapping,[0,0,1],true);
shown.shadows.forEach((shadows,i)=>near(1-S.unionArea(shadows.map(s=>s.rect))/4,shown.ratios[i]));
assert.throws(()=>S.validateLocation({...S.site,year:2024}),'Leap-year calendar silently used with 8760 values');
assert.throws(()=>S.validateLocation({...S.site,latitude:91}));

// Independent ray/plane oracle: sample each receiver's own UV, intersect the ray
// with each blocker in panel coordinates. Does not use projection bins or polygon union.
function sampled(g,sun,size=120){
 const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0),s=[dot(sun,g.u),dot(sun,g.v),dot(sun,g.n)];
 return g.panels.map((p,i)=>{
  let lit=0;
  for(let y=0;y<size;y++)for(let x=0;x<size;x++){
   const q=[p[0]+(x+.5)/size*g.w,p[1]+(y+.5)/size*g.l,p[2]];
   const hit=g.panels.some((b,j)=>{
    if(j===i)return false;const t=(b[2]-q[2])/s[2];if(t<=1e-8)return false;
    const X=q[0]+t*s[0]-b[0],Y=q[1]+t*s[1]-b[1];return X>0&&X<g.w&&Y>0&&Y<g.l;
   });if(!hit)lit++;
  }
  return lit/(size*size);
 });
}
let seed=7;const rand=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};
for(let test=0;test<30;test++){
 const az=(90+rand()*180)*Math.PI/180,b=rand()*1.4;
 const u=[-Math.cos(az),Math.sin(az),0],v=[-Math.cos(b)*Math.sin(az),-Math.cos(b)*Math.cos(az),Math.sin(b)],n=[Math.sin(b)*Math.sin(az),Math.sin(b)*Math.cos(az),Math.cos(b)];
 const sun=n.map((v,i)=>v+u[i]*(rand()-.5)+g.v[i]*.1);if(sun[2]<=0)continue;
 const h={...g,u,v,n,panels:Array.from({length:6},()=>[rand()*6-3,rand()*6-3,rand()*3])};
 const details=S.forSun(h,sun,true),exact=details.ratios,reference=sampled(h,sun);
 exact.forEach((r,i)=>near(r,reference[i],.013));
 details.shadows.forEach((shadows,i)=>{
  near(1-S.unionArea(shadows.map(s=>s.rect))/(h.w*h.l),exact[i]);
  shadows.forEach(({rect,blocker})=>{
   const dot=(a,b)=>a.reduce((s,v,k)=>s+v*b[k],0),p=h.panels[i],q=h.panels[blocker];
   const t=(q[2]-p[2])/dot(sun,h.n),x=p[0]+(rect[0]+rect[2])/2+t*dot(sun,h.u)-q[0],y=p[1]+(rect[1]+rect[3])/2+t*dot(sun,h.v)-q[1];
   assert(t>0&&x>=-1e-7&&x<=h.w+1e-7&&y>=-1e-7&&y<=h.l+1e-7,'Shown ray misses the identified casting panel');
  });
 });
}
// Solar direction signs, timezone, leap day and reference magnitude.
const pos=(month,day,hour)=>S.solarPosition({...S.site,month,day,hour});
assert(pos(6,21,8).vector[0]>0 && pos(6,21,16).vector[0]<0,'East/west swapped');
assert(pos(6,21,12).elevation_deg>pos(12,21,12).elevation_deg+40,'Season ordering');
assert(pos(6,21,0).elevation_deg<0,'Midnight sun in Yangzhou');
near(Math.hypot(...pos(6,21,12).vector),1);
assert.doesNotThrow(()=>S.solarPosition({...S.site,year:2024,month:2,day:29,hour:12}));
assert.throws(()=>S.solarPosition({...S.site,year:2025,month:2,day:29,hour:12}));
// SPA report reference case (NREL/TP-560-34302). This is the NOAA approximate
// formula, not SPA: use a 1 degree cross-method smoke-check tolerance.
const ref=S.solarPosition({latitude:39.742476,longitude:-105.1786,timezone:-7,year:2003,month:10,day:17,hour:12+30/60+30/3600});
near(ref.azimuth_deg,194.34024,1);near(ref.elevation_deg,90-50.11162,1);
if(process.argv[2]){
 const data=require(require('path').resolve(process.argv[2]));const started=performance.now();
 const original=data.prediction.values.slice(),shaded=S.annual(data,original);
 assert.deepEqual(data.prediction.values,original,'Changed original forecast');
 assert(shaded.loss_pct>0&&shaded.loss_pct<100,'No mutual shading detected');
 shaded.values.forEach((v,i)=>assert(v>=0&&v<=original[i]+1e-9));
 near(shaded.annual_kwh,shaded.values.reduce((s,v)=>s+v,0)/1000);
 const flat=JSON.parse(JSON.stringify(data));flat.settings.tilt=0;
 const flatResult=S.annual(flat,original);near(flatResult.loss_pct,0,1e-9);
 console.log(JSON.stringify({panels:data.count,elapsed_ms:Math.round(performance.now()-started),baseline_kwh:shaded.baseline_kwh,shaded_kwh:shaded.annual_kwh,loss_pct:shaded.loss_pct}));
}
console.log('Shading checks passed: analytical cases, independent ray oracle, solar conventions and annual bounds.');
