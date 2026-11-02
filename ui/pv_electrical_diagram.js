'use strict';
(function(root){
 const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
 function source(x,y,parallel){
  let s='';for(let i=Math.min(parallel,3)-1;i>=0;i--){const dx=i*4,dy=-i*4;s+=`<rect x="${x-dx}" y="${y+dy}" width="72" height="40" fill="white"/>`;}
  return s+`<path d="M${x+7} ${y+5}L${x+34} ${y+20}L${x+7} ${y+35}Z" fill="none"/>`;
 }
 function render(r,p,spec){
  const rows=[];let nextY=100;
  r.inverters.forEach(inv=>{inv.mppts.forEach(mppt=>{rows.push({inv,mppt,y:nextY});nextY+=105;});nextY+=40;});
  const W=1360,H=Math.max(200,rows[rows.length-1].y+80),centers=[];
  const text=(x,y,value,size=14,anchor='start')=>`<text x="${x}" y="${y}" font-size="${size}" text-anchor="${anchor}" stroke="none" fill="#35434d">${esc(value)}</text>`;
  let svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}"><title>光伏系统单线图</title><rect width="${W}" height="${H}" fill="white"/><g font-family="Microsoft YaHei, sans-serif" stroke="#45515a" stroke-width="1.5" fill="none" stroke-linejoin="round">`;
  svg+=text(30,30,'光伏系统单线图',18)+text(30,52,p.device_name||'逆变器：待选型',12);
  rows.forEach(({inv,mppt,y})=>{
   const par=mppt.strings.length;
   svg+=source(55,y-20,par)+source(240,y-20,par);
   svg+=`<path d="M127 ${y}H240" stroke-dasharray="3 4"/><path d="M312 ${y}H640"/>`;
   svg+=text(58,y+45,`${mppt.series_count} × ${spec.power_w} Wp · ${spec.model}`,13);
   svg+=text(380,y-12,`INV ${inv.id} / MPPT ${mppt.id}`,12)+text(380,y+22,`${par} 串并联 · S${mppt.strings.join(' / S')}`,12);
  });
  r.inverters.forEach(inv=>{
   const first=rows.findIndex(row=>row.inv.id===inv.id),last=first+inv.mppts.length-1,y1=rows[first].y,y2=rows[last].y,mid=(y1+y2)/2,top=y1-32,height=y2-y1+64;
   centers.push(mid);
   svg+=`<rect x="640" y="${top}" width="155" height="${height}" fill="white"/><path d="M640 ${top+height}L795 ${top}"/><path d="M795 ${mid}H843M868 ${mid}H958M843 ${mid}l25 -12"/><circle cx="843" cy="${mid}" r="2.3" fill="white"/><circle cx="868" cy="${mid}" r="2.3" fill="white"/>`;
   svg+=text(655,top+23,'DC',14)+text(777,top+height-10,'AC',14,'end');
   svg+=text(718,top-12,`INV ${inv.id}`,14,'middle')+text(718,top+height+24,`${Number(p.ac_kw).toFixed(1)} kW`,13,'middle')+text(855,mid-22,'QS',11,'middle');
  });
  const y1=centers[0],y2=centers[centers.length-1],mid=(y1+y2)/2;
  svg+=`<path d="M958 ${y1}V${y2}M958 ${mid}H1010M1054 ${mid}H1260" stroke-width="2"/><rect x="1010" y="${mid-24}" width="44" height="48" fill="white"/><path d="M1251 ${mid-5}l9 5-9 5"/>`;
  svg+=text(1032,mid+5,'kWh',13,'middle')+text(1260,mid-16,'电网',14,'end')+text(948,y1-25,'AC',12,'end');
  return svg+'</g></svg>';
 }
 root.PVElectricalDiagram={render};if(typeof module!=='undefined')module.exports=root.PVElectricalDiagram;
})(typeof window!=='undefined'?window:globalThis);
