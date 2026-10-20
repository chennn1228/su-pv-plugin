'use strict';
(function(){
 const S=window.SuPvShading,$=id=>document.getElementById(id);
 const template=`
 <nav class="lab-steps" aria-label="互遮挡实验步骤">
  <button data-lab-step="2"><b>01</b>太阳角度变化</button><button data-lab-step="3"><b>02</b>遮挡投影</button><button data-lab-step="4"><b>03</b>出力修正</button>
 </nav>
 <section data-lab-page="2" class="lab-page" hidden>
  <div class="lab-heading"><div><h2>太阳角度变化</h2></div><button class="secondary" data-lab-play>播放一天</button></div>
  <div class="lab-grid lab-sun-grid"><div class="lab-card"><div class="lab-canvas sun-canvas"><canvas id="labSunSky" aria-label="太阳一日轨迹及光照方向"></canvas></div></div><div class="lab-card"><div class="lab-canvas sun-canvas"><canvas id="labSunAngles" aria-label="太阳高度角和方位角随时间变化"></canvas></div></div></div>
  <div id="labSunMetrics" class="lab-stat-row"></div>
 </section>
 <section data-lab-page="3" class="lab-page" hidden>
  <div class="lab-heading"><div><h2>遮挡投影</h2><p id="labShadowSummary"></p></div><button class="secondary" data-lab-play>播放一天</button></div>
  <div class="lab-grid lab-shadow-grid"><div class="lab-card"><div class="lab-canvas shadow-canvas"><canvas id="labArrayShadow" aria-label="实际阵列单面、互遮挡区域和太阳射线，点击选择板"></canvas></div><div class="lab-key"><span class="lit">未遮挡</span><span class="shadow">遮挡</span></div></div>
  <div class="lab-card"><label class="lab-panel-picker">查看板号<input id="labPanelIndex" type="number" min="1" step="1" value="1"></label><div class="lab-canvas panel-canvas"><canvas id="labPanelShadow" aria-label="所选光伏板展开后的实际阴影面积"></canvas></div><div id="labPanelMetrics"></div></div></div>
 </section>
 <section data-lab-page="4" class="lab-page" hidden>
  <div class="lab-heading"><div><h2>出力修正</h2></div></div>
  <div id="labCalculationState" role="status"></div><div id="labComparison" class="lab-stat-row" hidden></div><div id="labHourEquation" class="lab-equation" hidden></div>
 </section>
 <div class="lab-footer"><button id="labPrevious" class="secondary">上一步</button><button id="labNext" class="primary">下一步</button></div>`;
 function create(hooks){
  const mount=$('shadingLab');mount.innerHTML=template;
  const state={active:false,step:2,location:S.site,plan:null,g:null,now:null,result:null,selected:null,playing:null,frame:null,yaw:-Math.PI/4,zoom:1,hits:[]};
  function index(){const m=Number($('month').value),day=Number($('day').value);return ((Date.UTC(state.location.year,m-1,day)-Date.UTC(state.location.year,0,1))/86400000)*24+Number($('hour').value);}
  function timeLabel(){return `${state.location.year}年${$('month').value}月${$('day').value}日 ${String($('hour').value).padStart(2,'0')}:30`;}
  function stop(){if(state.playing)clearInterval(state.playing);state.playing=null;mount.querySelectorAll('[data-lab-play]').forEach(b=>b.textContent='播放一天');}
  function schedule(){if(!state.frame)state.frame=requestAnimationFrame(()=>{state.frame=null;if(state.active)render();});}
  function timeChanged(){state.now=null;schedule();}
  ['month','day','hour'].forEach(id=>$(id).addEventListener('input',timeChanged));
  window.addEventListener('pv-time-query',timeChanged);
  function setStep(step){
   stop();state.step=step;
   mount.classList.toggle('lab-result-step',step===4);
   mount.querySelectorAll('[data-lab-step]').forEach(b=>{b.classList.toggle('active',Number(b.dataset.labStep)===step);b.setAttribute('aria-current',Number(b.dataset.labStep)===step?'step':'false');});
   mount.querySelectorAll('[data-lab-page]').forEach(p=>p.hidden=Number(p.dataset.labPage)!==step);
   $('labPrevious').hidden=step===2;$('labNext').hidden=step===4;
   $('labNext').textContent=step===3?'查看修正步骤':'下一步';
   hooks.onStepChange(step);schedule();
  }
  mount.querySelectorAll('[data-lab-step]').forEach(b=>b.addEventListener('click',()=>setStep(Number(b.dataset.labStep))));
  $('labNext').addEventListener('click',()=>setStep(Math.min(4,state.step+1)));
  $('labPrevious').addEventListener('click',()=>setStep(Math.max(2,state.step-1)));
  mount.querySelectorAll('[data-lab-play]').forEach(b=>b.addEventListener('click',()=>{
   if(state.playing){stop();return;}mount.querySelectorAll('[data-lab-play]').forEach(n=>n.textContent='暂停');
   state.playing=setInterval(()=>{if(document.hidden){stop();return;}$('hour').value=(Number($('hour').value)+1)%24;$('hour').dispatchEvent(new Event('input'));},600);
  }));
  $('labPanelIndex').addEventListener('input',()=>{const value=Number($('labPanelIndex').value)-1;if(state.g&&Number.isInteger(value)&&value>=0&&value<state.g.panels.length){state.selected=value;schedule();}});
  function canvas(id){
   const node=$(id),w=node.clientWidth,h=node.clientHeight,r=Math.min(2,devicePixelRatio||1);node.width=Math.max(1,Math.round(w*r));node.height=Math.max(1,Math.round(h*r));
   const c=node.getContext('2d');c.setTransform(r,0,0,r,0,0);c.clearRect(0,0,w,h);c.font='12px "Segoe UI","Microsoft YaHei",sans-serif';c.fillStyle='#708191';return {c,w,h};
  }
  function path(c,points,close=false){c.beginPath();points.forEach((p,i)=>i?c.lineTo(...p):c.moveTo(...p));if(close)c.closePath();}
  function text(c,value,x,y,align='center',color='#708191'){c.fillStyle=color;c.textAlign=align;c.fillText(value,x,y);}
  function arrow(c,a,b,color='#d99b30'){
   path(c,[a,b]);c.strokeStyle=color;c.lineWidth=1.3;c.stroke();const angle=Math.atan2(b[1]-a[1],b[0]-a[0]);
   path(c,[b,[b[0]-7*Math.cos(angle-.4),b[1]-7*Math.sin(angle-.4)],[b[0]-7*Math.cos(angle+.4),b[1]-7*Math.sin(angle+.4)]],true);c.fillStyle=color;c.fill();
  }
  function stat(label,value,unit='',className=''){return `<div class="${className}"><small>${label}</small><strong>${value}<span>${unit}</span></strong></div>`;}
  function now(){if(!state.now){const idx=index(),sun=S.atHour(state.g||{panels:[],n:[0,0,1]},idx,state.location,true);state.now={...sun,index:idx};}return state.now;}
  function daySun(hour){return S.solarPosition({...state.location,month:Number($('month').value),day:Number($('day').value),hour:Math.min(23.9999,hour)});}
  function solar(){
   const n=now(),points=Array.from({length:97},(_,i)=>daySun(i/4)),{c,w,h}=canvas('labSunSky'),scale=Math.min(w*.3,h*.42);
   const iso=p=>[w/2+(p[0]+p[1])/Math.sqrt(2)*scale,h*.65+(p[0]-p[1])/Math.sqrt(6)*scale-p[2]*Math.sqrt(2/3)*scale];
   const ring=Array.from({length:97},(_,i)=>iso([Math.sin(i/96*Math.PI*2),Math.cos(i/96*Math.PI*2),0]));path(c,ring,true);c.fillStyle='#edf4f9';c.fill();c.strokeStyle='#c2d2df';c.stroke();
   const O=iso([0,0,0]);[[1,0,0,'E'],[0,1,0,'N'],[-1,0,0,'W'],[0,-1,0,'S']].forEach(p=>{const q=iso(p);path(c,[O,q]);c.strokeStyle='#d4e0e9';c.stroke();text(c,p[3],q[0],q[1]+15);});
   let pen=false;c.beginPath();points.forEach(s=>{if(s.elevation_deg<0){pen=false;return;}const p=iso(s.vector);if(!pen)c.moveTo(...p);else c.lineTo(...p);pen=true;});c.strokeStyle='#2166ac';c.lineWidth=2;c.stroke();
   const placed=[];for(let hour=0;hour<24;hour+=3){const s=daySun(hour+.5);if(s.elevation_deg<=0)continue;const p=iso(s.vector);c.beginPath();c.arc(...p,2,0,Math.PI*2);c.fillStyle='#2166ac';c.fill();if(placed.every(q=>Math.hypot(q[0]-p[0],q[1]-p[1])>35)){text(c,`${hour}:30`,p[0],p[1]-9);placed.push(p);}}
   const p=iso(n.sun.vector);if(n.sun.elevation_deg>0){arrow(c,p,O);c.beginPath();c.arc(...p,7,0,Math.PI*2);c.fillStyle='#edb244';c.fill();}else text(c,'太阳在地平线下',w/2,28);
   
   const plot=canvas('labSunAngles'),C=plot.c,W=plot.w,H=plot.h,L=42,R=W-16;
   function graph(top,bottom,key,min,max,title,color){
    const X=t=>L+t/24*(R-L),Y=v=>bottom-(v-min)/(max-min)*(bottom-top);
    text(C,title,L,top-12,'left');for(let j=0;j<=2;j++){const v=min+(max-min)*j/2;path(C,[[L,Y(v)],[R,Y(v)]]);C.strokeStyle='#e2eaf0';C.lineWidth=1;C.stroke();text(C,v+'°',L-8,Y(v)+4,'right');}
    C.beginPath();let last=null;points.forEach((s,i)=>{const v=s[key],p=[X(i/4),Y(v)];if(last===null||Math.abs(v-last)>180)C.moveTo(...p);else C.lineTo(...p);last=v;});C.strokeStyle=color;C.lineWidth=1.8;C.stroke();
    const x=X(Number($('hour').value)+.5),y=Y(n.sun[key]);path(C,[[x,top],[x,bottom]]);C.setLineDash([3,3]);C.strokeStyle='#c9a260';C.lineWidth=1;C.stroke();C.setLineDash([]);C.beginPath();C.arc(x,y,4,0,Math.PI*2);C.fillStyle=color;C.fill();
    for(let t=0;t<=24;t+=6)text(C,String(t),X(t),bottom+17);
   }
   graph(30,H*.43,'elevation_deg',-90,90,'太阳高度角','#2166ac');graph(H*.59,H-29,'azimuth_deg',0,360,'太阳方位角','#d79a32');
   $('labSunMetrics').innerHTML=stat('太阳方位角',n.sun.azimuth_deg.toFixed(1),'°')+stat('太阳高度角',n.sun.elevation_deg.toFixed(1),'°')+stat('当前直射条件',n.sun.elevation_deg<=0?'地平线下':n.front_beam?'正面直射':'板背侧');
  }
  $('labSunAngles').addEventListener('click',event=>{const rect=event.currentTarget.getBoundingClientRect();$('hour').value=Math.max(0,Math.min(23,Math.floor((event.clientX-rect.left-42)/(rect.width-58)*24)));$('hour').dispatchEvent(new Event('input'));});
  function polygon(rect){return [[rect[0],rect[1]],[rect[2],rect[1]],[rect[2],rect[3]],[rect[0],rect[3]]];}
  function shadow(){
   const box=canvas('labArrayShadow'),{c,w,h}=box;
   if(!state.g||!state.g.panels.length){text(c,'当前没有可分析的板',w/2,h/2);canvas('labPanelShadow');$('labPanelMetrics').textContent='';$('labShadowSummary').textContent='等待有效阵列排布';$('labPanelIndex').disabled=true;return;}
   $('labPanelIndex').disabled=false;
   const g=state.g,n=now();
   if(state.selected===null||state.selected>=g.panels.length)state.selected=n.ratios.indexOf(Math.min(...n.ratios));
   const chosen=state.selected,co=Math.cos(state.yaw),si=Math.sin(state.yaw);
   const world=(p,x=0,y=0)=>g.u.map((u,i)=>u*(p[0]+x)+g.v[i]*(p[1]+y)+g.n[i]*p[2]);
   const project=p=>[co*p[0]-si*p[1],-(si*p[0]+co*p[1])/Math.sqrt(3)-p[2]*Math.sqrt(2/3)];
   const depth=p=>(si*p[0]+co*p[1])*Math.sqrt(2/3)-p[2]/Math.sqrt(3);
   const faceRect=[0,0,g.w,g.l],faces=g.panels.map((p,id)=>({id,points:polygon(faceRect).map(([x,y])=>world(p,x,y)),depth:depth(world(p,g.w/2,g.l/2))}));
   const rings=state.plan.boundary?[state.plan.boundary.outer,...state.plan.boundary.holes]:[[[0,0],[state.plan.width_mm,0],[state.plan.width_mm,state.plan.height_mm],[0,state.plan.height_mm]]];
   const origin=state.plan.positions[0],roof=rings.map(ring=>ring.map(([x,y])=>[0,1,2].map(i=>state.plan.frame_axes.reduce((s,axis,k)=>s+([x,y,0][k]-origin[k])*axis[i],0))));
   const rays=[];
   for(const s of n.shadows[chosen].slice(0,3)){
    const r=s.rect,base=world(g.panels[chosen],(r[0]+r[2])/2,(r[1]+r[3])/2),sn=g.n.reduce((v,q,i)=>v+q*n.sun.vector[i],0),t=(g.panels[s.blocker][2]-g.panels[chosen][2])/sn;
    rays.push({a:base.map((v,i)=>v+n.sun.vector[i]*t),b:base,blocker:s.blocker});
   }
   if(n.front_beam&&!rays.length){const p=g.panels[chosen];for(const q of [[.3,.3],[.7,.3],[.5,.7]]){const b=world(p,g.w*q[0],g.l*q[1]);rays.push({a:b.map((v,i)=>v+n.sun.vector[i]*g.l*.65),b});}}
   const all=faces.flatMap(f=>f.points).concat(roof.flat(),rays.flatMap(r=>[r.a,r.b])).map(project),xs=all.map(p=>p[0]),ys=all.map(p=>p[1]),lo=[Math.min(...xs),Math.min(...ys)],hi=[Math.max(...xs),Math.max(...ys)];
   const scale=Math.min((w-44)/(hi[0]-lo[0]||1),(h-50)/(hi[1]-lo[1]||1))*state.zoom;
   const P=p=>{const q=project(p);return [w/2+(q[0]-(lo[0]+hi[0])/2)*scale,h/2+(q[1]-(lo[1]+hi[1])/2)*scale];};
   c.beginPath();roof.forEach(r=>{r.map(P).forEach((p,i)=>i?c.lineTo(...p):c.moveTo(...p));c.closePath();});c.fillStyle='#eff4f8';c.fill('evenodd');c.strokeStyle='#c1cfda';c.stroke();
   const blockers=[...new Set(rays.filter(r=>r.blocker!==undefined).map(r=>r.blocker))];
   state.hits=[];faces.sort((a,b)=>b.depth-a.depth).forEach(f=>{
    const points=f.points.map(P);path(c,points,true);c.fillStyle='#a9cee5';c.fill();
    c.beginPath();for(const s of n.shadows[f.id]){polygon(s.rect).map(([x,y])=>P(world(g.panels[f.id],x,y))).forEach((p,i)=>i?c.lineTo(...p):c.moveTo(...p));c.closePath();}c.fillStyle='#e8ad4f';c.fill();
    path(c,points,true);c.strokeStyle=f.id===chosen?'#183347':blockers.includes(f.id)?'#b67519':'#668dac';c.lineWidth=f.id===chosen||blockers.includes(f.id)?2:.65;c.stroke();state.hits.push({id:f.id,points});
   });
   rays.forEach(r=>arrow(c,P(r.a),P(r.b),'#b67519'));
   const marked=P(world(g.panels[chosen],g.w/2,g.l/2));text(c,'#'+(chosen+1),marked[0],marked[1]+4,'center','#183347');
   blockers.forEach(id=>{const p=P(world(g.panels[id],g.w/2,g.l/2));text(c,'#'+(id+1),p[0],p[1]+4,'center','#8e5b17');});
   // World compass uses the same camera as the array.
   const C=[w-37,35],p0=project([0,0,0]);[[0,1,0,'N'],[1,0,0,'E']].forEach(v=>{const p=project(v);arrow(c,C,[C[0]+(p[0]-p0[0])*24,C[1]+(p[1]-p0[1])*24],'#93a9ba');text(c,v[3],C[0]+p[0]*32,C[1]+p[1]*32);});
   $('labPanelIndex').max=g.panels.length;$('labPanelIndex').value=chosen+1;
   const single=canvas('labPanelShadow'),C2=single.c,margin=26,k=Math.min((single.w-margin*2)/g.w,(single.h-margin*2)/g.l),left=(single.w-g.w*k)/2,top=(single.h-g.l*k)/2;
   C2.fillStyle='#a9cee5';C2.fillRect(left,top,g.w*k,g.l*k);C2.beginPath();n.shadows[chosen].forEach(s=>{const r=s.rect;C2.rect(left+r[0]*k,top+r[1]*k,(r[2]-r[0])*k,(r[3]-r[1])*k);});C2.fillStyle='#e8ad4f';C2.fill();C2.strokeStyle='#668dac';C2.strokeRect(left,top,g.w*k,g.l*k);
   text(C2,(g.w/1000).toFixed(3)+' m',single.w/2,top+g.l*k+18);text(C2,'板面展开 · #'+(chosen+1),single.w/2,15);
   C2.save();C2.translate(left-10,top+g.l*k/2);C2.rotate(-Math.PI/2);text(C2,(g.l/1000).toFixed(3)+' m',0,0);C2.restore();
   const ratio=n.ratios[chosen],area=g.w*g.l/1e6;
   $('labPanelMetrics').innerHTML=stat('遮挡面积',((1-ratio)*area).toFixed(3),'m²')+stat('未遮挡面积',(ratio*area).toFixed(3),'m²')+`<div class="lab-area-formula">${(ratio*area).toFixed(3)} ÷ ${area.toFixed(3)} ≈ <b>${(ratio*100).toFixed(2)}%</b></div>`;
   $('labShadowSummary').textContent=n.front_beam?'未遮挡面积 '+(n.factor*100).toFixed(2)+'%':'无正面直射';
   $('labArrayShadow').dataset.factor=n.factor;$('labArrayShadow').dataset.selected=chosen;$('labPanelShadow').dataset.shadedArea=(1-ratio)*area;
  }
  let drag=null;
  $('labArrayShadow').addEventListener('pointerdown',e=>{drag={x:e.clientX,last:e.clientX,moved:false};e.currentTarget.setPointerCapture(e.pointerId);});
  $('labArrayShadow').addEventListener('pointermove',e=>{if(!drag)return;const dx=e.clientX-drag.last;if(Math.abs(e.clientX-drag.x)>4)drag.moved=true;if(drag.moved){state.yaw+=dx*.008;schedule();}drag.last=e.clientX;});
  $('labArrayShadow').addEventListener('pointerup',e=>{
   if(drag&&!drag.moved){const rect=e.currentTarget.getBoundingClientRect(),x=e.clientX-rect.left,y=e.clientY-rect.top;
    const inside=points=>{let hit=false;for(let i=0,j=points.length-1;i<points.length;j=i++){const a=points[i],b=points[j];if((a[1]>y)!==(b[1]>y)&&x<(b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0])hit=!hit;}return hit;};
    const found=state.hits.slice().reverse().find(f=>inside(f.points));if(found){state.selected=found.id;schedule();}
   }drag=null;
  });
  $('labArrayShadow').addEventListener('pointercancel',()=>drag=null);
  $('labArrayShadow').addEventListener('wheel',e=>{e.preventDefault();state.zoom=Math.max(.5,Math.min(4,state.zoom*Math.exp(-e.deltaY*.001)));schedule();},{passive:false});
  function comparison(){
   const r=state.result;$('labComparison').hidden=!r;$('labHourEquation').hidden=!r;
   if(!r)return;
   $('labComparison').innerHTML=stat('原始全年电量',r.baseline_kwh.toFixed(2),'kWh')+stat('修正后全年电量',r.annual_kwh.toFixed(2),'kWh');
   const idx=index(),baseline=state.plan.prediction.values[idx],factor=r.factors[idx];
   $('labHourEquation').textContent=`${timeLabel()}：${baseline.toFixed(2)} W × ${(factor*100).toFixed(2)}% ≈ ${r.values[idx].toFixed(2)} W`;
  }
  function render(){if(state.step===2)solar();else if(state.step===3)shadow();else comparison();}
  window.addEventListener('resize',schedule);window.addEventListener('unload',stop);
  setStep(2);
  return {
   get step(){return state.step;},get location(){return {...state.location};},get ready(){return !!state.result;},
   setActive(value){state.active=value;mount.hidden=!value;document.body.classList.toggle('lab-process',value&&state.step<4);if(!value)stop();schedule();},
   setPlan(plan){stop();state.plan=plan;state.g=S.geometry(plan);state.now=null;state.selected=null;state.zoom=1;state.result=null;comparison();$('labCalculationState').textContent='';schedule();},
   invalidate(){stop();state.plan=null;state.g=null;state.now=null;state.result=null;comparison();$('labCalculationState').textContent='等待有效阵列排布';schedule();},
   resetResult(){state.result=null;comparison();$('labCalculationState').textContent='';schedule();},
   calculation(message,result=null){state.result=result;comparison();$('labCalculationState').textContent=result?'':message;schedule();},
   showStep:setStep
  };
 }
 window.PVShadingLab={create};
})();
