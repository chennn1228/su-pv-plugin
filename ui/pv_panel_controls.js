/* Shared model and angle widgets for tool 2 and tool 3. */
'use strict';
(function(){
 const el=id=>document.getElementById(id);
 const angleTemplate="<h2 class=\"section-label\">角度组合</h2><div class=\"angle-grid\">\n        <div class=\"angle-card\"><svg id=\"compass\" viewBox=\"0 0 120 108\" role=\"slider\" tabindex=\"0\" aria-label=\"拖动选择方位角\" aria-valuemin=\"0\" aria-valuemax=\"359\" aria-valuenow=\"180\"><circle cx=\"60\" cy=\"54\" r=\"30\" fill=\"none\" stroke=\"#e0e8ee\"/><path d=\"M60 22V86M28 54H92\" stroke=\"#d4dfe8\"/><path id=\"compassNeedle\" d=\"M60 25L55 57L60 53L65 57Z\" fill=\"#2166ac\"/><circle cx=\"60\" cy=\"54\" r=\"2.5\" fill=\"#2166ac\"/><g fill=\"#617789\" font-size=\"10\" text-anchor=\"middle\"><text x=\"60\" y=\"14\">北 0°</text><text x=\"106\" y=\"58\">东</text><text x=\"60\" y=\"102\">南 180°</text><text x=\"14\" y=\"58\">西</text></g></svg><div class=\"angle-control\"><label for=\"azimuthInput\">方位角</label><div class=\"angle-number\"><input id=\"azimuthInput\" type=\"number\" inputmode=\"numeric\" min=\"0\" max=\"359\" step=\"1\" value=\"180\" aria-label=\"方位角，度\"><span aria-hidden=\"true\">°</span></div><input id=\"azimuth\" type=\"range\" min=\"0\" max=\"359\" step=\"1\" value=\"180\"></div></div>\n        <div class=\"angle-card\"><svg id=\"tiltDiagram\" viewBox=\"0 0 120 108\" role=\"slider\" tabindex=\"0\" aria-label=\"拖动选择倾角\" aria-valuemin=\"0\" aria-valuemax=\"90\" aria-valuenow=\"30\"><path d=\"M14 84H106M22 84V15\" stroke=\"#d4dfe8\" stroke-dasharray=\"3 3\"/><path d=\"M44 84A22 22 0 0 0 22 62\" fill=\"none\" stroke=\"#d4dfe8\"/><line id=\"tiltPanel\" x1=\"22\" y1=\"84\" x2=\"87\" y2=\"46.5\" stroke=\"#2166ac\" stroke-width=\"5\" stroke-linecap=\"round\"/><circle cx=\"22\" cy=\"84\" r=\"3\" fill=\"#2166ac\"/><g fill=\"#617789\" font-size=\"10\"><text x=\"96\" y=\"101\">0°</text><text x=\"27\" y=\"19\">90°</text></g></svg><div class=\"angle-control\"><label for=\"tiltInput\">倾角</label><div class=\"angle-number\"><input id=\"tiltInput\" type=\"number\" inputmode=\"numeric\" min=\"0\" max=\"90\" step=\"1\" value=\"30\" aria-label=\"倾角，度\"><span aria-hidden=\"true\">°</span></div><input id=\"tilt\" type=\"range\" min=\"0\" max=\"90\" step=\"1\" value=\"30\"></div></div>\n      </div>";
 document.querySelectorAll('[data-pv-angles]').forEach(node=>{
  node.innerHTML=angleTemplate;
  const title=node.querySelector('.section-label'),header=document.createElement('div');header.className='angle-heading';
  title.before(header);header.append(title);
  header.insertAdjacentHTML('beforeend','<button id="fitRoof" class="secondary fit-roof" hidden>贴合屋面</button>');
  node.querySelector('#tiltDiagram').insertAdjacentHTML('afterbegin','<line id="roofSlopeLine" x1="22" y1="84" x2="74" y2="84" stroke="#96a4af" stroke-width="2" stroke-dasharray="4 3" style="display:none"/>');
  node.querySelector('#tilt').insertAdjacentHTML('afterend','<span id="tiltBounds" class="angle-range" hidden></span>');
  node.querySelector('label[for="tiltInput"]').firstChild.textContent='板面倾角 ';
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
  node.insertAdjacentHTML('beforeend','<button type="button" id="viewCharacteristics" class="product-characteristics">查看组件电气特性</button>');
 });
 function showCharacteristics(spec){
  if(!window.PVCharacteristics||!spec)return;
  let modal=el('componentCharacteristics');
  if(!modal){
   modal=document.createElement('div');modal.id='componentCharacteristics';modal.className='component-characteristics';modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');modal.setAttribute('aria-label','组件电气特性');
   modal.innerHTML='<section><header><h2 class="section-label" id="componentCurveTitle"></h2><button id="closeCharacteristics" class="secondary" aria-label="关闭组件特性">关闭</button></header><p>STC · 25℃ · 1000 W/m² · 参数拟合</p><div class="component-curve-grid"><div id="componentIV"></div><div id="componentTemperature"></div></div></section>';
   document.body.append(modal);
   el('closeCharacteristics').addEventListener('click',()=>{modal.hidden=true;el('viewCharacteristics').focus();});
   modal.addEventListener('click',event=>{if(event.target===modal)el('closeCharacteristics').click();});
   document.addEventListener('keydown',event=>{if(modal.hidden)return;if(event.key==='Escape'){event.preventDefault();el('closeCharacteristics').click();}else if(event.key==='Tab'){event.preventDefault();el('closeCharacteristics').focus();}});
  }
  modal.hidden=false;el('componentCurveTitle').textContent=spec.manufacturer+' · '+spec.model+' · 电气特性';
  const data=spec.electrical||{};el('componentIV').innerHTML=PVCharacteristics.iv(data);el('componentTemperature').innerHTML=PVCharacteristics.thermal(data);el('closeCharacteristics').focus();
 }
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
  let azimuth=180,tilt=30,spec=null,disabled=false,roofNormal=null,minTilt=0,maxTilt=90,readOnly=false,available=true,azimuthLocked=false;
  const degrees=value=>Number(value.toFixed(3))+'°';
  const exact=value=>Math.abs(value-Math.round(value))<1e-9?Math.round(value):value;
  const hasAzimuth=value=>value>=0&&value<360&&Math.abs(value-Math.round(value))<1e-7;
  const dataAzimuth=value=>((Math.round(value)%360)+360)%360;
  let tiltSteps=[];
  function azimuthLimits(value){
   const fixed=readOnly||azimuthLocked;
   el('azimuth').min=fixed?value:0;el('azimuth').max=fixed?value:359;el('azimuth').step=fixed?'any':'1';
   el('azimuthInput').min=el('azimuth').min;el('azimuthInput').max=el('azimuth').max;el('azimuthInput').step=el('azimuth').step;
   el('azimuthInput').value=value;el('azimuth').value=value;
   ['azimuth','azimuthInput'].forEach(id=>el(id).disabled=disabled||fixed);
   el('compass').setAttribute('aria-valuemin',el('azimuth').min);el('compass').setAttribute('aria-valuemax',el('azimuth').max);
   el('compass').setAttribute('aria-disabled',String(disabled||fixed));el('compass').setAttribute('tabindex',disabled||fixed?'-1':'0');
  }
  function updateFit(){
   const slope=roofNormal?Math.atan2(Math.hypot(roofNormal[0],roofNormal[1]),roofNormal[2])*180/Math.PI:0;
   const bearing=slope<1e-7?azimuth:(Math.atan2(roofNormal[0],roofNormal[1])*180/Math.PI+360)%360;
   const supported=azimuthLocked||!roofNormal||hasAzimuth(bearing);
   el('fitRoof').disabled=disabled||readOnly||!supported;
   el('fitRoof').title=supported?'':'屋面方位角'+degrees(bearing)+'暂无出力数据';
  }
  el('panelModel').addEventListener('change',()=>{if(!disabled&&options.onModelChange)options.onModelChange(el('panelModel').value);});
  el('viewCharacteristics').addEventListener('click',()=>showCharacteristics(spec));
  function updateLimits(a){
   minTilt=0;maxTilt=90;
   if(roofNormal&&!readOnly){
    minTilt=exact(Math.atan2(Math.hypot(roofNormal[0],roofNormal[1]),roofNormal[2])*180/Math.PI);
    const rad=a*Math.PI/180,facing=roofNormal[0]*Math.sin(rad)+roofNormal[1]*Math.cos(rad);
    if(facing < -1e-9)maxTilt=exact(Math.atan2(Math.max(0,roofNormal[2]),-facing)*180/Math.PI);
   }
   available=maxTilt+1e-7>=minTilt;
   const values=[minTilt];if(available){for(let t=0;t<=90;t++)if(t>minTilt+1e-7&&t<=maxTilt+1e-7)values.push(t);if(Math.abs(values[values.length-1]-maxTilt)>1e-7)values.push(maxTilt);}
   tiltSteps=values;
   el('tilt').min=minTilt;el('tilt').max=available?maxTilt:minTilt;el('tilt').step='any';
   el('tiltInput').min=minTilt;el('tiltInput').max=el('tilt').max;el('tiltInput').step='any';
   el('tiltDiagram').setAttribute('aria-valuemin',minTilt);el('tiltDiagram').setAttribute('aria-valuemax',available?maxTilt:minTilt);
   el('tiltBounds').textContent=available?degrees(minTilt)+' — '+degrees(maxTilt):'当前方位无可用倾角';
   ['tilt','tiltInput'].forEach(id=>el(id).disabled=disabled||readOnly||!available);
   el('tiltDiagram').setAttribute('aria-disabled',String(disabled||readOnly||!available));el('tiltDiagram').setAttribute('tabindex',disabled||readOnly||!available?'-1':'0');
  }
  function set(a,t){
   if(azimuthLocked)a=(Math.atan2(roofNormal[0],roofNormal[1])*180/Math.PI+360)%360;
   else if(!readOnly)a=dataAzimuth(a);
   a=exact(a);
   azimuthLimits(a);
   updateLimits(a);t=available?Math.max(minTilt,Math.min(maxTilt,t)):minTilt;
   a=exact(a);t=exact(t);
   azimuth=a;tilt=t;el('azimuth').value=el('azimuthInput').value=a;el('tilt').value=el('tiltInput').value=t;
   el('compassNeedle').setAttribute('transform',`rotate(${a} 60 54)`);
   const rad=t*Math.PI/180;el('tiltPanel').setAttribute('x2',22+75*Math.cos(rad));el('tiltPanel').setAttribute('y2',84-75*Math.sin(rad));
   el('compass').setAttribute('aria-valuenow',a);el('tiltDiagram').setAttribute('aria-valuenow',t);
   if(roofNormal){
    const ar=a*Math.PI/180,section=Math.atan2(roofNormal[0]*Math.sin(ar)+roofNormal[1]*Math.cos(ar),roofNormal[2]);
    el('roofSlopeLine').setAttribute('x2',22+75*Math.cos(section));el('roofSlopeLine').setAttribute('y2',84-75*Math.sin(section));
   }
   updateFit();if(spec)renderProduct(el('panelPreview'),spec,a,t);
  }
  function snapTilt(value){return tiltSteps.reduce((best,item)=>Math.abs(item-value)<Math.abs(best-value)?item:best,tiltSteps[0]);}
  function notify(commit){if(disabled||readOnly)return;set(Number(el('azimuth').value),snapTilt(Number(el('tilt').value)));const handler=commit?options.onCommit:options.onInput;if(handler)handler(azimuth,tilt);}
  el('fitRoof').addEventListener('click',()=>{
   if(disabled||readOnly||!roofNormal||el('fitRoof').disabled)return;
   const slope=exact(Math.atan2(Math.hypot(roofNormal[0],roofNormal[1]),roofNormal[2])*180/Math.PI);
   const bearing=slope<1e-7?azimuth:exact((Math.atan2(roofNormal[0],roofNormal[1])*180/Math.PI+360)%360);
   set(bearing,slope);if(options.onCommit)options.onCommit(azimuth,tilt);
  });
  ['azimuth','tilt'].forEach(name=>{
   el(name).addEventListener('input',()=>notify(false));
   el(name).addEventListener('change',()=>notify(true));
   const input=el(name+'Input');
   input.addEventListener('change',()=>{
    if(input.disabled||disabled||readOnly)return;
    if(!Number.isFinite(input.valueAsNumber)){set(azimuth,tilt);return;}
    el(name).value=Math.max(Number(input.min),Math.min(Number(input.max),input.valueAsNumber));notify(true);
   });
   input.addEventListener('keydown',event=>{
    if(event.key==='Enter'){event.preventDefault();input.blur();}
    if(event.key==='Escape'){event.preventDefault();set(azimuth,tilt);input.blur();}
   });
   input.addEventListener('blur',()=>{if(!Number.isFinite(input.valueAsNumber))set(azimuth,tilt);});
   input.addEventListener('wheel',event=>{if(document.activeElement===input)event.preventDefault();},{passive:false});
  });
  el('tilt').addEventListener('keydown',event=>{
   if(disabled||readOnly||!['ArrowLeft','ArrowDown','ArrowRight','ArrowUp','Home','End'].includes(event.key))return;
   event.preventDefault();const values=tiltSteps;
   const up=['ArrowRight','ArrowUp'].includes(event.key),value=event.key==='Home'?values[0]:event.key==='End'?values[values.length-1]:up?(values.find(v=>v>tilt+1e-7)??values[values.length-1]):([...values].reverse().find(v=>v<tilt-1e-7)??values[0]);
   el('tilt').value=value;notify(true);
  });
  function diagram(id,name,min,max,step,angleAt){
   const svg=el(id);let active=false;
   function update(event){
    const matrix=svg.getScreenCTM();if(!matrix)return;
    const point=svg.createSVGPoint();point.x=event.clientX;point.y=event.clientY;const local=point.matrixTransform(matrix.inverse());
    const lower=Number(el(name).min),upper=Number(el(name).max);
    const snapped=Math.round(angleAt(local)/step)*step;
    const value=name==='azimuth'?((snapped%360)+360)%360:Math.max(lower,Math.min(upper,snapped));
    el(name).value=value;notify(false);
   }
   svg.addEventListener('pointerdown',event=>{if(disabled||readOnly||(name==='azimuth'&&azimuthLocked)||(name==='tilt'&&!available)||event.button!==0)return;active=true;svg.setPointerCapture(event.pointerId);update(event);event.preventDefault();});
   svg.addEventListener('pointermove',event=>{if(active)update(event);});
   svg.addEventListener('pointerup',event=>{if(active){update(event);active=false;notify(true);}});
   svg.addEventListener('pointercancel',()=>{if(active){active=false;notify(true);}});
   svg.addEventListener('keydown',event=>{
    if(disabled||readOnly||(name==='azimuth'&&azimuthLocked)||(name==='tilt'&&!available))return;
    if(!['ArrowLeft','ArrowDown','ArrowRight','ArrowUp','Home','End'].includes(event.key))return;event.preventDefault();
    const lower=Number(el(name).min),upper=Number(el(name).max);
    const old=name==='azimuth'?azimuth:tilt,value=event.key==='Home'?lower:event.key==='End'?upper:Math.max(lower,Math.min(upper,old+(['ArrowRight','ArrowUp'].includes(event.key)?step:-step)));
    el(name).value=value;notify(true);
   });
  }
  diagram('compass','azimuth',0,359,1,p=>(Math.atan2(p.x-60,54-p.y)*180/Math.PI+360)%360);
  diagram('tiltDiagram','tilt',0,90,1,p=>Math.atan2(84-p.y,p.x-22)*180/Math.PI);
  set(azimuth,tilt);
  return {set,setRoof(normal,readonly=false){
   roofNormal=normal||null;readOnly=readonly;
   const slope=normal?Math.atan2(Math.hypot(normal[0],normal[1]),normal[2])*180/Math.PI:0;
   azimuthLocked=!!normal&&!readonly&&slope>1e-7;
   el('fitRoof').hidden=!normal||readonly;
   el('tiltBounds').hidden=!normal||readonly;
   el('roofSlopeLine').style.display=normal?'':'none';
   el('tiltDiagram').setAttribute('viewBox',normal?'0 -8 120 148':'0 0 120 108');
   set(azimuth,tilt);
  },setCatalog(items,selected){
   if(items){const signature=JSON.stringify(items.map(item=>[item.id,item.manufacturer,item.material,item.power_w]));if(el('panelModel').dataset.catalog!==signature){el('panelModel').replaceChildren(...items.map(item=>new Option(item.manufacturer+'－'+item.material+'－'+item.power_w+' W',item.id)));el('panelModel').dataset.catalog=signature;}}
   if(selected)el('panelModel').value=selected;
  },setDisabled(value){disabled=value;el('panelModel').disabled=value;azimuthLimits(azimuth);updateFit();['tilt','tiltInput'].forEach(id=>el(id).disabled=value||readOnly||!available);['compass','tiltDiagram'].forEach(id=>{const inactive=value||readOnly||(id==='compass'?azimuthLocked:!available);el(id).setAttribute('aria-disabled',String(inactive));el(id).setAttribute('tabindex',inactive?'-1':'0');});},setSpec(value){spec=value;el('productModel').textContent=spec.model||'—';el('panelMaterial').textContent=spec.material||'—';el('panelType').textContent=spec.type||'—';el('panelEfficiency').textContent=Number.isFinite(spec.efficiency_pct)?spec.efficiency_pct+'%':'—';el('dataStatus').hidden=spec.data_available!==false;el('dimensions').textContent=`${spec.length_mm} × ${spec.width_mm} × ${spec.thickness_mm} mm`;set(azimuth,tilt);}};
 }
 window.PVPanelControls={create,renderProduct};
})();
