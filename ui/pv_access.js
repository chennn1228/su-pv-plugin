"use strict";
// Canonical coordinates are millimetres in the selected installation plane.
(function(){
 const $=id=>document.getElementById(id),copy=v=>JSON.parse(JSON.stringify(v));
 const defaults=()=>({edge_mm:0,hole_mm:0,width_mm:800,span_mm:15000,automatic:false,entry:null,paths:[],exclusions:[]});
 function create(hooks){
  let data=defaults(),plan=null,mapping=null,enabled=false,locked=false,stage='result';
  const fieldKeys=[['edgeSetback','edge_mm'],['holeSetback','hole_mm'],['accessWidth','width_mm'],['accessSpan','span_mm']];
  const rangeBounds={edgeSetback:[0,5],holeSetback:[0,5],accessWidth:[.01,3],accessSpan:[1,30]};
  function syncRange(id){const bar=$(id+'Range'),value=Number($(id).value),bounds=rangeBounds[id];if(!bar||$(id).value.trim()===''||!Number.isFinite(value)||value<0)return;bar.min=Math.min(bounds[0],value);bar.max=Math.max(bounds[1],value);bar.value=value;}
  function values(){const result=copy(data);fieldKeys.forEach(([id,key])=>result[key]=Number($(id).value)*1000);return result;}
  function valid(){return fieldKeys.every(([id,key])=>$(id).value.trim()!==''&&Number.isFinite(Number($(id).value))&&Number($(id).value)>=0&&Number($(id).value)<=1000&&(!['width_mm','span_mm'].includes(key)||Number($(id).value)>0));}
  function refresh(){
   document.querySelectorAll('[data-access-mode]').forEach(b=>b.disabled=locked||!enabled);
   $('accessAuto').disabled=locked||!enabled||!data.entry;
   $('accessAuto').textContent=data.automatic?'重新预览方案':'预览通道并重排';
   $('accessClear').hidden=!data.paths.length&&!data.automatic;$('accessClear').disabled=locked;
   $('accessEntry').replaceChildren();$('accessExclusions').replaceChildren();
   function item(container,label,remove){const span=document.createElement('span'),button=document.createElement('button');span.textContent=label;button.type='button';button.textContent='×';button.disabled=locked;button.setAttribute('aria-label','删除'+label);button.onclick=()=>{if(locked)return;remove();changed();};span.append(button);$(container).append(span);}
   if(data.entry)item('accessEntry','已选入口',()=>{data.entry=null;data.paths=[];data.automatic=false;});
   data.exclusions.forEach((r,i)=>item('accessExclusions','禁布区'+(i+1),()=>data.exclusions.splice(i,1)));
   if(!data.exclusions.length){const empty=document.createElement('span');empty.className='access-empty';empty.textContent='未设禁布区';$('accessExclusions').append(empty);}
   const legend={setback:Number($('edgeSetback').value)>0||Number($('holeSetback').value)>0,route:data.paths.length>0,excluded:data.exclusions.length>0};
   Object.entries(legend).forEach(([key,active])=>{const node=document.querySelector('.access-legend .'+key);node.classList.toggle('inactive',!active);});
   const size=Number($('accessSpan').value);$('accessPartitionSize').textContent=Number.isFinite(size)?size+' × '+size+' m':'';
   updateStage();
   if(hooks.onEditing)hooks.onEditing(false);hooks.onRedraw();
  }
  function changed(){refresh();hooks.onChange();}
  document.querySelectorAll('[data-access-mode]').forEach(b=>b.onclick=()=>{if(!locked&&enabled&&valid())hooks.onPick(b.dataset.accessMode);});
  fieldKeys.forEach(([id])=>$(id).addEventListener('input',()=>{syncRange(id);changed();}));
  fieldKeys.forEach(([id])=>$(id+'Range').addEventListener('input',()=>{$(id).value=$(id+'Range').value;changed();}));
  $('accessAuto').onclick=()=>{if(locked||!enabled||!data.entry||!valid())return;data.automatic=true;data.paths=[];changed();};
  $('accessClear').onclick=()=>{if(locked)return;data.automatic=false;data.paths=[];changed();};
  $('accessShowZones').onchange=()=>hooks.onRedraw();
  function updateStage(){
   document.querySelectorAll('[data-access-stage],[data-access-result]').forEach(node=>{const active=(node.dataset.accessStage||node.dataset.accessResult)===stage;node.classList.toggle('active',active);node.setAttribute('aria-pressed',String(active));});
   $('accessViewTitle').textContent={zones:'检修分区',route:'入口与通道',result:'排布结果'}[stage];
  }
  function selectStage(value){if(!['zones','route','result'].includes(value))return;stage=value;if(stage==='zones')$('accessShowZones').checked=true;updateStage();hooks.onRedraw();}
  document.querySelectorAll('[data-access-stage],[data-access-result]').forEach(node=>{
   const select=()=>selectStage(node.dataset.accessStage||node.dataset.accessResult);node.addEventListener('click',select);
   if(node.dataset.accessResult)node.addEventListener('keydown',event=>{if(['Enter',' '].includes(event.key)){event.preventDefault();select();}});
  });
  function rings(d){return d.boundary?[d.boundary.outer,...d.boundary.holes]:[[[0,0],[d.width_mm,0],[d.width_mm,d.height_mm],[0,d.height_mm]]];}
  function inside(p,ring){let hit=false;for(let i=0,j=ring.length-1;i<ring.length;j=i++){
   const a=ring[j],b=ring[i];if((a[1]>p[1])!==(b[1]>p[1])&&p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0])hit=!hit;
  }return hit;}
  function roofPoint(p,d,cfg){const r=rings(d);return inside(p,r[0])&&!r.slice(1).some(h=>inside(p,h))&&!cfg.exclusions.some(b=>p[0]>=b[0]&&p[0]<=b[2]&&p[1]>=b[1]&&p[1]<=b[3]);}
  function columnName(n){let name='';for(n++;n>0;n=Math.floor((n-1)/26))name=String.fromCharCode(65+(n-1)%26)+name;return name;}
  function zones(d,cfg){
   let result;
   const trace=d.access_trace;
   if(cfg.automatic&&trace&&trace.zones&&Math.abs(trace.partition_span_mm-cfg.span_mm)<.01)result=copy(trace.zones);
   else{
    const bins=new Map(),fp=d.footprint||[[0,0]],centre=[fp.reduce((n,p)=>n+p[0],0)/fp.length,fp.reduce((n,p)=>n+p[1],0)/fp.length];
    (d.positions||[]).forEach(p=>{const q=[p[0]+centre[0],p[1]+centre[1]],col=Math.max(0,Math.floor(q[0]/cfg.span_mm)),row=Math.max(0,Math.floor(q[1]/cfg.span_mm)),key=col+':'+row;
     if(!bins.has(key))bins.set(key,{column:col,row,target_mm:q});
    });result=[...bins.values()];
   }
   return result.map(z=>{
    const span=cfg.span_mm,x=z.column*span,y=z.row*span,right=Math.min(x+span,d.width_mm),top=Math.min(y+span,d.height_mm),pad=Math.min(span*.10,600);
    const options=[[x+pad,top-pad],[right-pad,top-pad],[x+pad,y+pad],[right-pad,y+pad],z.target_mm];
    return {...z,id:columnName(z.column)+(z.row+1),box:[x,y,right,top],label_mm:options.find(q=>roofPoint(q,d,cfg))||z.target_mm};
   });
  }
  function paint(c,point,d,cfg,mode,showZones,mini=false){
   const boundary=rings(d),partition=zones(d,cfg);
   function polygon(points){points.forEach((p,i)=>{const q=point(...p);i?c.lineTo(...q):c.moveTo(...q);});c.closePath();}
   function rect(b){polygon([[b[0],b[1]],[b[2],b[1]],[b[2],b[3]],[b[0],b[3]]]);}
   function disk(p,r){polygon(Array.from({length:32},(_,i)=>[p[0]+r*Math.cos(i*Math.PI/16),p[1]+r*Math.sin(i*Math.PI/16)]));}
   function capsule(a,b,r){const dx=b[0]-a[0],dy=b[1]-a[1],l=Math.hypot(dx,dy);if(l<1e-8)return;const x=-dy/l*r,y=dx/l*r;polygon([[a[0]+x,a[1]+y],[b[0]+x,b[1]+y],[b[0]-x,b[1]-y],[a[0]-x,a[1]-y]].reverse());disk(a,r);disk(b,r);}
   c.save();c.beginPath();boundary.forEach(polygon);c.clip('evenodd');
   const filledZones=showZones&&mode!=='result';
   if(filledZones)partition.forEach(z=>{c.beginPath();rect(z.box);c.fillStyle=(z.column+z.row)%2?'rgba(136,124,174,.14)':'rgba(136,124,174,.085)';c.fill();});
   const internal=boundary.slice(1).concat(cfg.exclusions.map(b=>[[b[0],b[1]],[b[2],b[1]],[b[2],b[3]],[b[0],b[3]]]));
   [[boundary.slice(0,1),cfg.edge_mm],[internal,cfg.hole_mm]].forEach(([bounds,r])=>{if(r<=0)return;c.beginPath();bounds.forEach(ring=>ring.forEach((a,i)=>capsule(a,ring[(i+1)%ring.length],r)));c.fillStyle='rgba(190,157,95,.26)';c.fill();});
   if(mode!=='zones'){
    c.beginPath();cfg.paths.forEach(line=>line.slice(1).forEach((b,i)=>capsule(line[i],b,cfg.width_mm/2)));c.fillStyle='rgba(74,148,124,.30)';c.fill();
   }
   cfg.exclusions.forEach(b=>{c.beginPath();rect(b);c.fillStyle='rgba(173,106,125,.28)';c.fill();c.strokeStyle='#ad7c8b';c.lineWidth=mini?.7:1;c.setLineDash([4,3]);c.stroke();c.setLineDash([]);});
   if(showZones&&(d.width_mm+d.height_mm)/cfg.span_mm<=200){
    if(filledZones)partition.forEach(z=>{
     // Clip to the zone and roof, then double the stroke width so the
     // visible half lies entirely inside their intersection, including holes.
     c.save();c.beginPath();rect(z.box);c.clip();
     c.beginPath();rect(z.box);boundary.forEach(polygon);
     c.setLineDash(mini?[2,2]:[6,4]);c.strokeStyle='#8a7ca4';c.lineWidth=mini?1.3:2.2;c.stroke();c.restore();
    });
    else{
     c.beginPath();
     for(let x=cfg.span_mm;x<d.width_mm;x+=cfg.span_mm){c.moveTo(...point(x,0));c.lineTo(...point(x,d.height_mm));}
     for(let y=cfg.span_mm;y<d.height_mm;y+=cfg.span_mm){c.moveTo(...point(0,y));c.lineTo(...point(d.width_mm,y));}
     c.setLineDash(mini?[2,2]:[6,4]);c.strokeStyle='rgba(255,255,255,.9)';c.lineWidth=mini?1.5:3;c.stroke();c.strokeStyle='#8a7ca4';c.lineWidth=mini?.7:1.25;c.stroke();c.setLineDash([]);
    }
    partition.forEach(z=>{
     const a=point(z.box[0],z.box[1]),b=point(z.box[2],z.box[3]);if(Math.hypot(b[0]-a[0],b[1]-a[1])<(mini?28:52))return;
     const p=point(...z.label_mm);c.font=(mini?'7px':'10px')+' "Segoe UI","Microsoft YaHei",sans-serif';const width=c.measureText(z.id).width+(mini?4:8),height=mini?10:16;
     c.fillStyle='rgba(255,255,255,.95)';c.fillRect(p[0]-width/2,p[1]-height/2,width,height);c.fillStyle='#78688f';c.textAlign='center';c.textBaseline='middle';c.fillText(z.id,...p);
    });
   }
   c.restore();
   if(mode!=='zones')cfg.paths.forEach(line=>{c.beginPath();line.forEach((p,i)=>{const q=point(...p);i?c.lineTo(...q):c.moveTo(...q);});c.strokeStyle='#3b8a6d';c.lineWidth=mini?1.1:1.5;c.setLineDash(mini?[]:[4,3]);c.stroke();c.setLineDash([]);});
   if(cfg.entry){const p=point(...cfg.entry);c.beginPath();c.arc(...p,mini?2.3:4,0,Math.PI*2);c.fillStyle='#39806a';c.fill();if(!mini){c.fillStyle='#326f5d';c.font='11px "Segoe UI","Microsoft YaHei",sans-serif';c.textAlign='left';c.textBaseline='alphabetic';c.fillText('入口',p[0]+8,p[1]-6);}}
   return partition;
  }
  function draw(c,point,d,canvas){
   if(!enabled)return;const cfg=valid()?values():data,mode=canvas.id==='accessCanvas'?stage:'result',showZones=canvas.id==='accessCanvas'&&$('accessShowZones').checked;
   const partition=paint(c,point,d,cfg,mode,showZones);
   const origin=point(0,0),a=point(1,0),b=point(0,1),u=[a[0]-origin[0],a[1]-origin[1]],v=[b[0]-origin[0],b[1]-origin[1]];
   canvas.dataset.partitionSpan=showZones?cfg.span_mm:'';canvas.dataset.zoneCount=showZones?partition.length:0;canvas.dataset.zoneIds=JSON.stringify(partition.map(z=>z.id));canvas.dataset.stage=mode;
   canvas.dataset.accessMap=JSON.stringify({origin,u,v});canvas.dataset.accessPaths=mode==='zones'?0:cfg.paths.length;canvas.dataset.exclusions=cfg.exclusions.length;canvas.dataset.internalSetback=cfg.hole_mm;
  }
  function drawProcess(){
   if(!plan||!enabled)return;const cfg=valid()?values():data,d=plan;
   const axes=d.frame_axes,project=q=>[axes[0][0]*q[0]+axes[1][0]*q[1]+axes[2][0]*(q[2]||0),-(axes[0][1]*q[0]+axes[1][1]*q[1]+axes[2][1]*(q[2]||0))];
   const boards=(d.positions||[]).map(origin=>(d.unit_corners||[]).slice(0,4).map(p=>project(p.map((x,i)=>x+origin[i]))));
   const outlines=rings(d).map(r=>r.map(project)),all=outlines.flat().concat(boards.flat()),xs=all.map(p=>p[0]),ys=all.map(p=>p[1]),lo=[Math.min(...xs),Math.min(...ys)],hi=[Math.max(...xs),Math.max(...ys)];
   [['accessProcessZones','zones'],['accessProcessRoute','route'],['accessProcessResult','result']].forEach(([id,mode])=>{
    const canvas=$(id),w=canvas.clientWidth,h=canvas.clientHeight;if(!w||!h)return;const ratio=Math.min(2,devicePixelRatio||1);canvas.width=Math.round(w*ratio);canvas.height=Math.round(h*ratio);const c=canvas.getContext('2d');c.setTransform(ratio,0,0,ratio,0,0);c.clearRect(0,0,w,h);
    const scale=Math.max(.000001,Math.min((w-12)/(hi[0]-lo[0]||1),(h-12)/(hi[1]-lo[1]||1))),P=q=>[w/2+(q[0]-(lo[0]+hi[0])/2)*scale,h/2+(q[1]-(lo[1]+hi[1])/2)*scale],point=(x,y)=>P(project([x,y,0]));
    c.beginPath();outlines.forEach(r=>{r.forEach((q,i)=>i?c.lineTo(...P(q)):c.moveTo(...P(q)));c.closePath();});c.fillStyle='#f0f5f9';c.fill('evenodd');c.strokeStyle='#9fb4c5';c.lineWidth=.8;c.stroke();
    if(mode==='result')boards.forEach(board=>{c.beginPath();board.forEach((q,i)=>i?c.lineTo(...P(q)):c.moveTo(...P(q)));c.closePath();c.fillStyle='#bed7eb';c.fill();c.strokeStyle='#6d9bbd';c.lineWidth=.4;c.stroke();});
    const partition=paint(c,point,d,cfg,mode,mode==='zones',true);canvas.dataset.targetId=d.target_id;canvas.dataset.count=d.count;canvas.dataset.zoneCount=partition.length;canvas.dataset.routePaths=mode==='zones'?0:cfg.paths.length;canvas.dataset.outerVertices=outlines[0].length;
   });
   const length=cfg.paths.reduce((sum,line)=>sum+line.slice(1).reduce((n,p,i)=>n+Math.hypot(p[0]-line[i][0],p[1]-line[i][1]),0),0);
   $('accessRouteSummary').textContent=!cfg.entry?'待选入口':!cfg.paths.length?'待生成':(length/1000).toFixed(1)+' m';$('accessResultSummary').textContent=d.count+' 块';
  }
  return {values,valid,draw,drawProcess,get stage(){return stage;},cancel(){},get editing(){return false;},
   setDisabled(value){locked=value;fieldKeys.forEach(([id])=>{$(id).disabled=value;const bar=$(id+'Range');if(bar)bar.disabled=value;});refresh();},
   setPlan(d){if(!plan||plan.target_id!==d.target_id)stage='result';plan=d;enabled=!!d.access_enabled&&!d.forecast_only;data={...defaults(),...copy(d.settings.access||{})};
    fieldKeys.forEach(([id,key])=>{$(id).value=Number((data[key]/1000).toFixed(6));syncRange(id);});
    const errors=d.access_validation&&!d.access_validation.valid?d.access_validation.errors:[];
    $('accessStatus').textContent=errors.join(' ');$('accessStatus').classList.toggle('invalid',errors.length>0);
    $('accessAvailable').textContent=d.access_baseline_count??(d.count+(d.access_removed_count||0));$('accessRetained').textContent=d.count;$('accessRemoved').textContent=d.access_removed_count||0;
    const centred=d.layout_search?d.layout_search.centred_count:d.count;
    $('accessCentred').textContent=centred;$('accessGain').textContent=d.count-centred;refresh();
   },setVisible(show){$('accessWorkspace').hidden=!show||!enabled;}
  };
 }
 window.PVAccess={create};
})();
