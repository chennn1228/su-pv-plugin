'use strict';
(function(){
 const el=id=>document.getElementById(id);
 const state={data:null,request:0,dirty:true,building:false,angleDrag:false,timer:null,worker:null,shaded:null,geometry:null,query:null,shadedByMethod:{}};
 const controls=window.PVPanelControls.create({onModelChange(){state.angleDrag=false;change();},onInput(){state.angleDrag=true;change();},onCommit(){state.angleDrag=false;change();}});
 function params(){return {target_id:state.data&&state.data.target_id,request_id:state.request,model_id:el('panelModel').value,azimuth:Number(el('azimuth').value),tilt:Number(el('tilt').value),gap_x_mm:Number(el('gapX').value)*10,gap_y_mm:Number(el('gapY').value)*10};}
 function validGaps(){return ['gapX','gapY'].every(id=>el(id).value.trim()!==''&&Number.isInteger(Number(el(id).value))&&Number(el(id).value)>=0&&Number(el(id).value)<=Number(el(id).max));}
 function change(){
  if(state.building)return;
  invalidateShading();if(lab)lab.invalidate();
  state.request++;state.dirty=true;window.PV.clear();el('build').disabled=true;el('build').textContent='生成阵列';el('arrayStatus').textContent='';clearTimeout(state.timer);
  if(!validGaps()){PVArray.fail('请输入当前范围内的整数厘米数值。');return;}
  el('arrayError').hidden=true;
  state.timer=setTimeout(()=>{if(window.sketchup&&state.data&&!state.angleDrag)window.sketchup.preview(JSON.stringify(params()));},120);
 }
 let lab=null;
 lab=window.PVShadingLab.create({
  onStepChange(step){
   if(!lab)return;
   if(step<4){document.querySelector('[data-view="surface"]').click();el('period').value='daily';el('period').dispatchEvent(new Event('change'));}
   syncLabView();
   if(step===4){showForecast();window.PV.resize();}
  }
 });
 function syncLabView(){
  if(!lab)return;
  const power=el('arrayLayout').hidden,shade=el('predictionBranch').value==='shade',active=power&&shade;
  el('shadingMethodControl').hidden=!shade;
  if(active&&lab.step<4&&(el('day').disabled||el('hour').disabled||el('period').value!=='daily')){document.querySelector('[data-view="surface"]').click();el('period').value='daily';el('period').dispatchEvent(new Event('change'));}
  lab.setActive(active);el('shadeControls').hidden=!power;
  document.querySelector('.array-power').hidden=!power||(shade&&(lab.step!==4||!state.shaded));
  document.body.classList.toggle('lab-no-result',active&&!state.shaded);
 }
 function setShadeStatus(message,loss=null){
  const node=el('shadeStatus');node.classList.toggle('annual-loss',loss!==null);
  if(loss===null)node.textContent=message;
  else node.innerHTML='<small>全年减少</small><strong>'+loss.toFixed(2)+'<span>%</span></strong>';
 }
 function invalidateShading(){
  stopWorker();state.shaded=null;state.shadedByMethod={};state.geometry=null;
  setShadeStatus('');el('shadeRetry').hidden=true;if(lab)lab.resetResult();
 }
 function stopWorker(){
  if(state.worker)state.worker.terminate();state.worker=null;
  if(state.workerUrl)URL.revokeObjectURL(state.workerUrl);state.workerUrl=null;
 }
 function shadeFailed(message){
  stopWorker();setShadeStatus('计算失败：'+message);el('shadeRetry').hidden=false;
  lab.calculation('计算失败：'+message);window.PV.clear('互遮挡计算未完成，可切回原始预测');syncLabView();
 }
 function receiveForecast(prediction){
  window.PV.receive({...prediction,export_context:{kind:'array',count:state.data.count,target_id:state.data.target_id,branch:prediction.method||'baseline'}});
 }
 function showForecast(compute=false){
  if(state.data&&state.data.layout_only){window.PV.clear();return;}
  if(!state.data||state.dirty){window.PV.clear('请等待有效阵列排布');syncLabView();return;}
  const shade=el('predictionBranch').value==='shade';el('shadeRetry').hidden=true;
  if(!shade){const pending=!!state.worker;stopWorker();if(pending)lab.calculation('计算已取消');setShadeStatus('');receiveForecast(state.data.prediction);syncLabView();return;}
  if(!state.data.prediction.data_available){receiveForecast(state.data.prediction);lab.calculation('暂无原始出力数据，可以先查看太阳与遮挡几何');syncLabView();return;}
  if(state.shaded&&!compute){
   setShadeStatus('',state.shaded.loss_pct);
   lab.calculation('计算完成',state.shaded);receiveForecast({...state.data.prediction,...state.shaded,baseline_values:state.data.prediction.values});syncLabView();return;
  }
  if(state.worker)return;
  state.shaded=null;lab.calculation('计算中 0%');window.PV.clear('正在计算互遮挡…');setShadeStatus('计算中 0%');syncLabView();
  try{
   const data=state.data,method=el('shadingMethod').value;
   state.workerUrl=URL.createObjectURL(new Blob([window.SuPvShading.workerSource()],{type:'text/javascript'}));
   const worker=new Worker(state.workerUrl);state.worker=worker;
   worker.onmessage=event=>{
    if(state.worker!==worker||state.data!==data||state.dirty||el('shadingMethod').value!==method)return;
    const msg=event.data;
    if(msg.type==='progress'){setShadeStatus('计算中 '+msg.percent+'%');lab.calculation('计算中 '+msg.percent+'%');}
    else if(msg.type==='result'){stopWorker();state.shaded=msg.result;state.shadedByMethod[method]=msg.result;showForecast();}
    else if(msg.type==='error')shadeFailed(msg.message);
   };
   worker.onerror=event=>{if(state.worker!==worker)return;event.preventDefault();shadeFailed(event.message||'计算线程不可用');};
   worker.postMessage({plan:data,baseline:data.prediction.values,location:lab.location,method});
  }catch(error){shadeFailed(error.message);}
 }
 el('predictionBranch').addEventListener('change',()=>showForecast());
 el('shadingMethod').addEventListener('change',()=>{
  stopWorker();state.shaded=state.shadedByMethod[el('shadingMethod').value]||null;
  setShadeStatus('');lab.resetResult();
  showForecast();
 });
 el('shadeRetry').addEventListener('click',()=>showForecast(true));
 window.addEventListener('unload',stopWorker);
 function prepare(canvas){
  const w=canvas.clientWidth,h=canvas.clientHeight,ratio=Math.min(2,window.devicePixelRatio||1);
  canvas.width=Math.max(1,Math.round(w*ratio));canvas.height=Math.max(1,Math.round(h*ratio));const c=canvas.getContext('2d');c.setTransform(ratio,0,0,ratio,0,0);c.clearRect(0,0,w,h);c.font='11px "Segoe UI","Microsoft YaHei",sans-serif';return {c,w,h};
 }
 function hull(points){
  const p=points.map(v=>v.slice()).sort((a,b)=>a[0]-b[0]||a[1]-b[1]);const cross=(o,a,b)=>(a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0]);const lower=[],upper=[];
  p.forEach(v=>{while(lower.length>1&&cross(lower[lower.length-2],lower[lower.length-1],v)<=1e-8)lower.pop();lower.push(v);});
  p.reverse().forEach(v=>{while(upper.length>1&&cross(upper[upper.length-2],upper[upper.length-1],v)<=1e-8)upper.pop();upper.push(v);});return lower.slice(0,-1).concat(upper.slice(0,-1));
 }
 function path(c,points,close=false){c.beginPath();points.forEach((p,i)=>i?c.lineTo(...p):c.moveTo(...p));if(close)c.closePath();}
 function label(c,text,x,y,color='#486378'){
  c.save();c.textAlign='center';c.textBaseline='middle';const width=c.measureText(text).width+10;c.fillStyle='rgba(255,255,255,.94)';c.fillRect(x-width/2,y-8,width,16);c.fillStyle=color;c.fillText(text,x,y);c.restore();
 }
 // Dimension text follows its baseline and stays outside its strokes.
 function dimension(c,a,b,text,center,distance=22,baseline=null){
  const ends=baseline||[a,b],dx=ends[1][0]-ends[0][0],dy=ends[1][1]-ends[0][1],len=Math.hypot(dx,dy);
  const ux=len>1e-6?dx/len:1,uy=len>1e-6?dy/len:0;let nx=-uy,ny=ux;
  const mid=[(ends[0][0]+ends[1][0])/2,(ends[0][1]+ends[1][1])/2];
  if((mid[0]-center[0])*nx+(mid[1]-center[1])*ny<0){nx=-nx;ny=-ny;}
  const A=[ends[0][0]+nx*distance,ends[0][1]+ny*distance],B=[ends[1][0]+nx*distance,ends[1][1]+ny*distance];
  const segments=[[A,B]];c.save();c.strokeStyle='#587c97';c.lineWidth=.75;
  [[a,A],[b,B]].forEach(([p,q])=>{const end=[q[0]+nx*5,q[1]+ny*5];path(c,[p,end]);c.stroke();segments.push([p,end]);});
  path(c,[A,B]);c.stroke();[A,B].forEach(p=>{const tick=[[p[0]-nx*4,p[1]-ny*4],[p[0]+nx*4,p[1]+ny*4]];path(c,tick);c.stroke();segments.push(tick);});
  const x=(A[0]+B[0])/2+nx*16,y=(A[1]+B[1])/2+ny*16;
  let angle=Math.atan2(uy,ux);if(angle>Math.PI/2)angle-=Math.PI;if(angle<-Math.PI/2)angle+=Math.PI;
  const width=c.measureText(text).width+10,height=16,co=Math.cos(angle),si=Math.sin(angle);
  const rect=[[-width/2,-height/2],[width/2,-height/2],[width/2,height/2],[-width/2,height/2]].map(([u,v])=>[x+co*u-si*v,y+si*u+co*v]);
  c.translate(x,y);c.rotate(angle);c.fillStyle='rgba(255,255,255,.94)';c.fillRect(-width/2,-height/2,width,height);c.fillStyle='#486378';c.textAlign='center';c.textBaseline='middle';c.fillText(text,0,0);c.restore();
  return {text,rect,segments};
 }
 function directionGuide(c,center,project,bearing=null){
  c.save();c.strokeStyle='#a6b8c7';c.lineWidth=.8;
  [[0,1,0,'N'],[1,0,0,'E'],[0,-1,0,'S'],[-1,0,0,'W']].forEach(direction=>{
   const q=project(direction.slice(0,3)),len=Math.hypot(q[0],q[1]);if(len<1e-7)return;
   const p=[center[0]+q[0]/len*22,center[1]+q[1]/len*22];path(c,[center,p]);c.stroke();
   label(c,direction[3],center[0]+q[0]/len*32,center[1]+q[1]/len*32);
  });
  if(bearing!==null){const a=bearing*Math.PI/180,q=project([Math.sin(a),Math.cos(a),0]),len=Math.hypot(...q);if(len>1e-7){const end=[center[0]+q[0]/len*20,center[1]+q[1]/len*20];path(c,[center,end]);c.strokeStyle='#2166ac';c.lineWidth=1.5;c.stroke();}}
  c.restore();
 }
 function planFrame(d){
  const axes=d.frame_axes,dot=(a,b)=>a.reduce((sum,v,i)=>sum+v*b[i],0),cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],unit=a=>{const n=Math.hypot(...a);return a.map(v=>v/n);};
  // Orthographic view along the installation normal; screen-up follows projected north.
  // Vertical faces use world-up, with the north projection shown in the guide.
  const n=axes[2],seed=Math.abs(n[2])<1e-6?[0,0,1]:[0,1,0];
  const up=unit(seed.map((v,i)=>v-dot(seed,n)*n[i])),right=unit(cross(up,n));
  const vector=q=>[dot(q,right),-dot(q,up)],raw=(x,y)=>vector(axes[0].map((v,i)=>v*x+axes[1][i]*y));
  return {vector,raw};
 }
 function drawPlan(){
  const canvas=el('layoutCanvas'),{c,w,h}=prepare(canvas);if(!state.data)return;const d=state.data;
  const {vector,raw}=planFrame(d);
  const plane=[[0,0],[d.width_mm,0],[d.width_mm,d.height_mm],[0,d.height_mm]],rawPlane=plane.map(p=>raw(...p));
  const xs=rawPlane.map(p=>p[0]),ys=rawPlane.map(p=>p[1]),loX=Math.min(...xs),hiX=Math.max(...xs),loY=Math.min(...ys),hiY=Math.max(...ys);
  const pad={left:76,right:52,top:Math.min(76,Math.max(52,h*.20)),bottom:Math.min(62,Math.max(52,h*.28))};
  const scale=Math.max(.00001,Math.min((w-pad.left-pad.right)/(hiX-loX||1),(h-pad.top-pad.bottom)/(hiY-loY||1)));
  const ox=pad.left+(w-pad.left-pad.right-(hiX-loX)*scale)/2,oy=pad.top+(h-pad.top-pad.bottom-(hiY-loY)*scale)/2;
  const point=(x,y)=>{const p=raw(x,y);return [ox+(p[0]-loX)*scale,oy+(p[1]-loY)*scale];};
  const rings=d.boundary?[d.boundary.outer,...d.boundary.holes]:[plane];
  c.beginPath();rings.forEach(ring=>{ring.forEach((p,i)=>{const q=point(...p);i?c.lineTo(...q):c.moveTo(...q);});c.closePath();});c.fillStyle='#eef4f9';c.fill('evenodd');c.strokeStyle='#9db1c1';c.lineWidth=1;c.stroke();
  if(d.boundary){path(c,plane.map(p=>point(...p)),true);c.setLineDash([3,4]);c.strokeStyle='#d6e0e8';c.lineWidth=.7;c.stroke();c.setLineDash([]);}
  canvas.dataset.holes=d.boundary?d.boundary.holes.length:0;canvas.dataset.outerVertices=rings[0].length;
  const center=point(d.width_mm/2,d.height_mm/2),shape=hull(d.footprint);
  d.positions.forEach(position=>{path(c,shape.map(p=>point(position[0]+p[0],position[1]+p[1])),true);c.fillStyle='rgba(33,102,172,.23)';c.fill();c.strokeStyle='#2166ac';c.lineWidth=.7;c.stroke();});
  const dimensions=[];
  // Host edge lengths are separate from the net-clearance dimensions.
  [[plane[1],plane[2],d.height_mm],[plane[2],plane[3],d.width_mm]].forEach(([a,b,value])=>{
   const A=point(...a),B=point(...b),dx=B[0]-A[0],dy=B[1]-A[1],len=Math.hypot(dx,dy)||1;let nx=-dy/len,ny=dx/len;
   const mid=[(A[0]+B[0])/2,(A[1]+B[1])/2];if((mid[0]-center[0])*nx+(mid[1]-center[1])*ny<0){nx=-nx;ny=-ny;}
   label(c,(value/1000).toFixed(2)+' m',mid[0]+nx*19,mid[1]+ny*19,'#617789');
  });
  directionGuide(c,[w-51,45],vector,d.settings.azimuth);
  canvas.dataset.dimensions=JSON.stringify(dimensions);canvas.dataset.north=JSON.stringify(vector([0,1,0]));canvas.dataset.east=JSON.stringify(vector([1,0,0]));
  canvas.dataset.count=d.count;canvas.dataset.targetId=d.target_id;canvas.dataset.gapX=d.settings.gap_x_mm;canvas.dataset.gapY=d.settings.gap_y_mm;
 }
 function drawIso(){
  const canvas=el('isoCanvas'),{c,w,h}=prepare(canvas);if(!state.data||!state.data.unit_corners)return;const d=state.data;
  const cols=Math.min(2,Math.max(1,d.columns)),rows=Math.min(2,Math.max(1,d.rows)),px=d.projected_width_mm,py=d.projected_height_mm,gx=d.settings.gap_x_mm,gy=d.settings.gap_y_mm;
  const minX=Math.min(...d.footprint.map(p=>p[0])),minY=Math.min(...d.footprint.map(p=>p[1])),lift=-Math.min(...d.unit_corners.map(p=>p[2]));
  const U=cols*px+(cols-1)*gx,V=rows*py+(rows-1)*gy,axes=d.frame_axes;
  const world=q=>[0,1,2].map(i=>q[0]*axes[0][i]+q[1]*axes[1][i]+q[2]*axes[2][i]);
  // True isometric projection: the X, Y and Z axes have equal foreshortening.
  const iso=q=>[(q[0]+q[1])/Math.sqrt(2),(q[0]-q[1])/Math.sqrt(6)-q[2]*Math.sqrt(2/3)];
  const plane=[[0,0,0],[U,0,0],[U,V,0],[0,V,0]];
  const cells=[];for(let row=0;row<rows;row++)for(let col=0;col<cols;col++){
   const origin=[col*(px+gx)-minX,row*(py+gy)-minY,lift];const local=d.unit_corners.map(p=>p.map((v,i)=>v+origin[i]));cells.push({local,world:local.map(world)});
  }
  const all=plane.map(world).concat(...cells.map(cell=>cell.world)).map(iso),xs=all.map(p=>p[0]),ys=all.map(p=>p[1]);
  const loX=Math.min(...xs),hiX=Math.max(...xs),loY=Math.min(...ys),hiY=Math.max(...ys),scale=Math.max(.00001,Math.min((w-100)/(hiX-loX||1),(h-90)/(hiY-loY||1)));
  const projectWorld=q=>{const p=iso(q);return [w/2+(p[0]-(loX+hiX)/2)*scale,h/2+7+(p[1]-(loY+hiY)/2)*scale];},P=q=>projectWorld(world(q));
  path(c,plane.map(P),true);c.fillStyle='rgba(218,229,238,.55)';c.fill();c.strokeStyle='#adbecb';c.lineWidth=.8;c.stroke();
  const shape=hull(d.footprint),faces=[[0,3,2,1],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[4,5,6,7]],drawFaces=[];
  cells.forEach(cell=>{
   const origin=cell.local[0].map((v,i)=>v-d.unit_corners[0][i]);path(c,shape.map(p=>P([origin[0]+p[0],origin[1]+p[1],0])),true);c.setLineDash([3,3]);c.strokeStyle='rgba(33,102,172,.5)';c.stroke();c.setLineDash([]);
   [0,1,2,3].forEach(i=>{path(c,[P(cell.local[i]),P([cell.local[i][0],cell.local[i][1],0])]);c.setLineDash([2,3]);c.strokeStyle='rgba(100,129,153,.45)';c.lineWidth=.6;c.stroke();c.setLineDash([]);});
   faces.forEach((ids,index)=>drawFaces.push({points:ids.map(i=>projectWorld(cell.world[i])),depth:ids.reduce((sum,i)=>sum+cell.world[i][0]-cell.world[i][1]+cell.world[i][2],0),index}));
  });
  drawFaces.sort((a,b)=>a.depth-b.depth).forEach(face=>{path(c,face.points,true);c.fillStyle=face.index===5?'#477eaa':face.index===0?'#a2b6c7':'#c3d0db';c.fill();c.strokeStyle='#467294';c.lineWidth=.55;c.stroke();});
  const center=P([U/2,V/2,0]),dimensions=[];
  const depth=q=>{const p=world(q);return p[0]-p[1]+p[2];};
  const frontY=depth([U/2,0,0])>=depth([U/2,V,0])?0:V;
  const frontX=depth([0,V/2,0])>=depth([U,V/2,0])?0:U;
  if(cols>1)dimensions.push(dimension(c,P([px,frontY,0]),P([px+gx,frontY,0]),'横 '+gx/10+' cm',center));
  if(rows>1)dimensions.push(dimension(c,P([frontX,py,0]),P([frontX,py+gy,0]),'纵 '+gy/10+' cm',center));
  canvas.dataset.frontEdges=JSON.stringify({x:frontX,y:frontY,width:U,height:V});
  canvas.dataset.dimensions=JSON.stringify(dimensions);
  const origin=cells[0].world[0],a=d.settings.azimuth*Math.PI/180,b=d.settings.tilt*Math.PI/180,r=Math.min(d.spec.length_mm*.28,U*.3,V*.3),horizontal=[-Math.sin(a),-Math.cos(a),0];
  const arc=[];for(let i=0;i<=16;i++){const t=b*i/16;arc.push(projectWorld([origin[0]+horizontal[0]*r*Math.cos(t),origin[1]+horizontal[1]*r*Math.cos(t),origin[2]+r*Math.sin(t)]));}
  path(c,[projectWorld(origin),projectWorld([origin[0]+horizontal[0]*r,origin[1]+horizontal[1]*r,origin[2]])]);c.setLineDash([2,3]);c.strokeStyle='#b9985a';c.stroke();c.setLineDash([]);path(c,arc);c.strokeStyle='#bf9652';c.lineWidth=1;c.stroke();const mid=arc[8];label(c,'β '+Number(d.settings.tilt.toFixed(3))+'°',mid[0]+18,mid[1]-12,'#95733d');
  // Azimuth uses world north, independent of the selected face's rotation.
  const compassCenter=[w-54,48],radius=21,small=q=>[compassCenter[0]+(q[0]+q[1])/Math.sqrt(2),compassCenter[1]+(q[0]-q[1])/Math.sqrt(6)];
  directionGuide(c,compassCenter,q=>{const p=iso(q);return p;});
  const azArc=[];for(let i=0;i<=30;i++){const angle=a*i/30;azArc.push(small([radius*Math.sin(angle),radius*Math.cos(angle)]));}path(c,azArc);c.strokeStyle='#bf9652';c.lineWidth=1;c.stroke();const arrow=small([radius*Math.sin(a),radius*Math.cos(a)]);path(c,[compassCenter,arrow]);c.strokeStyle='#2166ac';c.lineWidth=1.5;c.stroke();label(c,'α '+Number(d.settings.azimuth.toFixed(3))+'°',w-54,99);
  el('unitSize').textContent=cols+' × '+rows;canvas.dataset.azimuth=d.settings.azimuth;canvas.dataset.tilt=d.settings.tilt;canvas.dataset.projection='isometric';
 }
 function draw(){if(state.data&&state.data.forecast_only)return;drawPlan();drawIso();}
 function ruler(id,max){
  const node=el(id+'Ruler'),width=node.clientWidth||220,tickStep=Math.max(5,Math.ceil(max/(width/9)/5)*5);let html='';
  for(let value=0;value<=max&&max>0;value+=tickStep)html+=`<i class="${value%(tickStep*2)===0?'major':''}" style="left:${value/max*100}%"></i>`;node.innerHTML=html;
 }
 function setGaps(d){
  [['gapX','gap_x_mm','gap_max_x_mm'],['gapY','gap_y_mm','gap_max_y_mm']].forEach(([id,key,maxKey])=>{
   const max=d[maxKey]/10;el(id).max=el(id+'Range').max=max;el(id).value=el(id+'Range').value=d.settings[key]/10;el(id).disabled=el(id+'Range').disabled=max===0;
   el(id+'Bounds').innerHTML=max===0?'<span>当前方向无需净距</span>':`<span>0</span><span>${max} cm</span>`;ruler(id,max);
  });
 }
 window.PVArray={
  waitForSelection(){invalidateShading();lab.invalidate();state.dirty=true;window.PV.clear('请选择光伏板或阵列');},
  receive(data){
   if(state.data&&data.target_id<state.data.target_id)return;const next=!state.data||data.target_id!==state.data.target_id;
   if(!next&&data.request_id<state.request)return;if(state.angleDrag)return;
   invalidateShading();
   if(next){clearTimeout(state.timer);state.request=data.request_id||0;}state.data=data;state.dirty=false;state.building=false;controls.setDisabled(false);
   document.querySelectorAll('input,select,#repick').forEach(control=>control.disabled=false);
   controls.setRoof(data.roof_normal||(data.forecast_only?null:data.frame_axes[2]),!!data.forecast_only);
   controls.set(data.settings.azimuth,data.settings.tilt);controls.setCatalog(data.catalog,data.spec.id);controls.setSpec(data.spec);
   document.body.classList.toggle('forecast-only',!!data.forecast_only);
   document.querySelector('.array-mode-tabs').hidden=!!data.forecast_only||!!data.layout_only;
   el('forecastReselect').hidden=!data.forecast_only;
   document.querySelector('[data-array-view="power"]').hidden=!!data.layout_only;
   if(data.forecast_only){
    controls.setDisabled(true);
    el('arrayLayout').hidden=true;el('arrayForecastQuery').hidden=false;el('forecastCount').hidden=false;
    document.querySelectorAll('[data-layout-only]').forEach(node=>node.hidden=true);
    el('forecastCount').textContent=data.count+' 块 · '+data.capacity_kwp.toFixed(2)+' kWp';
    lab.setPlan(data);showForecast();window.PV.resize();return;
   }
   setGaps(data);
   el('targetName').textContent='安装面';
   const {raw}=planFrame(data),corners=[[0,0],[data.width_mm,0],[data.width_mm,data.height_mm],[0,data.height_mm]].map(p=>raw(...p));
   const lowX=Math.min(...corners.map(p=>p[0])),highX=Math.max(...corners.map(p=>p[0])),lowY=Math.min(...corners.map(p=>p[1])),highY=Math.max(...corners.map(p=>p[1]));
   const targetScale=Math.min(62/(highX-lowX),44/(highY-lowY)),tw=(highX-lowX)*targetScale,th=(highY-lowY)*targetScale;
   const rings=data.boundary?[data.boundary.outer,...data.boundary.holes]:[[[0,0],[data.width_mm,0],[data.width_mm,data.height_mm],[0,data.height_mm]]];
   const outline=rings.map(ring=>ring.map((p,i)=>{const q=raw(...p);return (i?'L':'M')+((84-tw)/2+(q[0]-lowX)*targetScale)+','+((64-th)/2+(q[1]-lowY)*targetScale);}).join(' ')+' Z').join(' ');
   el('targetPreview').innerHTML=`<path d="${outline}" fill-rule="evenodd" fill="#edf4fa" stroke="#729abb" stroke-width="1.2"/>`;
   el('targetSize').textContent=(data.width_mm/1000).toFixed(2)+' × '+(data.height_mm/1000).toFixed(2)+' m';
   el('forecastCount').textContent=data.count+' 块 · '+data.capacity_kwp.toFixed(2)+' kWp';el('panelCount').textContent=data.count;el('capacity').textContent=data.capacity_kwp.toFixed(2);el('gridSize').textContent=data.columns+'列 × '+data.rows+'行';
   el('build').disabled=data.count===0;el('build').textContent='生成阵列';el('arrayError').hidden=true;el('arrayStatus').textContent='';lab.setPlan(data);showForecast();draw();
  },
  built(result){state.building=false;el('build').disabled=true;el('build').textContent='已生成阵列';el('arrayStatus').textContent='已生成 '+result.count+' 块组件';document.querySelectorAll('input,select,#repick').forEach(control=>control.disabled=false);controls.setDisabled(false);setGaps(state.data);},
  fail(message){invalidateShading();lab.invalidate();state.dirty=true;window.PV.clear('出力暂不可用');state.building=false;el('arrayError').hidden=false;el('arrayError').textContent=message;el('build').disabled=true;el('build').textContent='生成阵列';el('arrayStatus').textContent='';document.querySelectorAll('input,select,#repick').forEach(control=>control.disabled=false);controls.setDisabled(false);}
 };
 ['gapX','gapY'].forEach(id=>{
  const range=el(id+'Range');
  range.addEventListener('input',()=>{const v=Math.max(0,Math.min(Number(range.max),Math.round(Number(range.value)/5)*5));range.value=el(id).value=v;change();});
  range.addEventListener('keydown',event=>{if(!['ArrowLeft','ArrowDown','ArrowRight','ArrowUp'].includes(event.key))return;event.preventDefault();const sign=['ArrowRight','ArrowUp'].includes(event.key)?1:-1,v=Math.max(0,Math.min(Number(range.max),Math.round(Number(range.value)/5)*5+sign*5));range.value=el(id).value=v;change();});
  el(id).addEventListener('input',()=>{if(el(id).value.trim()!=='')range.value=el(id).value;change();});
 });
 el('build').addEventListener('click',()=>{if(!state.data||state.dirty||state.building||!validGaps()||!state.data.count)return;state.building=true;controls.setDisabled(true);el('build').disabled=true;el('build').textContent='正在生成…';document.querySelectorAll('input,select,#repick').forEach(control=>control.disabled=true);if(window.sketchup)window.sketchup.build(JSON.stringify(params()));});
 el('repick').addEventListener('click',()=>{invalidateShading();lab.invalidate();window.PV.clear('请选择安装面');el('build').disabled=true;state.dirty=true;state.request++;clearTimeout(state.timer);if(window.sketchup)window.sketchup.repick();});
 document.querySelectorAll('[data-array-view]').forEach(button=>button.addEventListener('click',()=>{
  const power=button.dataset.arrayView==='power';
  document.querySelectorAll('[data-array-view]').forEach(b=>b.classList.toggle('active',b===button));
  el('arrayLayout').hidden=power;document.querySelector('.array-power').hidden=!power;el('arrayForecastQuery').hidden=!power;el('forecastCount').hidden=!power;el('shadeControls').hidden=!power;document.querySelectorAll('[data-layout-only]').forEach(node=>node.hidden=power);
  syncLabView();if(power)window.PV.resize();else draw();
 }));
 el('forecastReselect').addEventListener('click',()=>{PVArray.waitForSelection();if(window.sketchup)window.sketchup.repick();});
 window.addEventListener('resize',()=>{draw();if(state.data&&!state.data.forecast_only){ruler('gapX',state.data.gap_max_x_mm/10);ruler('gapY',state.data.gap_max_y_mm/10);}});
 if(window.sketchup&&window.sketchup.ready)window.sketchup.ready();
})();
