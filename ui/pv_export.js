'use strict';
(function(){
 let plan=null,forecast=null;
 const $=id=>document.getElementById(id);
 function objects(){
  if(plan&&window.SuPvSceneShading)return window.SuPvSceneShading.geometry(plan).objects;
  if(!forecast||!forecast.spec)return [];
  const a=forecast.settings.azimuth*Math.PI/180,b=forecast.settings.tilt*Math.PI/180;
  return [{origin:[0,0,0],w:forecast.spec.width_mm,l:forecast.spec.length_mm,
   axes:[[-Math.cos(a),Math.sin(a),0],[-Math.sin(a)*Math.cos(b),-Math.cos(a)*Math.cos(b),Math.sin(b)],[Math.sin(a)*Math.sin(b),Math.cos(a)*Math.sin(b),Math.cos(b)]]}];
 }
 function polygons(){return objects().map(p=>[[0,0],[p.w,0],[p.w,p.l],[0,p.l]].map(([x,y])=>p.origin.map((v,i)=>v+x*p.axes[0][i]+y*p.axes[1][i])));}
 function svg(width=1600,height=1100,annotate=true){
  const polys=polygons();if(!polys.length)throw Error('没有可导出的光伏板。');
  let roof=[];
  if(plan&&!plan.forecast_only&&window.SuPvSceneShading){
   const g=window.SuPvSceneShading.geometry(plan),rings=plan.boundary?[plan.boundary.outer,...plan.boundary.holes]:[[[0,0],[plan.width_mm,0],[plan.width_mm,plan.height_mm],[0,plan.height_mm]]];
   roof=rings.map(ring=>ring.map(([x,y])=>[0,1,2].map(i=>x*plan.frame_axes[0][i]+y*plan.frame_axes[1][i]-g.first[i])));
  }
  const pts=polys.flat().concat(roof.flat());
  const lo=[Math.min(...pts.map(p=>p[0])),Math.min(...pts.map(p=>p[1]))],hi=[Math.max(...pts.map(p=>p[0])),Math.max(...pts.map(p=>p[1]))];
  const padx=annotate?Math.min(75,width*.1):10,pady=annotate?Math.min(85,height*.24):10,scale=Math.min((width-padx*2)/(hi[0]-lo[0]||1),(height-pady*2)/(hi[1]-lo[1]||1));
  const P=p=>[width/2+(p[0]-(hi[0]+lo[0])/2)*scale,height/2-(p[1]-(hi[1]+lo[1])/2)*scale];
  let out=`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" data-cad-scale="${1/scale}" data-cad-origin-x="${(hi[0]+lo[0])/2-width/(2*scale)}" data-cad-origin-y="${(hi[1]+lo[1])/2+height/(2*scale)}"><title>光伏水平俯视图</title><rect width="${width}" height="${height}" fill="white"/><g data-cad-layer="PV_COMPONENT" fill="#b7d3e8" stroke="#2166ac" stroke-width="1">`;
  if(roof.length)out+=`<path data-cad-layer="PV_BOUNDARY" d="${roof.map(ring=>ring.map((p,i)=>(i?'L':'M')+P(p).map(v=>v.toFixed(9)).join(',')).join(' ')+' Z').join(' ')}" fill="#f1f5f8" stroke="#9db1c1" fill-rule="evenodd"/>`;
  polys.forEach(poly=>out+=`<polygon points="${poly.map(p=>P(p).map(v=>v.toFixed(9)).join(',')).join(' ')}"/>`);
  out+='</g>';
  if(annotate)out+=`<g font-family="Microsoft YaHei, sans-serif" fill="#27465e"><text x="20" y="${Math.min(42,height*.15)}" font-size="${Math.min(24,height*.1)}">水平俯视图 · ${polys.length} 块</text><text x="20" y="${height-15}" font-size="${Math.min(18,height*.08)}">${((hi[0]-lo[0])/1000).toFixed(3)} × ${((hi[1]-lo[1])/1000).toFixed(3)} m</text><text x="${width-70}" y="42" font-size="20">N ↑</text><text x="${width-70}" y="68" font-size="16">E →</text></g>`;
  out+='</svg>';
  return out;
 }
 let pendingSvg=false;
 const hasGeometry=()=>plan?plan.count>0:!!(forecast&&forecast.spec);
 function update(){ $('exportSvg').disabled=pendingSvg||!hasGeometry(); }
 function error(message){$('error').hidden=false;$('error').textContent=message;}
 function emitSvg(){
  if(window.sketchup&&window.sketchup.select_export){window.sketchup.select_export('svg');return;}
  if(pendingSvg||!hasGeometry())return;
  try{
   if(!window.sketchup||!window.sketchup.export_figure)throw Error('请在SketchUp插件窗口中导出。');
   const body=svg();pendingSvg=true;update();
   window.sketchup.export_figure(JSON.stringify({format:'svg',body,kind:'plan'}));
  }catch(e){pendingSvg=false;update();error(e.message);}
 }
 $('exportSvg').onclick=emitSvg;
 window.PVExport={svg,exported(){pendingSvg=false;update();},invalidate(){plan=null;forecast=null;pendingSvg=false;update();},
 setPlan(data){plan=data;update();},setForecast(data){forecast=data;update();},selection(data){
  let card=$('selectionOverview');if(!card){card=document.createElement('div');card.id='selectionOverview';document.querySelector('.array-heading').after(card);}
  // Keep selection identification here; model and angles already appear in the sidebar.
  const count=$('forecastCount'),repick=$('forecastReselect');
  if(card.contains(count))document.querySelector('.forecast-header').append(count);
  if(card.contains(repick))document.querySelector('.forecast-header').append(repick);
  card.innerHTML='<div class="selection-map">'+svg(180,100,false)+'</div><div class="selection-meta"><strong>已选光伏</strong></div>';
  card.querySelector('.selection-meta').append(count);card.append(repick);card.hidden=false;

 }};
})();
