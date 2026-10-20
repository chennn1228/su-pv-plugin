'use strict';
const assert=require('assert'),S=require('../ui/pv_shading.js');
const {makePlan,checks}=require('./benchmark_shading.cjs');
checks();
for(const missing of [false,true]){
 const plan=makePlan(6,{missing}),raw=Array.from({length:8760},(_,i)=>Math.max(0,Math.sin((i%24-6)*Math.PI/12))*630*plan.count);
 const a=S.annual(plan,raw,()=>{},S.site,'per_panel'),b=S.annual(plan,raw,()=>{},S.site,'aggregate');
 assert.equal(S.annual(plan,raw).method,'aggregate');
 assert(a.method==='per_panel'&&b.method==='aggregate');
 for(let i=0;i<8760;i++){
  assert(Math.abs(a.factors[i]-b.factors[i])<1e-8,'Hourly factors diverged');
  assert(Math.abs(a.values[i]-b.values[i])<1e-6,'Hourly outputs diverged');
  assert(b.values[i]>=0&&b.values[i]<=raw[i]+1e-8);
 }
 assert(Math.abs(a.annual_kwh-b.annual_kwh)<1e-6,'Annual totals diverged');
 assert.notStrictEqual(a.values,raw);assert.notStrictEqual(b.values,raw);
}
assert.throws(()=>S.annual(makePlan(1),new Array(8760).fill(0),()=>{},S.site,'unknown'));
for(const method of ['aggregate','per_panel']){
 const plan=makePlan(0),a=S.annual(plan,new Array(8760).fill(0),()=>{},S.site,method);
 assert(a.annual_kwh===0&&a.loss_pct===0&&a.factors.every(v=>v===1));
}
console.log('Both methods passed: 325 geometry cases, 8760-hour full and missing grids, metadata, bounds and empty arrays.');
