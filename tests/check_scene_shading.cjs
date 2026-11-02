const assert=require('assert/strict'),P=require('../ui/pv_scene_shading.js'),S=require('../ui/pv_shading.js');
const near=(a,b,t=1e-8)=>assert(Math.abs(a-b)<t,`${a} vs ${b}`);
const axes=[[1,0,0],[0,1,0],[0,0,1]],spec={width_mm:2,length_mm:2};
const quad=(x0,y0,x1,y1,z)=>[[[x0,y0,z],[x1,y0,z],[x1,y1,z]],[[x0,y0,z],[x1,y1,z],[x0,y1,z]]];
const plan={settings:{azimuth:180,tilt:0},spec,frame_axes:axes,panel_axes:axes,count:2,positions:[[0,0,0],[1,0,1]],environment:quad(0,0,1.5,2,2)};
let g=S.geometry(plan),r=S.forSun(g,[0,0,1],true);
near(r.ratios[0],0);near(r.ratios[1],.75);near(r.factor,.375);
near(P.union(r.shadows[0].map(s=>s.poly))/4,.5);near(P.union(r.external[0].map(s=>s.poly))/4,.75);
near(P.union([...r.shadows[0],...r.external[0]].map(s=>s.poly))/4,1);
const coincident=S.geometry({...plan,positions:[[0,0,0],[0,0,0]],environment:[]});
assert(coincident.general,'Coplanar overlapping free selections used the disjoint aggregate shortcut');near(S.forSun(coincident,[0,0,1]).factor,1);
// Ring-shaped external geometry: the opening must remain illuminated.
const ring=[...quad(0,0,2,.5,2),...quad(0,1.5,2,2,2),...quad(0,.5,.5,1.5,2),...quad(1.5,.5,2,1.5,2)];
near(S.forSun(S.geometry({...plan,count:1,positions:[[0,0,0]],environment:ring}),[0,0,1]).factor,.25);
// Geometry behind the receiving plane never casts forward onto it.
near(S.forSun(S.geometry({...plan,count:1,positions:[[0,0,0]],environment:quad(0,0,2,2,-1)}),[0,0,1]).factor,1);
// Independent Moller–Trumbore ray/triangle oracle, no polygon projection.
const dot=(a,b)=>a.reduce((s,x,i)=>s+x*b[i],0),sub=(a,b)=>a.map((x,i)=>x-b[i]),cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
function hit(o,d,t){const e1=sub(t[1],t[0]),e2=sub(t[2],t[0]),h=cross(d,e2),a=dot(e1,h);if(Math.abs(a)<1e-9)return false;const f=1/a,s=sub(o,t[0]),u=f*dot(s,h);if(u<0||u>1)return false;const q=cross(s,e1),v=f*dot(d,q);return v>=0&&u+v<=1&&f*dot(e2,q)>1e-7;}
let seed=42;const rand=()=>((seed=(1664525*seed+1013904223)>>>0)/2**32);
for(let k=0;k<12;k++){
 const tilt=.2+rand()*.6,co=Math.cos(tilt),si=Math.sin(tilt);
 const objects=[{origin:[0,0,0],axes,w:2,l:2},{origin:[rand(),rand(),.4+rand()],axes:[[co,0,si],[0,1,0],[-si,0,co]],w:1.3,l:2.2}];
 const env=[...quad(-.5,.1,1.3,1.4,1.8),[[.2,-1,-.5],[2.4,.5,1.2],[-.3,2.4,2.8]]];
 const components=objects.map(p=>({origin:p.origin,axes:p.axes,spec:{width_mm:p.w,length_mm:p.l},series_index:0}));
 const d=S.geometry({...plan,components,environment:env}),sun=[rand()-.5,rand()-.5,1],result=S.forSun(d,sun,true),N=160;
 d.scene.objects.forEach((p,id)=>{
  const triangles=d.scene.sources.filter(s=>s.kind==='external'||s.id!==id).flatMap(s=>s.poly.length===3?[s.poly]:[[s.poly[0],s.poly[1],s.poly[2]],[s.poly[0],s.poly[2],s.poly[3]]]);
  let lit=0;for(let y=0;y<N;y++)for(let x=0;x<N;x++){
   const o=p.origin.map((v,i)=>v+(x+.5)/N*p.w*p.axes[0][i]+(y+.5)/N*p.l*p.axes[1][i]);
   if(!triangles.some(t=>hit(o,sun,t)))lit++;
  }
  near(result.ratios[id],lit/(N*N),.008);
 });
}
// Weighted mixed products: an arithmetic mean of area factors would be wrong.
const mixed={...plan,components:[{origin:[0,0,0],axes,spec,series_index:0},{origin:[1,0,1],axes,spec,series_index:1}],series:[new Array(8760).fill(100),new Array(8760).fill(400)]};
const hourly=S.annual(mixed,new Array(8760).fill(500));
for(const h of [12,4000,5400]){const detail=S.atHour(S.geometry(mixed),h);near(hourly.values[h],100*detail.ratios[0]+400*detail.ratios[1]);}
console.log('Scene checks passed: external/self union, holes, rear clipping, 12 independent ray-oracle scenes, mixed energy weights.');
