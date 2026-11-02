'use strict';
(function(){
 const el=id=>document.getElementById(id),W=560,H=226,L=46,R=22,T=18,B=38;
 let candidates=[],current=null,total=0,dragging=false,commit=null,automatic=true,dragStart=null;
 const chart=el('seriesChart'),svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
 svg.setAttribute('viewBox',`0 0 ${W} ${H}`);svg.setAttribute('aria-label','每串块数与总串数的可行方案');chart.append(svg);
 const strings=c=>c.string_count;
 function bounds(){const lo=candidates[0].series_count,hi=candidates[candidates.length-1].series_count;return {lo,hi,y:Math.max(1,Math.ceil(total/lo))};}
 function x(n){const b=bounds();return L+(b.hi===b.lo?.5:(n-b.lo)/(b.hi-b.lo))*(W-L-R);}
 function y(m){return H-B-m/bounds().y*(H-T-B);}
 function composition(){
  const sizes=current?.string_sizes||[],lengths=sizes.flatMap(size=>Array(size.string_count).fill(size.series_count)),m=lengths.length;
  el('seriesEquation').classList.toggle('mixed',sizes.length>1);
  el('seriesEquation').innerHTML=current?sizes.map(size=>`<span><small>块 / 串 × 串数</small><strong>${size.series_count} × ${size.string_count}</strong></span>`).join('<b>+</b>'):'<span><small>块 / 串 × 串数</small><strong>—</strong></span>';
  let cells='';
  if(current){
   const n=Math.max(...lengths),scale=Math.min(196/(n*20-4),108/(m*29-4)),height=(m*29-4)*scale,top=(124-height)/2;
   lengths.forEach((length,row)=>{const left=(220-(length*20-4)*scale)/2;for(let col=0;col<length;col++)cells+=`<rect data-row="${row+1}" data-column="${col+1}" x="${left+col*20*scale}" y="${top+row*29*scale}" width="${16*scale}" height="${25*scale}" rx="${scale}" stroke-width="${Math.min(.7,scale)}"/>`;});
   el('seriesMatrix').innerHTML=`<svg viewBox="0 0 220 124" role="img" aria-label="${m}串，共${current.connected_count}块组件"><title>${sizes.map(size=>`${size.series_count}块 × ${size.string_count}串`).join(' + ')}</title><g>${cells}</g></svg>`;
  }else el('seriesMatrix').replaceChildren();
  el('seriesRemainder').innerHTML=current?`<span><b>${current.connected_count}</b> / ${total} 块</span><span>✓ 全部接入</span>`:`<span>${total||'—'} 块已选</span>`;
 }
 function draw(){
  composition();
  el('idealLabel').textContent=total?`m = ${total}/n 参考`:'m = N/n 参考';
  if(!current||!candidates.length){svg.innerHTML=`<path class="series-axis" d="M${L} ${T}V${H-B}H${W-R}"/><text class="series-empty" x="${W/2}" y="${H/2}" text-anchor="middle">${el('seriesMode').textContent==='计算中…'?'校核中…':el('seriesMode').textContent==='校核未通过'?'无可行方案':el('seriesMode').textContent==='计算异常'?'计算异常':'参数待完善'}</text><text x="${W-R}" y="${H-7}" text-anchor="end">每串上限 n 块</text><text x="${L}" y="12">总串数 m</text>`;return;}
  const b=bounds(),grid=[];
  for(let i=0;i<=4;i++){const m=Math.round(b.y*i/4),py=y(m);grid.push(`<path class="series-grid" d="M${L} ${py}H${W-R}"/><text x="${L-9}" y="${py+4}" text-anchor="end">${m}</text>`);}
  const ticks=[...new Set([b.lo,Math.round((b.lo+b.hi)/2),b.hi])];
  ticks.forEach(n=>grid.push(`<text x="${x(n)}" y="${H-B+19}" text-anchor="middle">${n}</text>`));
  const ideal=Array.from({length:81},(_,i)=>{const n=b.lo+(b.hi-b.lo)*i/80;return `${x(n)},${y(total/n)}`;}).join(' ');
  const actual=candidates.map(c=>`${x(c.series_count)},${y(strings(c))}`).join(' '),px=x(current.series_count),py=y(strings(current));
  svg.innerHTML=grid.join('')+`<text x="${L}" y="12">总串数 m</text><text x="${W-R}" y="${H-1}" text-anchor="end">每串上限 n 块</text><polyline class="series-ideal" points="${ideal}"/><polyline class="series-feasible" points="${actual}"/>`+
   candidates.map(c=>`<circle class="series-candidate" cx="${x(c.series_count)}" cy="${y(strings(c))}" r="3"><title>≤${c.series_count}块 / 串 · ${strings(c)}串 · ${c.inverter_count}台逆变器</title></circle>`).join('')+
   `<path class="series-guide" d="M${L} ${py}H${px}V${H-B}"/><circle class="series-halo" cx="${px}" cy="${py}" r="13"/><circle id="seriesHandle" class="series-handle" cx="${px}" cy="${py}" r="7" tabindex="0" role="slider" aria-label="每串组件数上限" aria-valuemin="${b.lo}" aria-valuemax="${b.hi}" aria-valuenow="${current.series_count}" aria-valuetext="每串不超过${current.series_count}块，共${strings(current)}串，全部接入"><title>拖动或用 ← → 选择</title></circle>`;
 }
 function nearest(event){const point=svg.createSVGPoint();point.x=event.clientX;point.y=event.clientY;const local=point.matrixTransform(svg.getScreenCTM().inverse());return candidates.reduce((best,c)=>Math.abs(x(c.series_count)-local.x)<Math.abs(x(best.series_count)-local.x)?c:best,candidates[0]);}
 function preview(candidate){if(current===candidate&&el('seriesMode').textContent==='预选')return;current=candidate;el('seriesMode').textContent='预选';draw();}
 function choose(candidate){current=candidate;automatic=false;el('series_count').value=String(candidate.series_count);el('seriesMode').textContent='计算中…';draw();if(commit)commit();}
 svg.addEventListener('pointerdown',event=>{if(!candidates.length||event.button!==0)return;event.preventDefault();dragStart=current;dragging=true;svg.setPointerCapture(event.pointerId);preview(nearest(event));});
 svg.addEventListener('pointermove',event=>{if(dragging)preview(nearest(event));});
 svg.addEventListener('pointerup',event=>{if(!dragging)return;dragging=false;svg.releasePointerCapture(event.pointerId);choose(nearest(event));});
 svg.addEventListener('pointercancel',()=>{dragging=false;if(dragStart){current=dragStart;el('seriesMode').textContent=automatic?'自动配置':'手动选择';draw();}});
 chart.addEventListener('keydown',event=>{if(!candidates.length||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End'].includes(event.key))return;event.preventDefault();let index=candidates.indexOf(current);index=event.key==='Home'?0:event.key==='End'?candidates.length-1:Math.max(0,Math.min(candidates.length-1,index+(['ArrowLeft','ArrowDown'].includes(event.key)?-1:1)));choose(candidates[index]);el('seriesHandle')?.focus();});
 window.PVStringPlan={
  onSelect(callback){commit=callback;},
  clear(count){total=count||0;candidates=[];current=null;dragging=false;el('seriesMode').textContent='待计算';el('series_count').replaceChildren(new Option('自动配置','0'));draw();},
  pending(){el('seriesMode').textContent='计算中…';if(!current)draw();},
  unavailable(kind){el('seriesMode').textContent=kind==='internal'?'计算异常':'校核未通过';draw();},
  show(data,count,selected){total=count;const merged=new Map(candidates.map(c=>[c.series_count,c]));data.candidates.filter(c=>c.connected_count===count&&c.string_count>0).forEach(c=>merged.set(c.series_count,c));candidates=[...merged.values()].sort((a,b)=>a.series_count-b.series_count);current=candidates.find(c=>c.series_count===data.series_count);automatic=selected===0;el('series_count').replaceChildren(new Option('自动配置','0'),...candidates.map(c=>new Option('≤ '+c.series_count+' 块',String(c.series_count))));el('series_count').value=String(automatic?0:data.series_count);el('seriesMode').textContent=automatic?'自动配置':'手动选择';draw();}
 };
 draw();
})();
