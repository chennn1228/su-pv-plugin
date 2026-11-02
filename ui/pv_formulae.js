'use strict';
(function(){
 const raw=String.raw,math=tex=>'<div class="math-equation">'+PVMath.html(tex)+'</div>',num=(v,n=2)=>Number.isFinite(v)?Number(v).toFixed(n):'—';
 const card=(title,tex,answer='',tag='')=>'<article class="formula-card"><div class="formula-card-heading"><strong>'+title+'</strong>'+(tag?'<span class="formula-tag">'+tag+'</span>':'')+'</div>'+math(tex)+(answer?'<div class="formula-answer">'+answer+'</div>':'')+'</article>';
 function put(kind,cards,symbols,tag=''){
  document.querySelectorAll('[data-formulas="'+kind+'"]').forEach(node=>{node.innerHTML='<div class="pv-formulas-heading"><h2 class="section-label">计算依据</h2>'+(tag?'<span class="formula-tag">'+tag+'</span>':'')+'</div><div class="pv-formula-grid">'+cards.join('')+'</div><div class="formula-symbols">'+symbols.map(s=>'<span>'+s+'</span>').join('')+'</div>';});
 }
 function mount(){
  const host=document.querySelector('[data-pv-mount]');if(!host||!document.getElementById('clearance'))return;
  let node=host.querySelector('.pv-mount-formula');if(!node){node=document.createElement('div');node.className='pv-mount-formula';host.append(node);}
  node.innerHTML=math(raw`h=h_{\min}-\min_j z_j`)+math(raw`100\le h_{\min}\le500\;\mathrm{mm}`);
  node.title='h：沿安装面法向的抬升量；zⱼ：板体角点的法向坐标；范围为本工具可调范围。';
 }
 function layout(d){
  mount();if(!d||d.forecast_only)return;
  const s=d.settings,px=d.projected_width_mm,py=d.projected_height_mm;
  put('layout',[
   card('网格节距',raw`\Delta_x=p_x+g_x,\qquad\Delta_y=p_y+g_y`,math(raw`\Delta_x=${num((px+s.gap_x_mm)/1000)}\,\mathrm m,\quad\Delta_y=${num((py+s.gap_y_mm)/1000)}\,\mathrm m`)),
   card('计数与装机',raw`N=\#\{C_i\subseteq\Omega_{\mathrm{allow}}\},\quad P_{\mathrm{DC}}=\frac{NP_{\mathrm{STC}}}{1000}`,math(raw`N=${d.count},\qquad P_{\mathrm{DC}}=${num(d.capacity_kwp)}\;\mathrm{kWp}`))
  ],['p：板体投影跨度','g：净距','Cᵢ：组件投影','Ωallow：允许区域']);
  const a=s.access||{},edge=(a.edge_mm||0)/1000,hole=(a.hole_mm||0)/1000,width=(a.width_mm||800)/1000;
  put('access',[
   card('边界退让',raw`\begin{aligned}C_i&\subseteq\Omega\\d(C_i,\Gamma_o)&\ge d_o\\d(C_i,\Gamma_h\cup\Gamma_E)&\ge d_h\end{aligned}`,math(raw`d_o=${num(edge)}\,\mathrm m,\qquad d_h=${num(hole)}\,\mathrm m`)),
   card('禁布与通道',raw`\begin{aligned}\operatorname{int}C_i\cap\operatorname{int}E_j&=\varnothing\\d(C_i,\Gamma_{\mathrm{path}})&\ge\frac{w}{2}\end{aligned}`,math(raw`w=${num(width)}\,\mathrm m`)),
   card('网格平移',raw`\max_{\boldsymbol\delta\in\mathcal S}N(\boldsymbol\delta)`,math(raw`N=${d.count}`),'候选搜索'),
   card('检修分区',raw`(c,r)=\left(\left\lfloor\frac{x}{\ell}\right\rfloor,\left\lfloor\frac{y}{\ell}\right\rfloor\right)`,math(raw`\ell=${num((a.span_mm||15000)/1000)}\,\mathrm m`),'中心归区')
  ],['Γo：外边界','Γh：孔洞','ΓE：禁布边界','Γpath：通道中心线','S：候选平移集合','ℓ：分区参数']);
 }
 function forecast(d){
  mount();
  const valid=d&&d.data_available!==false&&Array.isArray(d.values)&&d.values.length===8760;
  const count=d?.export_context?.count||1;
  const cards=[
   card('单板基准',raw`\begin{aligned}G&=G_b+G_d+G_r\\P&=P_{\mathrm{STC}}\frac{G}{G_{\mathrm{STC}}}\bigl[1+\frac{\gamma_P}{100}(T_c-25)\bigr]\end{aligned}`,'','MATLAB · CSV'),
   card('电量汇总',raw`\begin{aligned}E_0(t)&=\sum_{i=1}^{N}e_i(t)\\E_{\mathrm{year}}&=\frac1{1000}\sum_{t=1}^{8760}E(t)\end{aligned}`,valid?math(raw`N=${count},\quad E_{\mathrm{year}}=${num(d.annual_kwh)}\;\mathrm{kWh}`):'—','Wh → kWh')
  ];
  if(d?.method||d?.baseline_values){
   cards.push(card('阴影折减',raw`f_i(t)=1-\frac{A_{\mathrm{sh},i}(t)}{A_i},\qquad E_1(t)=\sum_i e_i(t)f_i(t)`,'','面积近似'));
   cards.push(card('全年减少率',raw`\eta=1-\frac{\sum_tE_1(t)}{\sum_tE_0(t)}`,valid&&Number.isFinite(d.loss_pct)?math(raw`\eta=${num(d.loss_pct)}\%`):''));
  }
  put('forecast',cards,['Gb：直射','Gd：天空散射','Gr：反射','Tc：电池温度','γP：温度系数 / %·℃⁻¹'],d?.method?'面积折减估算':'基准时序');
 }
 function pendingLayout(){document.querySelectorAll('[data-formulas="layout"] .formula-answer,[data-formulas="access"] .formula-answer').forEach(node=>{node.textContent='—';});}
 window.PVFormulae={layout,forecast,mount,pendingLayout};
 document.addEventListener('input',event=>{if(['clearance','clearanceRange'].includes(event.target.id))mount();});
 forecast(null);
})();
