'use strict';
// Offline comparison benchmark for the two shipping shading methods.
// Equal, parallel, non-intersecting panels: sum of visible areas equals the
// union of the translated sun-projected rectangles in a common parallel plane.
const S=require('../ui/pv_shading.js'),assert=require('assert');
const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
const {sweepArea,aggregateFactor}=S;
function makePlan(side,{missing=false,azimuth=180,tilt=30,slope=0}={}){
 const a=slope*Math.PI/180,positions=[];
 for(let row=0;row<side;row++)for(let col=0;col<side;col++)if(!missing||!((row%7===2)&&(col%5===1)))positions.push([col*1234,row*2178,0]);
 // Rotated or sloped cases use wider pitch to keep physical surfaces disjoint.
 if(azimuth!==180||slope)positions.forEach(p=>{p[0]*=3;p[1]*=2;});
 return {positions,count:positions.length,frame_axes:[[1,0,0],[0,Math.cos(a),Math.sin(a)],[0,-Math.sin(a),Math.cos(a)]],settings:{azimuth,tilt},spec:{width_mm:1134,length_mm:2382}};
}
function checks(){
 const cases=[[],[[0,0,1,1]],[[0,0,2,2],[1,0,3,2]],[[0,0,2,2],[0,0,2,2]],[[0,0,1,1],[1,0,2,1]]];
 cases.forEach(r=>assert(Math.abs(sweepArea(r)-S.unionArea(r))<1e-8));
 let maxError=0,checked=0;
 for(const options of [{},{missing:true},{missing:true,azimuth:130,tilt:39},{slope:20},{azimuth:220,slope:-15}]){
  const g=S.geometry(makePlan(8,options));
  for(const month of [1,3,6,9,12])for(let hour=6;hour<19;hour++){
   const sun=S.solarPosition({...S.site,month,day:21,hour:hour+.5}).vector;
   const error=Math.abs(aggregateFactor(g,sun)-S.forSun(g,sun).factor);maxError=Math.max(maxError,error);checked++;
   assert(error<1e-8,'Aggregate differs from per-panel geometry: '+error);
  }
 }
 return {checked,max_factor_error:maxError};
}
function benchmark(){
 const directions=[];
 for(const month of [1,6,12])for(const hour of [8.5,9.5,11.5,14.5,16.5])directions.push(S.solarPosition({...S.site,month,day:21,hour}).vector);
 const rows=[];
 for(const side of [6,20,50])for(const missing of [false,true]){
  const g=S.geometry(makePlan(side,{missing})),sun=directions.filter(s=>s[2]>1e-8&&dot(s,g.n)>1e-8);
  S.forSun(g,sun[0]);aggregateFactor(g,sun[0]);
  const times=[[],[]];let error=0;
  for(const s of sun)error=Math.max(error,Math.abs(aggregateFactor(g,s)-S.forSun(g,s).factor));
  for(let repeat=0;repeat<5;repeat++)for(const method of repeat%2?[1,0]:[0,1]){
   const begin=performance.now();for(const s of sun)(method?aggregateFactor:S.forSun)(g,s);times[method].push(performance.now()-begin);
  }
  const median=a=>a.sort((a,b)=>a-b)[2],old=median(times[0]),candidate=median(times[1]);
  rows.push({panels:g.panels.length,missing,directions:sun.length,per_panel_ms:+old.toFixed(3),aggregate_union_ms:+candidate.toFixed(3),speedup:+(old/candidate).toFixed(3),max_factor_error:error});
 }
 return rows;
}
if(require.main===module)console.log(JSON.stringify({date:'2026-10-20',runtime:process.version,validation:checks(),benchmark:benchmark(),production_methods:['per_panel','aggregate']},null,2));
module.exports={sweepArea,aggregateFactor,makePlan,checks};
