'use strict';
// Convex polygon projection and exact union by scanline integration, in millimetres.
// No rays, grid sampling, or raster approximation is used for shadow areas.
(function installScene(root){
 const EPS=1e-7,dot=(a,b)=>a.reduce((s,x,i)=>s+x*b[i],0);
 const cross=(a,b)=>a[0]*b[1]-a[1]*b[0];
 function clip(poly,distance){
  const out=[];
  for(let i=0;i<poly.length;i++){
   const a=poly[i],b=poly[(i+1)%poly.length],da=distance(a),db=distance(b);
   if(da>=0)out.push(a);
   if((da>=0)!==(db>=0)){const t=da/(da-db);out.push(a.map((x,k)=>x+(b[k]-x)*t));}
  }
  return out;
 }
 function rectangle(poly,w,l){
  for(const fn of [p=>p[0],p=>w-p[0],p=>p[1],p=>l-p[1]]){poly=clip(poly,fn);if(poly.length<3)return [];}
  return poly;
 }
 function area(poly){return Math.abs(poly.reduce((s,p,i)=>s+cross(p,poly[(i+1)%poly.length]),0))/2;}
 function union(polys){
  polys=polys.filter(p=>p.length>=3&&area(p)>EPS);if(!polys.length)return 0;if(polys.length===1)return area(polys[0]);
  const edges=polys.flatMap(p=>p.map((v,i)=>[v,p[(i+1)%p.length]])),xs=polys.flatMap(p=>p.map(v=>v[0]));
  // Edge intersections are the only additional changes in interval ordering.
  for(let i=0;i<edges.length;i++)for(let j=i+1;j<edges.length;j++){
   const [a,b]=edges[i],[c,d]=edges[j],r=[b[0]-a[0],b[1]-a[1]],s=[d[0]-c[0],d[1]-c[1]],den=cross(r,s);
   if(Math.abs(den)<EPS)continue;
   const q=[c[0]-a[0],c[1]-a[1]],t=cross(q,s)/den,u=cross(q,r)/den;
   if(t>0&&t<1&&u>0&&u<1)xs.push(a[0]+t*r[0]);
  }
  xs.sort((a,b)=>a-b);let total=0;
  for(let i=1;i<xs.length;i++){
   const dx=xs[i]-xs[i-1];if(dx<EPS)continue;const x=(xs[i]+xs[i-1])/2,intervals=[];
   for(const poly of polys){const ys=[];for(let k=0;k<poly.length;k++){
    const a=poly[k],b=poly[(k+1)%poly.length];if((a[0]<x&&b[0]>x)||(b[0]<x&&a[0]>x))ys.push(a[1]+(x-a[0])/(b[0]-a[0])*(b[1]-a[1]));
   }if(ys.length>=2)intervals.push([Math.min(...ys),Math.max(...ys)]);}
   intervals.sort((a,b)=>a[0]-b[0]);let end=-Infinity,length=0;
   for(const [a,b] of intervals){if(b>end){length+=b-Math.max(a,end);end=b;}}
   total+=dx*length;
  }
  return total;
 }
 const bounds=p=>[Math.min(...p.map(q=>q[0])),Math.min(...p.map(q=>q[1])),Math.max(...p.map(q=>q[0])),Math.max(...p.map(q=>q[1]))];
 const overlaps=(a,b)=>a[0]<b[2]-EPS&&a[2]>b[0]+EPS&&a[1]<b[3]-EPS&&a[3]>b[1]+EPS;
 // Broad-phase comparisons include a margin: only exact clipping may discard a
 // grazing intersection. Bounds are conservative, never a shadow approximation.
 const mayOverlap=(a,b)=>a[0]<=b[2]+EPS&&a[2]>=b[0]-EPS&&a[1]<=b[3]+EPS&&a[3]>=b[1]-EPS;
 function bounds3(poly){
  const box=[Infinity,Infinity,Infinity,-Infinity,-Infinity,-Infinity];
  for(const p of poly)for(let k=0;k<3;k++){box[k]=Math.min(box[k],p[k]);box[k+3]=Math.max(box[k+3],p[k]);}
  return box;
 }
 function tree(items){
  if(!items.length)return null;
  const box=[Infinity,Infinity,Infinity,-Infinity,-Infinity,-Infinity];
  for(const p of items)for(let k=0;k<3;k++){box[k]=Math.min(box[k],p.extent[k]);box[k+3]=Math.max(box[k+3],p.extent[k+3]);}
  if(items.length<=8)return {box,items};
  const spans=[0,1,2].map(k=>box[k+3]-box[k]),axis=spans.indexOf(Math.max(...spans));
  items.sort((a,b)=>(a.extent[axis]+a.extent[axis+3])-(b.extent[axis]+b.extent[axis+3]));
  const middle=items.length>>1;
  return {box,left:tree(items.slice(0,middle)),right:tree(items.slice(middle))};
 }
 function projectBox(box,su,sv){
  return [box[0]-su*(su>=0?box[5]:box[2]),box[1]-sv*(sv>=0?box[5]:box[2]),
   box[3]-su*(su>=0?box[2]:box[5]),box[4]-sv*(sv>=0?box[2]:box[5])];
 }
 function corners(p){return [[0,0],[p.w,0],[p.w,p.l],[0,p.l]].map(([x,y])=>p.origin.map((v,i)=>v+x*p.axes[0][i]+y*p.axes[1][i]));}
 function geometry(plan){
  const a=plan.settings.azimuth*Math.PI/180,b=plan.settings.tilt*Math.PI/180;
  const axes=plan.panel_axes||[[-Math.cos(a),Math.sin(a),0],[-Math.cos(b)*Math.sin(a),-Math.cos(b)*Math.cos(a),Math.sin(b)],[Math.sin(b)*Math.sin(a),Math.sin(b)*Math.cos(a),Math.cos(b)]];
  const world=p=>[0,1,2].map(i=>plan.frame_axes.reduce((s,axis,k)=>s+p[k]*axis[i],0));
  const first=plan.components?plan.components[0].origin:world(plan.positions[0]||[0,0,0]);
  const shift=p=>p.map((v,i)=>v-first[i]);
  const objects=plan.components?plan.components.map(p=>({origin:shift(p.origin),axes:p.axes,w:p.spec.width_mm,l:p.spec.length_mm,series_index:p.series_index})):
   plan.positions.map(p=>({origin:shift(world(p)),axes,w:plan.spec.width_mm,l:plan.spec.length_mm}));
  const blockers=(plan.occluder_panels||[]).map(p=>({origin:shift(p.origin),axes:p.axes,w:p.spec.width_mm,l:p.spec.length_mm}));
  const environment=(plan.environment||[]).map(poly=>poly.map(shift));
  const receivers=objects.map((p,id)=>({poly:corners(p),kind:'self',id}));
  let minimumZ=Infinity;for(const p of receivers)for(const v of p.poly)minimumZ=Math.min(minimumZ,v[2]);
  const surrounding=blockers.map(p=>({poly:corners(p),kind:'self',id:-1})).concat(environment.map(poly=>({poly,kind:'external',id:-1})));
  // With the sun above the horizon, a ray from any receiver goes upwards.
  // Geometry wholly at/below the lowest receiving vertex cannot intercept it.
  const sources=receivers.concat(surrounding.filter(p=>p.poly.some(v=>v[2]>minimumZ)));
  const groups=new Map();
  objects.forEach((p,id)=>{
   const key=p.axes.flat().map(x=>x.toFixed(12)).join(',');
   if(!groups.has(key))groups.set(key,{axes:p.axes,receivers:[],sx:p.w,sy:p.l,minDepth:Infinity});
   const group=groups.get(key),o=p.axes.map(axis=>dot(p.origin,axis));
   group.receivers.push({receiver:p,id,o});group.minDepth=Math.min(group.minDepth,o[2]);
  });
  // Source coordinates and the hierarchy belong to this immutable snapshot.
  // Angle/model/spacing changes build a fresh geometry; no SU entity is cached.
  for(const group of groups.values()){
   const items=[];
   for(const source of sources){
    const local=source.poly.map(p=>group.axes.map(axis=>dot(p,axis))),extent=bounds3(local);
    if(extent[5]<=group.minDepth+EPS)continue;
    items.push({...source,local,extent,top:extent[5]});
   }
   group.tree=tree(items);
  }
  return {objects,sources,environment,first,series:plan.series,groups,
   screening:{surrounding:surrounding.length,below_receivers:surrounding.length-(sources.length-receivers.length)}};
 }
 function forSun(g,sun,details=false){
  const count=g.objects.length,ratios=new Array(count).fill(1),shadows=details?Array.from({length:count},()=>[]):null,external=details?Array.from({length:count},()=>[]):null;
  const stats={nodes:0,projected_sources:0,candidate_pairs:0,exact_clips:0};g.last_screening=stats;
  if(sun[2]<=EPS)return {factor:1,ratios,shadows,external,front_beam:false};
  let front=false;
  for(const group of g.groups.values()){
   const [u,v,n]=group.axes,sn=dot(sun,n);if(sn<=EPS)continue;front=true;
   const su=dot(sun,u)/sn,sv=dot(sun,v)/sn;
   const bins=new Map(),large=[],{sx,sy}=group,envelope=[Infinity,Infinity,-Infinity,-Infinity];
   const targets=group.receivers.map(p=>{
    const q=[p.o[0]-su*p.o[2],p.o[1]-sv*p.o[2]],box=[q[0],q[1],q[0]+p.receiver.w,q[1]+p.receiver.l];
    for(let k=0;k<2;k++){envelope[k]=Math.min(envelope[k],box[k]);envelope[k+2]=Math.max(envelope[k+2],box[k+2]);}
    return {...p,q,box};
   });
   const visit=node=>{
    if(!node)return;stats.nodes++;
    if(node.box[5]<=group.minDepth+EPS||!mayOverlap(projectBox(node.box,su,sv),envelope))return;
    if(!node.items){visit(node.left);visit(node.right);return;}
    for(const source of node.items){
     if(!mayOverlap(projectBox(source.extent,su,sv),envelope))continue;
     stats.projected_sources++;
     const box=bounds(source.local.map(p=>[p[0]-su*p[2],p[1]-sv*p[2]]));
     if(!mayOverlap(box,envelope))continue;
     const item={...source,box};
     // Index only the part that can reach a receiving panel. Very large faces
     // must not fill thousands of empty cells outside the array.
     const x0=Math.floor(Math.max(box[0],envelope[0]-EPS)/sx),x1=Math.floor(Math.min(box[2],envelope[2]+EPS)/sx),
      y0=Math.floor(Math.max(box[1],envelope[1]-EPS)/sy),y1=Math.floor(Math.min(box[3],envelope[3]+EPS)/sy);
     if((x1-x0+1)*(y1-y0+1)>400){large.push(item);continue;}
     for(let x=x0;x<=x1;x++)for(let y=y0;y<=y1;y++){const k=x+','+y;if(!bins.has(k))bins.set(k,[]);bins.get(k).push(item);}
    }
   };
   visit(group.tree);
   for(const {receiver,id,o,q,box} of targets){
    const candidates=new Set(large);
    for(let x=Math.floor(box[0]/sx);x<=Math.floor(box[2]/sx);x++)for(let y=Math.floor(box[1]/sy);y<=Math.floor(box[3]/sy);y++)for(const s of bins.get(x+','+y)||[])candidates.add(s);
    const all=[];
    for(const source of candidates){
     stats.candidate_pairs++;
     if(source.kind==='self'&&source.id===id||source.top<=o[2]+EPS||!overlaps(source.box,box))continue;
     stats.exact_clips++;
     const upstream=clip(source.local,p=>p[2]-o[2]-EPS);
     const poly=rectangle(upstream.map(p=>[p[0]-su*p[2]-q[0],p[1]-sv*p[2]-q[1]]),receiver.w,receiver.l);
     if(poly.length<3||area(poly)<=EPS)continue;
     all.push(poly);
     if(details)(source.kind==='external'?external[id]:shadows[id]).push({poly,blocker:source.id});
    }
    ratios[id]=Math.max(0,Math.min(1,1-union(all)/(receiver.w*receiver.l)));
   }
  }
  const totalArea=g.objects.reduce((s,p)=>s+p.w*p.l,0),litArea=g.objects.reduce((s,p,i)=>s+p.w*p.l*ratios[i],0);
  return {factor:totalArea?litArea/totalArea:1,ratios,shadows,external,front_beam:front};
 }
 root.SuPvSceneShading={geometry,forSun,union,clip,rectangle,area,corners};
 root.SuPvSceneWorkerSource='('+installScene.toString()+')(self);';
 if(typeof module!=='undefined')module.exports=root.SuPvSceneShading;
})(typeof self!=='undefined'?self:globalThis);
