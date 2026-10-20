/* Shared model and angle widgets for tool 2 and tool 3. */
'use strict';
(function(){
 const el=id=>document.getElementById(id);
 const angleTemplate="<h2 class=\"section-label\">角度组合</h2><div class=\"angle-grid\">\n        <div class=\"angle-card\"><svg id=\"compass\" viewBox=\"0 0 120 108\" role=\"slider\" tabindex=\"0\" aria-label=\"拖动选择方位角\" aria-valuemin=\"90\" aria-valuemax=\"270\" aria-valuenow=\"180\"><circle cx=\"60\" cy=\"54\" r=\"30\" fill=\"none\" stroke=\"#e0e8ee\"/><path d=\"M60 22V86M28 54H92\" stroke=\"#d4dfe8\"/><path id=\"compassNeedle\" d=\"M60 25L55 57L60 53L65 57Z\" fill=\"#2166ac\"/><circle cx=\"60\" cy=\"54\" r=\"2.5\" fill=\"#2166ac\"/><g fill=\"#617789\" font-size=\"10\" text-anchor=\"middle\"><text x=\"60\" y=\"14\">北 0°</text><text x=\"106\" y=\"58\">东</text><text x=\"60\" y=\"102\">南 180°</text><text x=\"14\" y=\"58\">西</text></g></svg><div class=\"angle-control\"><label for=\"azimuth\">方位角 <b id=\"azimuthValue\">180°</b></label><select id=\"azimuthSelect\" aria-label=\"选择方位角\"></select><input id=\"azimuth\" type=\"range\" min=\"90\" max=\"270\" step=\"5\" value=\"180\"></div></div>\n        <div class=\"angle-card\"><svg id=\"tiltDiagram\" viewBox=\"0 0 120 108\" role=\"slider\" tabindex=\"0\" aria-label=\"拖动选择倾角\" aria-valuemin=\"0\" aria-valuemax=\"90\" aria-valuenow=\"30\"><path d=\"M14 84H106M22 84V15\" stroke=\"#d4dfe8\" stroke-dasharray=\"3 3\"/><path d=\"M44 84A22 22 0 0 0 22 62\" fill=\"none\" stroke=\"#d4dfe8\"/><line id=\"tiltPanel\" x1=\"22\" y1=\"84\" x2=\"87\" y2=\"46.5\" stroke=\"#2166ac\" stroke-width=\"5\" stroke-linecap=\"round\"/><circle cx=\"22\" cy=\"84\" r=\"3\" fill=\"#2166ac\"/><g fill=\"#617789\" font-size=\"10\"><text x=\"96\" y=\"101\">0°</text><text x=\"27\" y=\"19\">90°</text></g></svg><div class=\"angle-control\"><label for=\"tilt\">倾角 <b id=\"tiltValue\">30°</b></label><select id=\"tiltSelect\" aria-label=\"选择倾角\"></select><input id=\"tilt\" type=\"range\" min=\"0\" max=\"90\" step=\"3\" value=\"30\"></div></div>\n      </div>";
 document.querySelectorAll('[data-pv-angles]').forEach(node=>{
  node.innerHTML=angleTemplate;
  const title=node.querySelector('.section-label'),header=document.createElement('div');header.className='angle-heading';
  title.before(header);header.append(title);
  header.insertAdjacentHTML('beforeend','<div id="roofAngleSummary" class="roof-angle-summary" hidden><span>屋面坡度 <b id="roofSlopeValue"></b></span><span>屋面方位 <b id="roofAspectValue"></b></span></div>');
  header.insertAdjacentHTML('afterend','<div id="roofFitControl" class="roof-fit-row" hidden><button id="fitRoof" class="secondary fit-roof" hidden>贴合屋面</button><span id="roofRelativeAngle"></span></div>');
  node.querySelector('#tiltDiagram').insertAdjacentHTML('afterbegin','<line id="roofSlopeLine" x1="22" y1="84" x2="74" y2="84" stroke="#96a4af" stroke-width="2" stroke-dasharray="4 3" style="display:none"/>');
  node.querySelector('#tilt').insertAdjacentHTML('afterend','<span id="tiltBounds" class="angle-range" hidden></span>');
  node.querySelector('label[for="tilt"]').firstChild.textContent='板面倾角 ';
 });
 document.querySelectorAll('[data-pv-product]').forEach(node=>{
  node.innerHTML='<div class="product-heading"><label for="panelModel">组件型号</label><select id="panelModel" aria-label="选择光伏组件"><option value="TSM-NE19R">天合光能－晶硅－630 W</option></select></div>'+
   '<div class="product-body"><svg id="panelPreview" viewBox="35 -5 190 140" role="img" aria-label="光伏组件轴测示意"></svg>'+
   '<table class="product-specs" aria-label="组件参数"><tbody>'+
   '<tr><th scope="row">型号</th><td colspan="3" id="productModel">—</td></tr>'+
   '<tr><th scope="row">材料</th><td id="panelMaterial">—</td><th scope="row">类型</th><td id="panelType">—</td></tr>'+
   '<tr><th scope="row">效率</th><td colspan="3" id="panelEfficiency">—</td></tr>'+
   '<tr><th scope="row">尺寸</th><td colspan="3" id="dimensions">—</td></tr>'+
   '</tbody></table></div><span id="dataStatus" hidden>暂无出力数据</span>';
 });
  function renderProduct(element,spec,azimuth,tilt){
    const a=azimuth*Math.PI/180,b=tilt*Math.PI/180;
    const u=[-Math.cos(a),Math.sin(a),0],v=[-Math.cos(b)*Math.sin(a),-Math.cos(b)*Math.cos(a),Math.sin(b)];
    const n=[Math.sin(b)*Math.sin(a),Math.sin(b)*Math.cos(a),Math.cos(b)];
    const w=spec.width_mm,l=spec.length_mm,t=spec.thickness_mm,scale=135/Math.hypot(w,l);
    const world=(x,y,z)=>u.map((c,i)=>c*x+v[i]*y+n[i]*z);
    const projectPoint=p=>[120+(p[0]+p[1])/Math.sqrt(2)*scale,65+(p[0]-p[1])/Math.sqrt(6)*scale-p[2]*Math.sqrt(2/3)*scale];
    const corners=[[0,0,0],[w,0,0],[w,l,0],[0,l,0],[0,0,t],[w,0,t],[w,l,t],[0,l,t]].map(p=>world(p[0]-w/2,p[1]-l/2,p[2]-t/2));
    const faces=[[0,3,2,1],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[4,5,6,7]];
    // Same world transform as the SketchUp component, parallel projection, back-to-front faces.
    const depth=p=>p[0]-p[1]+p[2];
    let svg='';
    const axes=[[1,0,0,'E +X','#ba9292'],[0,1,0,'N +Y','#8baa96'],[0,0,1,'Z','#96a9c0']];
    const origin=[120,65];
    axes.forEach(axis=>{const end=projectPoint(axis.slice(0,3).map(v=>v*Math.hypot(w,l)*.42));svg+=`<g opacity=".6"><line x1="${origin[0]}" y1="${origin[1]}" x2="${end[0]}" y2="${end[1]}" stroke="${axis[4]}" stroke-dasharray="3 3"/><text x="${end[0]+4}" y="${end[1]+3}" fill="${axis[4]}" font-size="9">${axis[3]}</text></g>`;});
    faces.map((ids,i)=>({ids,i,depth:ids.reduce((sum,id)=>sum+depth(corners[id]),0)})).sort((a,b)=>a.depth-b.depth).forEach(face=>{
      svg+=`<polygon points="${face.ids.map(id=>projectPoint(corners[id]).join(',')).join(' ')}" fill="${face.i===5?'#245a8e':face.i===0?'#8ca0b2':'#b4c2cf'}" stroke="#718ba1" stroke-width=".8"/>`;
    });
    element.innerHTML=svg;element.dataset.azimuth=azimuth;element.dataset.tilt=tilt;
  }

 function create(options){
  let azimuth=180,tilt=30,spec=null,disabled=false,roofNormal=null,minTilt=0,maxTilt=90,readOnly=false,available=true;
  const degrees=value=>Number(value.toFixed(3))+'°';
  const exact=value=>Math.abs(value-Math.round(value))<1e-9?Math.round(value):value;
  function ensureOption(id,value){if(!Array.from(el(id).options).some(option=>Number(option.value)===value))el(id).add(new Option(degrees(value),String(value)));}
  el('panelModel').addEventListener('change',()=>{if(!disabled&&options.onModelChange)options.onModelChange(el('panelModel').value);});
  for(let a=90;a<=270;a+=5)el('azimuthSelect').add(new Option(a+'°',String(a)));
  for(let t=0;t<=90;t+=3)el('tiltSelect').add(new Option(t+'°',String(t)));
  function updateLimits(a){
   minTilt=0;maxTilt=90;
   if(roofNormal&&!readOnly){
    minTilt=exact(Math.atan2(Math.hypot(roofNormal[0],roofNormal[1]),roofNormal[2])*180/Math.PI);
    const rad=a*Math.PI/180,facing=roofNormal[0]*Math.sin(rad)+roofNormal[1]*Math.cos(rad);
    if(facing < -1e-9)maxTilt=exact(Math.atan2(Math.max(0,roofNormal[2]),-facing)*180/Math.PI);
   }
   available=maxTilt+1e-7>=minTilt;
   const values=[minTilt];if(available){for(let t=0;t<=90;t+=3)if(t>minTilt+1e-7&&t<=maxTilt+1e-7)values.push(t);if(Math.abs(values[values.length-1]-maxTilt)>1e-7)values.push(maxTilt);}
   el('tiltSelect').replaceChildren(...values.map(value=>new Option(degrees(value),String(value))));
   el('tilt').min=minTilt;el('tilt').max=available?maxTilt:minTilt;el('tilt').step='any';
   el('tiltDiagram').setAttribute('aria-valuemin',minTilt);el('tiltDiagram').setAttribute('aria-valuemax',available?maxTilt:minTilt);
   el('tiltBounds').textContent=available?degrees(minTilt)+' — '+degrees(maxTilt):'当前方位无可用倾角';
   ['tilt','tiltSelect'].forEach(id=>el(id).disabled=disabled||!available);
   el('tiltDiagram').setAttribute('aria-disabled',String(disabled||!available));el('tiltDiagram').setAttribute('tabindex',disabled||!available?'-1':'0');
  }
  function set(a,t){
   updateLimits(a);t=available?Math.max(minTilt,Math.min(maxTilt,t)):minTilt;
   a=exact(a);t=exact(t);ensureOption('azimuthSelect',a);ensureOption('tiltSelect',t);
   azimuth=a;tilt=t;el('azimuth').value=el('azimuthSelect').value=a;el('tilt').value=el('tiltSelect').value=t;
   el('azimuthValue').textContent=degrees(a);el('tiltValue').textContent=degrees(t);
   el('compassNeedle').setAttribute('transform',`rotate(${a} 60 54)`);
   const rad=t*Math.PI/180;el('tiltPanel').setAttribute('x2',22+75*Math.cos(rad));el('tiltPanel').setAttribute('y2',84-75*Math.sin(rad));
   el('compass').setAttribute('aria-valuenow',a);el('tiltDiagram').setAttribute('aria-valuenow',t);
   if(roofNormal){
    const ar=a*Math.PI/180,section=Math.atan2(roofNormal[0]*Math.sin(ar)+roofNormal[1]*Math.cos(ar),roofNormal[2]);
    el('roofSlopeLine').setAttribute('x2',22+75*Math.cos(section));el('roofSlopeLine').setAttribute('y2',84-75*Math.sin(section));
    const facing=Math.sin(rad)*(roofNormal[0]*Math.sin(ar)+roofNormal[1]*Math.cos(ar))+Math.cos(rad)*roofNormal[2];
    const delta=Math.acos(Math.max(-1,Math.min(1,facing/Math.hypot(...roofNormal))))*180/Math.PI;
    el('roofRelativeAngle').textContent='与屋面夹角 '+Number(delta.toFixed(1))+'°';el('roofRelativeAngle').dataset.degrees=delta;
   }
   if(spec)renderProduct(el('panelPreview'),spec,a,t);
  }
  function snap(id,value){const allowed=Array.from(el(id).options,option=>Number(option.value));return allowed.reduce((best,item)=>Math.abs(item-value)<Math.abs(best-value)?item:best,allowed[0]);}
  function notify(commit){if(disabled)return;set(snap('azimuthSelect',Number(el('azimuth').value)),snap('tiltSelect',Number(el('tilt').value)));const handler=commit?options.onCommit:options.onInput;if(handler)handler(azimuth,tilt);}
  el('fitRoof').addEventListener('click',()=>{
   if(disabled||!roofNormal)return;
   const slope=exact(Math.atan2(Math.hypot(roofNormal[0],roofNormal[1]),roofNormal[2])*180/Math.PI);
   const bearing=slope<1e-7?azimuth:exact((Math.atan2(roofNormal[0],roofNormal[1])*180/Math.PI+360)%360);
   set(bearing,slope);if(options.onCommit)options.onCommit(azimuth,tilt);
  });
  ['azimuth','tilt'].forEach(name=>{
   el(name).addEventListener('input',()=>notify(false));
   el(name).addEventListener('change',()=>notify(true));
   el(name+'Select').addEventListener('change',()=>{el(name).value=el(name+'Select').value;notify(true);});
  });
  el('tilt').addEventListener('keydown',event=>{
   if(disabled||!['ArrowLeft','ArrowDown','ArrowRight','ArrowUp','Home','End'].includes(event.key))return;
   event.preventDefault();const values=Array.from(el('tiltSelect').options,option=>Number(option.value)).sort((a,b)=>a-b);
   const up=['ArrowRight','ArrowUp'].includes(event.key),value=event.key==='Home'?values[0]:event.key==='End'?values[values.length-1]:up?(values.find(v=>v>tilt+1e-7)??values[values.length-1]):([...values].reverse().find(v=>v<tilt-1e-7)??values[0]);
   el('tilt').value=value;notify(true);
  });
  function diagram(id,name,min,max,step,angleAt){
   const svg=el(id);let active=false;
   function update(event){
    const matrix=svg.getScreenCTM();if(!matrix)return;
    const point=svg.createSVGPoint();point.x=event.clientX;point.y=event.clientY;const local=point.matrixTransform(matrix.inverse());
    const lower=Number(el(name).min),upper=Number(el(name).max);
    const value=Math.max(lower,Math.min(upper,Math.round(angleAt(local)/step)*step));
    el(name).value=value;notify(false);
   }
   svg.addEventListener('pointerdown',event=>{if(disabled||(name==='tilt'&&!available)||event.button!==0)return;active=true;svg.setPointerCapture(event.pointerId);update(event);event.preventDefault();});
   svg.addEventListener('pointermove',event=>{if(active)update(event);});
   svg.addEventListener('pointerup',event=>{if(active){update(event);active=false;notify(true);}});
   svg.addEventListener('pointercancel',()=>{if(active){active=false;notify(true);}});
   svg.addEventListener('keydown',event=>{
    if(disabled||(name==='tilt'&&!available))return;
    if(!['ArrowLeft','ArrowDown','ArrowRight','ArrowUp','Home','End'].includes(event.key))return;event.preventDefault();
    const lower=Number(el(name).min),upper=Number(el(name).max);
    const old=name==='azimuth'?azimuth:tilt,value=event.key==='Home'?lower:event.key==='End'?upper:Math.max(lower,Math.min(upper,old+(['ArrowRight','ArrowUp'].includes(event.key)?step:-step)));
    el(name).value=value;notify(true);
   });
  }
  diagram('compass','azimuth',90,270,5,p=>(Math.atan2(p.x-60,54-p.y)*180/Math.PI+360)%360);
  diagram('tiltDiagram','tilt',0,90,3,p=>Math.atan2(84-p.y,p.x-22)*180/Math.PI);
  set(azimuth,tilt);
  return {set,setRoof(normal,readonly=false){
   roofNormal=normal||null;readOnly=readonly;
   const slope=normal?Math.atan2(Math.hypot(normal[0],normal[1]),normal[2])*180/Math.PI:0;
   el('azimuth').min=0;el('azimuth').max=360;el('azimuth').step='any';
   el('compass').setAttribute('aria-valuemin','0');el('compass').setAttribute('aria-valuemax','360');
   el('azimuthSelect').replaceChildren(...Array.from({length:73},(_,i)=>new Option(i*5+'°',String(i*5))));
   el('roofAngleSummary').hidden=!normal;el('roofSlopeValue').textContent=slope.toFixed(1).replace(/\.0$/,'')+'°';
   el('roofAspectValue').textContent=normal&&slope>1e-7?degrees(exact((Math.atan2(normal[0],normal[1])*180/Math.PI+360)%360)):'—';
   el('fitRoof').hidden=!normal||readonly;
   el('roofFitControl').hidden=!normal||readonly;
   el('tiltBounds').hidden=!normal||readonly;
   el('roofSlopeLine').style.display=normal?'':'none';
   el('tiltDiagram').setAttribute('viewBox',normal?'0 -8 120 148':'0 0 120 108');
   set(azimuth,tilt);
  },setCatalog(items,selected){
   if(items){const signature=JSON.stringify(items.map(item=>[item.id,item.manufacturer,item.material,item.power_w]));if(el('panelModel').dataset.catalog!==signature){el('panelModel').replaceChildren(...items.map(item=>new Option(item.manufacturer+'－'+item.material+'－'+item.power_w+' W',item.id)));el('panelModel').dataset.catalog=signature;}}
   if(selected)el('panelModel').value=selected;
  },setDisabled(value){disabled=value;['panelModel','azimuth','azimuthSelect','fitRoof'].forEach(id=>el(id).disabled=value);['tilt','tiltSelect'].forEach(id=>el(id).disabled=value||!available);['compass','tiltDiagram'].forEach(id=>{const inactive=value||(id==='tiltDiagram'&&!available);el(id).setAttribute('aria-disabled',String(inactive));el(id).setAttribute('tabindex',inactive?'-1':'0');});},setSpec(value){spec=value;el('productModel').textContent=spec.model||'—';el('panelMaterial').textContent=spec.material||'—';el('panelType').textContent=spec.type||'—';el('panelEfficiency').textContent=Number.isFinite(spec.efficiency_pct)?spec.efficiency_pct+'%':'—';el('dataStatus').hidden=spec.data_available!==false;el('dimensions').textContent=`${spec.length_mm} × ${spec.width_mm} × ${spec.thickness_mm} mm`;set(azimuth,tilt);}};
 }
 window.PVPanelControls={create,renderProduct};
})();
