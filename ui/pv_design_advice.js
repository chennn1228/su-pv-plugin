'use strict';
(function(){
 const el=id=>document.getElementById(id);let context=null,result=null,requested=null;
 document.querySelectorAll('[data-pv-mount]').forEach(node=>{
  const advice='<details class="design-advice"><summary>最优设计参数配置建议</summary><p class="advice-caption">目标：基准年电量 ↑</p><button id="requestAdvice" class="secondary">计算配置建议</button><div id="adviceResult" role="status"></div><button id="applyAdvice" class="secondary" hidden>应用建议角度</button></details>';
  node.innerHTML='<h2 class="section-label">安装支架</h2><div class="mount-field"><label for="clearance">组件最低净空 <span><input id="clearance" type="number" min="100" max="500" step="10" value="100" aria-label="组件最低净空毫米"> mm</span></label><input id="clearanceRange" type="range" min="100" max="500" step="10" value="100"><div class="gap-bounds"><span>100 mm</span><span>500 mm</span></div></div>'+(node.dataset.pvAdvice==='enabled'?advice:'');
 });
 function fail(message){if(el('adviceResult'))el('adviceResult').textContent=message;if(el('requestAdvice'))el('requestAdvice').disabled=false;}
 window.PVDesignAdvice={
  create(options){
   context=options;const number=el('clearance'),range=el('clearanceRange');
   function update(source,commit){if(source.value==='')return;const value=Number(source.value);if(!Number.isFinite(value)||value<100||value>500)return;number.value=range.value=value;window.PVDesignAdvice.invalidate();if(options.onChange)options.onChange(commit);}
   range.addEventListener('input',()=>update(range,false));range.addEventListener('change',()=>update(range,true));
   number.addEventListener('input',()=>update(number,true));number.addEventListener('change',()=>{if(!number.checkValidity())fail('组件最低净空须为100—500 mm。');else update(number,true);});
   el('requestAdvice')?.addEventListener('click',()=>{
    if(!window.sketchup||!window.sketchup.recommend){fail('请从SketchUp中打开。');return;}
    const params=options.params();requested=JSON.stringify(params);result=null;el('applyAdvice').hidden=true;el('requestAdvice').disabled=true;el('adviceResult').textContent='正在比较已有角度…';
    setTimeout(()=>window.sketchup.recommend(JSON.stringify(params)),0);
   });
   el('applyAdvice')?.addEventListener('click',()=>{if(result&&requested===JSON.stringify(options.params()))options.apply(result.settings);});
   return {value:()=>Number(number.value),valid:()=>number.value!==''&&number.checkValidity(),set(value=100){number.value=range.value=value;},disabled(value){number.disabled=range.disabled=value;if(el('requestAdvice'))el('requestAdvice').disabled=value;}};
  },
  invalidate(){result=null;requested=null;if(el('applyAdvice'))el('applyAdvice').hidden=true;if(el('requestAdvice'))el('requestAdvice').disabled=false;if(el('adviceResult'))el('adviceResult').textContent='';},
  receive(data){if(!el('adviceResult')||!context||requested!==JSON.stringify(context.params()))return;result=data;el('requestAdvice').disabled=false;el('applyAdvice').hidden=false;el('adviceResult').title=data.scope;el('adviceResult').textContent=`${Number(data.settings.azimuth.toFixed(2))}° / ${Number(data.settings.tilt.toFixed(2))}° · ${data.count}块 · ${data.annual_kwh.toFixed(2)} kWh/年`;},fail
 };
})();
