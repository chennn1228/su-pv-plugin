'use strict';
// Compare conservative screening with exhaustive projection of every face.
const assert=require('node:assert/strict'),P=require('../ui/pv_scene_shading.js'),S=require('../ui/pv_shading.js');
const dot=(a,b)=>a.reduce((v,x,i)=>v+x*b[i],0),axes=[[1,0,0],[0,1,0],[0,0,1]];
const quad=(x0,y0,x1,y1,z)=>[[[x0,y0,z],[x1,y0,z],[x1,y1,z]],[[x0,y0,z],[x1,y1,z],[x0,y1,z]]];
function reference(plan,sun,details=false){
 const g=P.geometry({...plan,environment:[],occluder_panels:[]}),objects=g.objects;
 const shift=p=>p.map((v,i)=>v-g.first[i]);
 const sources=objects.map((p,id)=>({poly:P.corners(p),kind:'self',id})).concat(
  (plan.occluder_panels||[]).map(p=>({poly:P.corners({origin:shift(p.origin),axes:p.axes,w:p.spec.width_mm,l:p.spec.length_mm}),kind:'self',id:-1})),
  (plan.environment||[]).map(poly=>({poly:poly.map(shift),kind:'external',id:-1})));
 const shadows=objects.map(()=>[]),external=objects.map(()=>[]),ratios=objects.map((p,id)=>{
  const [u,v,n]=p.axes,sn=dot(sun,n);if(sun[2]<=1e-7||sn<=1e-7)return 1;
  const su=dot(sun,u)/sn,sv=dot(sun,v)/sn,o=p.axes.map(axis=>dot(p.origin,axis)),q=[o[0]-su*o[2],o[1]-sv*o[2]],all=[];
  for(const source of sources){
   if(source.kind==='self'&&source.id===id)continue;
   const local=source.poly.map(v=>p.axes.map(axis=>dot(v,axis)));
   const upstream=P.clip(local,v=>v[2]-o[2]-1e-7);
   const poly=P.rectangle(upstream.map(v=>[v[0]-su*v[2]-q[0],v[1]-sv*v[2]-q[1]]),p.w,p.l);
   if(poly.length<3||P.area(poly)<=1e-7)continue;
   all.push(poly);if(details)(source.kind==='external'?external[id]:shadows[id]).push({poly});
  }
  return Math.max(0,Math.min(1,1-P.union(all)/(p.w*p.l)));
 });
 return {ratios,shadows,external};
}
const base={settings:{azimuth:180,tilt:0},spec:{width_mm:1000,length_mm:2000},frame_axes:axes,panel_axes:axes,count:1,positions:[[0,0,0]]};
let checked=0,maxError=0;
function compare(plan,directions){
 const g=P.geometry(plan);
 for(const sun of directions){
  const actual=P.forSun(g,sun,true),expected=reference(plan,sun,true);checked++;
  actual.ratios.forEach((ratio,i)=>{
   const error=Math.abs(ratio-expected.ratios[i]);maxError=Math.max(maxError,error);assert(error<1e-8,`factor error ${error}`);
   for(const kind of ['shadows','external'])assert(Math.abs(P.union(actual[kind][i].map(s=>s.poly))-P.union(expected[kind][i].map(s=>s.poly)))<.02,`${kind} changed`);
  });
 }
 return g;
}
const below=quad(-1e5,-1e5,1e5,1e5,-100);
let g=compare({...base,environment:below},[[0,0,1],[2,1,.001]]);
assert.equal(g.screening.below_receivers,2);assert(!S.geometry({...base,environment:below}).general,'Irrelevant surroundings disabled the fast self-shading path');
// A high, distant wall still shades at a low sun angle: no distance cutoff.
const wall=[[[100000,-100,99],[100000,3000,99],[100000,3000,104]],[[100000,-100,99],[100000,3000,104],[100000,-100,104]]];
g=compare({...base,environment:wall},[[1,0,.001],[-1,0,.001],[0,0,1]]);
assert(P.forSun(g,[1,0,.001]).factor<.01,'Distant low-angle shade was removed');
assert.equal(g.last_screening.projected_sources,2);
P.forSun(g,[-1,0,.001]);assert.equal(g.last_screening.projected_sources,0,'Wrong-side wall reached exact projection');
// Crossing a receiver plane and a hole in surrounding geometry retain their areas.
compare({...base,environment:[...quad(0,0,1000,300,500),...quad(0,1700,1000,2000,500),[[0,0,-100],[1000,0,1500],[0,2000,1500]]]},[[0,0,1],[.8,-.4,.7],[-.5,1,.1]]);
let seed=74;const rand=()=>((seed=(1664525*seed+1013904223)>>>0)/2**32);
for(let test=0;test<45;test++){
 const components=Array.from({length:3},(_,i)=>{
  const a=rand()*Math.PI*2,b=(rand()-.4)*Math.PI/2;
  return {origin:[rand()*2000,rand()*3000,rand()*1500],axes:[[-Math.cos(a),Math.sin(a),0],[-Math.cos(b)*Math.sin(a),-Math.cos(b)*Math.cos(a),Math.sin(b)],[Math.sin(b)*Math.sin(a),Math.sin(b)*Math.cos(a),Math.cos(b)]],spec:{width_mm:800+rand()*600,length_mm:1200+rand()*1400},series_index:i};
 });
 const environment=Array.from({length:24},()=>Array.from({length:3},()=>[rand()*12000-5000,rand()*12000-5000,rand()*6000-3000]));
 const occluder_panels=[{origin:[200,300,1000],axes,spec:base.spec}];
 const directions=Array.from({length:12},(_,i)=>[rand()*2-1,rand()*2-1,i===0?.00001:rand()]);
 compare({...base,components,environment,occluder_panels},directions);
}
// A complete year also exercises seasonally changing front/back orientations.
const annualPlan={...base,count:2,positions:[[0,0,0],[500,0,600]],environment:quad(-600,400,900,2200,900)};
const emptyGeometry=S.geometry(base);
compare(annualPlan,Array.from({length:8760},(_,h)=>S.atHour(emptyGeometry,h).sun.vector));
// The blob worker must include the hierarchy and screening helpers too.
const vm=require('node:vm'),context={self:{}};vm.runInNewContext(S.workerSource(),context);
const worker=context.self.SuPvSceneShading,workerGeometry=worker.geometry(annualPlan),sun=[.6,-.4,.7];
assert(Math.abs(worker.forSun(workerGeometry,sun).factor-P.forSun(P.geometry(annualPlan),sun).factor)<1e-12);
console.log(JSON.stringify({checks:checked,max_factor_error:maxError,cases:'below-roof, distant low sun, wrong direction, holes, crossing planes, mixed panels, 8760 hours, worker'}));
