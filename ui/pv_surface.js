'use strict';
// Offline WebGL surface. No CDN or external JavaScript dependencies.
(function () {
  const el = id => document.getElementById(id);
  const arrayMode = document.body.dataset.pvMode === 'array';
  const chartSection = document.querySelector(arrayMode ? '.array-power' : '.chart-section');
  const state = { values:null, peak:1, azimuth:180, tilt:30, request:0, yaw:-0.62,
    elevation:0.82, zoom:0.44, pendingFrame:false, vertices:null, indices:null,
    hourStart:0, hourEnd:23, hourCount:24, period:'daily', view:'surface', monthly:null, totals:null,
    displayValues:null, rowCount:365, meshStride:24, reference:null, referenceMonthly:null, referenceTotals:null, displayReference:null,
    exportSnapshot:null, exportPending:false };
  const hourHalf=1.65; // 拉长小时方向；全年天数方向保持原比例。
  const daysInMonth = [31,28,31,30,31,30,31,31,30,31,30,31];
  const monthStarts = [0];
  daysInMonth.forEach((days, i) => monthStarts.push(monthStarts[i] + days));
  const canvas = el('surface'), overlay = el('labels'), plot = el('plot');
  const ctx = overlay.getContext('2d');
  const gl = canvas.getContext('webgl', {antialias:true, alpha:true}) || canvas.getContext('experimental-webgl');
  let fallback = null, program, locations, vertexBuffer, indexBuffer, lineBuffer, gridCount;
  const colors = [[24,62,183],[17,168,196],[129,212,79],[255,211,77],[227,75,40]];

  function color(value) {
    const t = Math.max(0, Math.min(1, value)) * 4;
    const i = Math.min(3, Math.floor(t)), f = t - i;
    return colors[i].map((v, k) => v + (colors[i+1][k] - v) * f);
  }
  function shader(type, source) {
    const s = gl.createShader(type); gl.shaderSource(s, source); gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }
  function initGL() {
    const vs = shader(gl.VERTEX_SHADER, `attribute vec4 aVertex; uniform vec4 uView;
      uniform float uZoom; uniform float uAspect; varying float vValue;
      void main(){ float x=uView.x*aVertex.x-uView.y*aVertex.y;
        float y=uView.y*aVertex.x+uView.x*aVertex.y; float z=aVertex.z-0.55;
        gl_Position=vec4(x*uZoom/uAspect,(uView.z*y+uView.w*z)*uZoom,(uView.w*y-uView.z*z)*0.18,1.0);
        vValue=aVertex.w; }`);
    const fs = shader(gl.FRAGMENT_SHADER, `precision mediump float; varying float vValue;
      uniform float uSolid; uniform vec4 uColor; uniform float uOpacity;
      vec3 heat(float t){ t=clamp(t,0.0,1.0)*4.0;
        vec3 a=vec3(24.0,62.0,183.0)/255.0; vec3 b=vec3(17.0,168.0,196.0)/255.0;
        vec3 c=vec3(129.0,212.0,79.0)/255.0; vec3 d=vec3(255.0,211.0,77.0)/255.0;
        vec3 e=vec3(227.0,75.0,40.0)/255.0;
        if(t<1.0)return mix(a,b,t);if(t<2.0)return mix(b,c,t-1.0);
        if(t<3.0)return mix(c,d,t-2.0);return mix(d,e,t-3.0); }
      void main(){gl_FragColor=uSolid>0.5?uColor:vec4(heat(vValue),uOpacity);}`);
    program = gl.createProgram(); gl.attachShader(program, vs); gl.attachShader(program, fs); gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
    locations = {};
    ['uView','uZoom','uAspect','uSolid','uColor','uOpacity'].forEach(name => locations[name] = gl.getUniformLocation(program,name));
    locations.vertex = gl.getAttribLocation(program,'aVertex');
    vertexBuffer=gl.createBuffer(); indexBuffer=gl.createBuffer(); lineBuffer=gl.createBuffer();
    gl.enable(gl.DEPTH_TEST); gl.depthFunc(gl.LEQUAL);
  }
  function hourY(hour){return (hour-state.hourStart)/(state.hourEnd-state.hourStart)*hourHalf*2-hourHalf;}
  function hourTicks(){
    const ticks=[state.hourStart];
    for(let h=state.hourStart+1;h<state.hourEnd;h++)if(h%2===0)ticks.push(h);
    if(ticks[ticks.length-1]!==state.hourEnd)ticks.push(state.hourEnd);
    return ticks;
  }
  function buildGrid(){
    const lines = [];
    function line(a,b){lines.push(...a,0,...b,0);}
    monthStarts.slice(0,12).forEach(d=>{ const x=rowX(monthRow(monthStarts.indexOf(d))); line([x,-hourHalf,0],[x,hourHalf,0]); });
    hourTicks().forEach(h=>{const y=hourY(h);line([-1.6,y,0],[1.6,y,0]);});
    line([-1.6,-hourHalf,0],[1.6,-hourHalf,0]);line([-1.6,-hourHalf,0],[-1.6,hourHalf,0]);
    line([-1.6,-hourHalf,0],[-1.6,-hourHalf,1.4]);
    gridCount=lines.length/4;
    gl.bindBuffer(gl.ARRAY_BUFFER,lineBuffer); gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(lines),gl.STATIC_DRAW);
  }
  try { if(gl) initGL(); else fallback=canvas.getContext('2d'); }
  catch(error){ el('empty').textContent='三维渲染初始化失败：'+error.message; }

  function drawProduct(spec){state.spec=spec;angleControls.setSpec(spec);}
  function aggregate(){
    function sums(values){
      const monthly=new Array(288).fill(0),totals=new Array(12).fill(0);
      for(let m=0;m<12;m++)for(let d=monthStarts[m];d<monthStarts[m+1];d++)for(let h=0;h<24;h++){
        const v=values[d*24+h];monthly[m*24+h]+=v/daysInMonth[m];totals[m]+=v/1000;
      }
      return [monthly,totals];
    }
    [state.monthly,state.totals]=sums(state.values);
    [state.referenceMonthly,state.referenceTotals]=state.reference?sums(state.reference):[null,null];
  }
  function rowX(row){return row/(state.rowCount-1)*3.2-1.6;}
  function monthRow(m){return state.period==='monthly'?m:monthStarts[m];}
  function buildMesh() {
    state.displayValues=state.period==='monthly'?state.monthly:state.values;
    state.displayReference=state.reference?(state.period==='monthly'?state.referenceMonthly:state.reference):null;
    state.rowCount=state.period==='monthly'?12:365;
    const maximum=Math.max(...state.displayValues);state.colorPeak=maximum||1;
    state.peak=Math.max(maximum,state.displayReference?Math.max(...state.displayReference):0)||1;
    el('legendMax').textContent=maximum.toFixed(2)+' W';
    el('surfaceCaption').textContent=state.period==='monthly'?'12个月 · 独立切片':'365天 × 24小时';
    // 找全年任意一天出现正值的小时包络，只裁掉两端所有天均为0的时段。
    let first=24,last=-1;
    for(let h=0;h<24;h++)for(let d=0;d<state.rowCount;d++)if(state.displayValues[d*24+h]>0||(state.displayReference&&state.displayReference[d*24+h]>0)){first=Math.min(first,h);last=Math.max(last,h);break;}
    state.hourStart=last<0?0:Math.max(0,first-1);
    state.hourEnd=last<0?23:Math.min(23,last+1);
    state.naturalStart=state.hourStart;state.naturalEnd=state.hourEnd;
    const selectedHour=Number(el('hour').value);state.hourStart=Math.min(state.hourStart,selectedHour);state.hourEnd=Math.max(state.hourEnd,selectedHour);
    state.hourCount=state.hourEnd-state.hourStart+1;
    const count=state.hourCount;
    state.meshStride=count;
    plot.dataset.hourStart=state.hourStart;plot.dataset.hourEnd=state.hourEnd;plot.dataset.visibleHours=state.hourCount;plot.dataset.period=state.period;plot.dataset.rows=state.rowCount;plot.dataset.peak=maximum;plot.dataset.axisPeak=state.peak;plot.dataset.comparison=String(!!state.displayReference);
    // Each month is a vertical curtain: top and baseline pairs, never connected across months.
    const slices=state.period==='monthly';state.meshStride=count*(slices?2:1);
    const vertices = new Float32Array(state.rowCount*state.meshStride*4);
    const indices = new Uint16Array((slices?12:364)*(count-1)*6);
    let k=0;
    for(let d=0;d<state.rowCount;d++)for(let j=0;j<count;j++){
      const h=state.hourStart+j,i=d*state.meshStride+j*(slices?2:1),q=state.displayValues[d*24+h]/state.peak;
      vertices.set([rowX(d),hourY(h),q*1.4,state.displayValues[d*24+h]/state.colorPeak],i*4);
      if(slices){
        vertices.set([rowX(d),hourY(h),0,0],(i+1)*4);
        if(j<count-1){indices.set([i,i+1,i+2,i+2,i+1,i+3],k);k+=6;}
      }else if(d<364&&j<count-1){indices.set([i,i+count,i+1,i+1,i+count,i+count+1],k);k+=6;}
    }
    plot.dataset.triangles=indices.length/3;plot.dataset.geometry=slices?'slices':'surface';
    state.vertices=vertices; state.indices=indices;
    if(gl&&program){
      gl.bindBuffer(gl.ARRAY_BUFFER,vertexBuffer); gl.bufferData(gl.ARRAY_BUFFER,vertices,gl.STATIC_DRAW);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,indices,gl.STATIC_DRAW);
      buildGrid();
    }
  }
  function project(x,y,z){
    const co=Math.cos(state.yaw),si=Math.sin(state.yaw),se=Math.sin(state.elevation),ce=Math.cos(state.elevation);
    const rx=co*x-si*y, ry=si*x+co*y, rz=z-0.55;
    return {x:(rx*state.zoom/(plot.clientWidth/plot.clientHeight)+1)*plot.clientWidth/2,
      y:(1-(se*ry+ce*rz)*state.zoom)*plot.clientHeight/2, depth:ce*ry-se*rz};
  }
  function vertexProjection(index){const a=state.vertices;return project(a[index*4],a[index*4+1],a[index*4+2]);}
  function drawGL(){
    gl.viewport(0,0,canvas.width,canvas.height);gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
    gl.useProgram(program);
    gl.uniform4f(locations.uView,Math.cos(state.yaw),Math.sin(state.yaw),Math.sin(state.elevation),Math.cos(state.elevation));
    gl.uniform1f(locations.uZoom,state.zoom);gl.uniform1f(locations.uAspect,plot.clientWidth/plot.clientHeight);
    gl.bindBuffer(gl.ARRAY_BUFFER,vertexBuffer);gl.enableVertexAttribArray(locations.vertex);
    gl.vertexAttribPointer(locations.vertex,4,gl.FLOAT,false,16,0);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer);gl.uniform1f(locations.uSolid,0);
    gl.enable(gl.POLYGON_OFFSET_FILL);gl.polygonOffset(1,1);
    gl.uniform1f(locations.uOpacity,1);
    if(state.period==='monthly'){
      const selected=Number(el('month').value)-1,perMonth=(state.hourCount-1)*6;
      gl.drawElements(gl.TRIANGLES,perMonth,gl.UNSIGNED_SHORT,selected*perMonth*2);
      gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.depthMask(false);
      gl.uniform1f(locations.uOpacity,.5);
      const order=Array.from({length:12},(_,m)=>m).filter(m=>m!==selected).sort((a,b)=>project(rowX(b),0,0).depth-project(rowX(a),0,0).depth);
      order.forEach(m=>gl.drawElements(gl.TRIANGLES,perMonth,gl.UNSIGNED_SHORT,m*perMonth*2));
      gl.depthMask(true);gl.disable(gl.BLEND);gl.uniform1f(locations.uOpacity,1);
    }else gl.drawElements(gl.TRIANGLES,state.indices.length,gl.UNSIGNED_SHORT,0);
    gl.disable(gl.POLYGON_OFFSET_FILL);
    gl.bindBuffer(gl.ARRAY_BUFFER,lineBuffer);gl.vertexAttribPointer(locations.vertex,4,gl.FLOAT,false,16,0);
    gl.uniform1f(locations.uSolid,1);gl.uniform4f(locations.uColor,0.44,0.53,0.61,1);
    gl.drawArrays(gl.LINES,0,gridCount);
  }
  function drawFallback(){
    const ratio=window.devicePixelRatio||1;fallback.setTransform(ratio,0,0,ratio,0,0);
    fallback.clearRect(0,0,plot.clientWidth,plot.clientHeight);
    const points=Array.from({length:state.rowCount*state.meshStride},(_,i)=>vertexProjection(i)),triangles=[];
    for(let i=0;i<state.indices.length;i+=3){const ids=Array.from(state.indices.slice(i,i+3));
      triangles.push({ids,depth:ids.reduce((s,id)=>s+points[id].depth,0)});}
    triangles.sort((a,b)=>b.depth-a.depth).forEach(triangle=>{
      const ids=triangle.ids,c=color(ids.reduce((s,id)=>s+state.vertices[id*4+3],0)/3);
      fallback.beginPath();ids.forEach((id,i)=>{const p=points[id];if(i===0)fallback.moveTo(p.x,p.y);else fallback.lineTo(p.x,p.y);});
      const month=Math.floor(ids[0]/state.meshStride),opacity=state.period==='monthly'&&month!==Number(el('month').value)-1?.5:1;
      fallback.closePath();fallback.fillStyle=`rgba(${c.map(Math.round).join(',')},${opacity})`;fallback.fill();
      fallback.strokeStyle=fallback.fillStyle;fallback.lineWidth=.6;fallback.stroke();
    });
  }
  function selectedIndex(){return (monthStarts[Number(el('month').value)-1]+Number(el('day').value)-1)*24+Number(el('hour').value);}
  function seriesKey(c,width){
    if(!state.reference)return;
    c.save();c.font='11px "Segoe UI","Microsoft YaHei",sans-serif';c.textAlign='left';
    const x=Math.max(150,width-205),y=23;
    c.beginPath();c.moveTo(x,y-4);c.lineTo(x+20,y-4);c.strokeStyle='#2166ac';c.lineWidth=2.6;c.stroke();c.fillStyle='#2166ac';c.fillText('遮挡折减',x+26,y);
    c.setLineDash([4,3]);c.beginPath();c.moveTo(x+105,y-4);c.lineTo(x+125,y-4);c.strokeStyle='rgba(111,132,151,.6)';c.lineWidth=1.2;c.stroke();c.fillStyle='#8b9eae';c.fillText('原始预测',x+131,y);c.restore();
  }
  function referenceProfiles(c){
    if(!state.displayReference)return;
    const selected=state.period==='monthly'?Number(el('month').value)-1:Math.floor(selectedIndex()/24);
    const rows=state.period==='monthly'?Array.from({length:12},(_,i)=>i):Array.from(new Set([...Array.from({length:27},(_,i)=>Math.min(364,i*14)),364,selected]));
    c.save();
    rows.forEach(row=>{
      c.beginPath();for(let h=state.hourStart;h<=state.hourEnd;h++){
        const p=project(rowX(row),hourY(h),state.displayReference[row*24+h]/state.peak*1.4);
        if(h===state.hourStart)c.moveTo(p.x,p.y);else c.lineTo(p.x,p.y);
      }
      c.setLineDash(row===selected?[4,3]:[]);c.lineWidth=row===selected?1.2:.65;
      c.strokeStyle=row===selected?'rgba(111,132,151,.6)':'rgba(125,145,163,.23)';c.stroke();
    });
    c.restore();
  }
  function labels(){
    const ratio=window.devicePixelRatio||1;ctx.setTransform(ratio,0,0,ratio,0,0);ctx.clearRect(0,0,plot.clientWidth,plot.clientHeight);
    ctx.font='11px "Segoe UI","Microsoft YaHei",sans-serif';ctx.fillStyle='#486175';ctx.textAlign='center';
    const label=(text,x,y,z,dx=0,dy=0)=>{const p=project(x,y,z);ctx.fillText(text,p.x+dx,p.y+dy);};
    monthStarts.slice(0,12).forEach((d,i)=>label((i+1)+'月',rowX(monthRow(i)),-hourHalf-.13,0,0,8));
    let previous=null;
    hourTicks().forEach(h=>{const p=project(-1.74,hourY(h),0);
      if(!previous||Math.hypot(p.x-previous.x,p.y-previous.y)>=24){label(h+'时',-1.74,hourY(h),0,-5,0);previous=p;}});
    [0,.25,.5,.75,1].forEach(q=>label((state.peak*q).toFixed(0),-1.69,-hourHalf-.07,q*1.4,q===0?-32:-18,0));
    label(state.period==='monthly'?'月份':'天 / 月份',.1,-hourHalf-.27,0,0,16);label('小时',-2.05,0,0,-30,20);
    ctx.textAlign='left';ctx.fillText('平均出力 / W',18,25);ctx.textAlign='center';
    referenceProfiles(ctx);seriesKey(ctx,plot.clientWidth);
    const hour=Number(el('hour').value),monthly=state.period==='monthly';
    const index=selectedIndex(),day=monthly?Number(el('month').value)-1:Math.floor(index/24),step=monthly?2:1;
    plot.dataset.selectedRow=day;plot.dataset.focus=monthly?'fade-months':'day-profile';
    if(monthly){
      // Keep all twelve profiles readable while their fills are faded.
      for(let m=0;m<12;m++){
        ctx.beginPath();for(let j=0;j<state.hourCount;j++){
          const point=vertexProjection(m*state.meshStride+j*2);
          if(j===0)ctx.moveTo(point.x,point.y);else ctx.lineTo(point.x,point.y);
        }
        ctx.strokeStyle=m===day?'rgba(24,51,71,.85)':'rgba(55,82,106,.55)';
        ctx.lineWidth=m===day?.9:.65;ctx.stroke();
      }
    }
    if(!monthly){
      ctx.beginPath();for(let j=0;j<state.hourCount;j++){const point=vertexProjection(day*state.meshStride+j);if(j===0)ctx.moveTo(point.x,point.y);else ctx.lineTo(point.x,point.y);}
      ctx.strokeStyle='rgba(24,51,71,.82)';ctx.lineWidth=.85;ctx.stroke();
    }
    // Also annotate cropped night hours at their actual 0W position on the full hour coordinate.
    const value=state.displayValues[day*24+hour],p=project(rowX(day),hourY(hour),value/state.peak*1.4),base=project(rowX(day),hourY(hour),0);
    if(!monthly){
      ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineTo(base.x,base.y);ctx.setLineDash([2,3]);ctx.strokeStyle='rgba(24,51,71,.65)';ctx.lineWidth=.65;ctx.stroke();ctx.setLineDash([]);
      const text=value.toFixed(2)+' W',width=ctx.measureText(text).width+12;
      const x=Math.max(8,Math.min(plot.clientWidth-width-8,p.x+9)),y=Math.max(16,Math.min(plot.clientHeight-14,p.y-12));
      ctx.fillStyle='rgba(255,255,255,.94)';ctx.fillRect(x-4,y-12,width,19);ctx.fillStyle='#183347';ctx.textAlign='left';ctx.fillText(text,x+2,y+1);ctx.textAlign='center';
    }
    ctx.beginPath();ctx.arc(p.x,p.y,3.5,0,Math.PI*2);ctx.fillStyle='#fff';ctx.fill();ctx.strokeStyle='#245a8e';ctx.lineWidth=1.4;ctx.stroke();
    plot.dataset.annotatedPower=value.toFixed(2);
  }

  function render(){
    state.pendingFrame=false;
    if(!state.values)return;
    if(state.view!=='surface'){drawChart();return;}
    const ratio=Math.min(2,window.devicePixelRatio||1),w=Math.max(1,Math.round(plot.clientWidth*ratio)),h=Math.max(1,Math.round(plot.clientHeight*ratio));
    if(canvas.width!==w||canvas.height!==h){canvas.width=overlay.width=w;canvas.height=overlay.height=h;}
    if(!state.values)return;
    if(state.view==='surface'){if(gl&&program)drawGL();else if(fallback)drawFallback();labels();}
    else drawChart();
  }
  function drawChart(){
    const target=el('lineChart'),box=el('linePlot'),ratio=Math.min(2,window.devicePixelRatio||1);
    const w=box.clientWidth,h=box.clientHeight;
    target.width=Math.max(1,Math.round(w*ratio));target.height=Math.max(1,Math.round(h*ratio));
    const c=target.getContext('2d');c.setTransform(ratio,0,0,ratio,0,0);c.clearRect(0,0,w,h);
    const m=Number(el('month').value)-1,d=Number(el('day').value),hour=Number(el('hour').value),daily=state.view==='day';
    const mean=daily&&state.period==='monthly';
    const values=daily?(mean?state.monthly.slice(m*24,(m+1)*24):state.values.slice((monthStarts[m]+d-1)*24,(monthStarts[m]+d)*24)):state.totals;
    const reference=state.reference?(daily?(mean?state.referenceMonthly.slice(m*24,(m+1)*24):state.reference.slice((monthStarts[m]+d-1)*24,(monthStarts[m]+d)*24)):state.referenceTotals):null;
    const max=Math.max(...values),axisMax=Math.max(max,reference?Math.max(...reference):0),top=axisMax>0?axisMax*1.12:1,L=68,R=w-32,T=35,B=h-45;
    const x=i=>daily?L+(i+.5)/24*(R-L):L+i/11*(R-L),y=v=>B-v/top*(B-T);
    c.font='12px "Segoe UI","Microsoft YaHei",sans-serif';c.lineWidth=1;c.textAlign='right';
    for(let i=0;i<=4;i++){const v=top*i/4,py=y(v);c.strokeStyle='#e3eaf0';c.beginPath();c.moveTo(L,py);c.lineTo(R,py);c.stroke();c.fillStyle='#617789';c.fillText(v.toFixed(daily?0:1),L-12,py+4);}
    c.textAlign='left';c.fillText(daily?'平均出力 / W':'电量 / kWh',L,T-18);c.textAlign='center';
    if(daily){for(let t=0;t<=24;t+=3)c.fillText(t+':00',L+t/24*(R-L),B+25);}
    else values.forEach((v,i)=>c.fillText((i+1)+'月',x(i),B+25));
    if(reference){
      c.beginPath();reference.forEach((v,i)=>i===0?c.moveTo(x(i),y(v)):c.lineTo(x(i),y(v)));
      c.strokeStyle='rgba(111,132,151,.48)';c.lineWidth=1.3;c.setLineDash([5,4]);c.stroke();c.setLineDash([]);
    }
    c.beginPath();values.forEach((v,i)=>{if(i===0)c.moveTo(x(i),y(v));else c.lineTo(x(i),y(v));});
    c.lineTo(x(values.length-1),B);c.lineTo(x(0),B);c.closePath();c.fillStyle='rgba(33,102,172,.08)';c.fill();
    c.beginPath();values.forEach((v,i)=>{if(i===0)c.moveTo(x(i),y(v));else c.lineTo(x(i),y(v));});c.strokeStyle='#2166ac';c.lineWidth=2.6;c.stroke();
    const selected=daily?hour:m;
    values.forEach((v,i)=>{c.beginPath();c.arc(x(i),y(v),i===selected?5:3,0,Math.PI*2);c.fillStyle=i===selected?'#164d84':'#2166ac';c.fill();});
    el('chartSummary').textContent=daily?(mean?`${m+1}月 · 月平均逐时`:`${m+1}月${d}日`):'全年月度电量';
    el('energyLabel').textContent=daily?(mean?'日均电量':'日电量'):'全年电量';
    el('chartEnergy').textContent=(daily?values.reduce((s,v)=>s+v,0)/1000:state.totals.reduce((s,v)=>s+v,0)).toFixed(daily?3:2);
    el('peakLabel').textContent=daily?'小时峰值':`${m+1}月电量`;
    el('chartPeak').textContent=(daily?max:state.totals[m]).toFixed(2);
    el('chartPeakUnit').textContent=daily?'W':'kWh';
    target.dataset.values=JSON.stringify(values);target.dataset.total=values.reduce((s,v)=>s+v,0);target.dataset.selected=selected;
    if(reference)target.dataset.referenceValues=JSON.stringify(reference);else delete target.dataset.referenceValues;
    target.dataset.axisMax=axisMax;seriesKey(c,w);
  }
  el('lineChart').addEventListener('click',event=>{
    if(!state.values)return;
    const rect=event.currentTarget.getBoundingClientRect(),fraction=Math.max(0,Math.min(1,(event.clientX-rect.left-68)/(rect.width-100)));
    if(state.view==='day')el('hour').value=Math.min(23,Math.floor(fraction*24));
    else {el('month').value=Math.round(fraction*11)+1;fillDays();}
    queryPoint();
  });
  function requestRender(){if(!state.pendingFrame){state.pendingFrame=true;requestAnimationFrame(render);}}
  function syncAngles(a,t){state.azimuth=a;state.tilt=t;angleControls.set(a,t);}
  function queryPoint(){
    const m=Number(el('month').value),d=Number(el('day').value),h=Number(el('hour').value);
    const mean=state.period==='monthly'&&state.view!=='month';
    const hourLabel=`${String(h).padStart(2,'0')}:00—${String(h+1).padStart(2,'0')}:00`;
    el('monthValue').textContent=m+'月';el('dayValue').textContent=d+'日';el('hourValue').textContent=hourLabel;
    el('day').disabled=mean||state.view==='month';el('hour').disabled=state.view==='month';
    el('dayControl').classList.toggle('inactive',el('day').disabled);
    el('pointDate').textContent=state.view==='month'?`${m}月总电量`:`${m}月${mean?'平均':d+'日'} · ${hourLabel}`;
    el('pointUnit').textContent=state.view==='month'?'kWh':'W';
    if(!state.values)return;
    if(state.hourStart!==Math.min(state.naturalStart,h)||state.hourEnd!==Math.max(state.naturalEnd,h))buildMesh();
    const value=state.view==='month'?state.totals[m-1]:(mean?state.monthly[(m-1)*24+h]:state.values[selectedIndex()]);
    el('pointPower').textContent=value.toFixed(2);requestRender();
    if(arrayMode)window.dispatchEvent(new CustomEvent('pv-time-query',{detail:{index:selectedIndex(),view:state.view,period:state.period}}));
  }
  function fillDays(){const old=Number(el('day').value)||1,days=daysInMonth[Number(el('month').value)-1];
    el('day').max=days;el('day').value=Math.min(old,days);queryPoint();}
  function sendAngles(){
    invalidateExport();
    if(!window.sketchup){PV.fail('请从SketchUp的“变电站光伏”工具栏打开。');return;}
    el('place').disabled=true;el('error').hidden=true;
    state.request++;window.sketchup.angles(JSON.stringify({azimuth:state.azimuth,tilt:state.tilt,model_id:el('panelModel').value,request_id:state.request}));
  }
  function clearOutput(message){
    invalidateExport();
    state.values=null;state.monthly=null;state.totals=null;state.displayValues=null;state.reference=null;state.referenceMonthly=null;state.referenceTotals=null;state.displayReference=null;
    ['annual','peak','pointPower','chartEnergy','chartPeak','legendMax'].forEach(id=>el(id).textContent='—');
    ['peak','rows','dayProfile','queryPower'].forEach(key=>delete plot.dataset[key]);
    el('lineChart').removeAttribute('data-values');el('lineChart').removeAttribute('data-total');
    delete el('lineChart').dataset.referenceValues;plot.dataset.comparison='false';
    chartSection.classList.add('no-data');
    el('missingData').hidden=false;el('missingData').textContent=message;
  }
  function updateExport(){
    el('exportCsv').disabled=!state.exportSnapshot||state.exportPending;
    el('exportCsv').textContent=state.exportPending?'正在导出…':'导出全年 CSV';
  }
  function invalidateExport(){state.exportSnapshot=null;updateExport();}
  el('exportCsv').addEventListener('click',()=>{
    if(!state.exportSnapshot||state.exportPending||!window.sketchup||!window.sketchup.export_csv)return;
    state.exportPending=true;updateExport();
    window.sketchup.export_csv(JSON.stringify(state.exportSnapshot));
  });
  window.PV={
    exported(result){
      state.exportPending=false;updateExport();
      if(result.error){el('error').hidden=false;el('error').textContent=result.error;}
    },
    receive(data){
      if(data.request_id!=null&&data.request_id<state.request)return;
      if(state.angleDrag)return;
      syncAngles(data.settings.azimuth,data.settings.tilt);
      angleControls.setCatalog(data.catalog,data.spec.id);drawProduct(data.spec);
      el('error').hidden=true;
      if(!arrayMode){el('place').disabled=false;el('panelContext').hidden=!data.placement_active;el('panelContext').textContent=data.placement_active?'点击模型放置 · Esc取消':'';}
      if(!arrayMode&&data.placement_only){document.body.classList.add('placement-only');invalidateExport();return;}
      if(data.data_available===false){clearOutput('暂无出力数据');queryPoint();return;}
      if(!Array.isArray(data.values)||data.values.length!==8760||data.values.some(v=>!Number.isFinite(v)||v<0)){
        clearOutput('出力数据暂不可用');PV.fail('收到的全年出力数据不完整。');return;
      }
      chartSection.classList.remove('no-data');
      el('missingData').hidden=true;
      const reference=arrayMode?data.baseline_values:null;
      if(reference!=null&&(!Array.isArray(reference)||reference.length!==8760||reference.some(v=>!Number.isFinite(v)||v<0))){clearOutput('原始对照数据不完整');return;}
      state.values=data.values;state.reference=reference||null;aggregate();
      const context=arrayMode?data.export_context:{kind:'panel',count:1,branch:'panel'};
      state.exportSnapshot=context&&context.count>0?{settings:{...data.settings},context:{...context},values:data.values.slice()}:null;
      updateExport();
      el('annual').textContent=data.annual_kwh.toFixed(2);el('peak').textContent=data.peak_wh.toFixed(2);
      plot.dataset.azimuth=state.azimuth;plot.dataset.tilt=state.tilt;
      el('error').hidden=true;el('empty').hidden=true;if(!arrayMode)el('place').disabled=false;
      if(!arrayMode){el('panelContext').hidden=!data.placement_active;el('panelContext').textContent=data.placement_active?'点击模型放置 · Esc取消':'';}
      buildMesh();queryPoint();
    },
    clear(message='正在更新阵列…'){clearOutput(message);},
    resize(){requestRender();},
    fail(message,angles){
      if(angles)syncAngles(angles.azimuth,angles.tilt);
      el('error').hidden=false;el('error').textContent=message;
      if(!arrayMode)el('place').disabled=!state.spec;
    }
  };

  const angleControls=arrayMode?{set(){},setSpec(){},setCatalog(){}}:window.PVPanelControls.create({
    onModelChange(){state.angleDrag=false;clearOutput('正在切换型号…');sendAngles();},
    onInput(a,t){invalidateExport();state.angleDrag=true;syncAngles(a,t);},
    onCommit(a,t){state.angleDrag=false;syncAngles(a,t);sendAngles();}
  });
  fillDays();queryPoint();
  el('month').addEventListener('input',fillDays);el('day').addEventListener('input',queryPoint);el('hour').addEventListener('input',queryPoint);
  if(!arrayMode)el('place').addEventListener('click',()=>{if(window.sketchup){el('panelContext').hidden=false;el('panelContext').textContent='点击模型放置 · Esc取消';state.angleDrag=false;el('place').disabled=true;window.sketchup.place(JSON.stringify({azimuth:state.azimuth,tilt:state.tilt,model_id:el('panelModel').value}));}});
  function setPeriod(value){state.period=value;el('period').value=el('profilePeriod').value=value;if(state.values)buildMesh();queryPoint();}
  el('period').addEventListener('change',()=>setPeriod(el('period').value));
  el('profilePeriod').addEventListener('change',()=>setPeriod(el('profilePeriod').value));
  document.querySelectorAll('[data-view]').forEach(button=>button.addEventListener('click',()=>{
    state.view=button.dataset.view;
    document.querySelectorAll('[data-view]').forEach(b=>{b.classList.toggle('active',b===button);b.setAttribute('aria-selected',String(b===button));});
    const surface=state.view==='surface';
    el('surfaceArea').hidden=!surface;el('lineArea').hidden=surface;
    el('surfaceControls').hidden=!surface;el('lineMetrics').hidden=surface;el('profileControls').hidden=state.view!=='day';el('legendArea').hidden=!surface;el('resetView').hidden=!surface;
    queryPoint();
  }));
  el('resetView').addEventListener('click',()=>{state.yaw=-.62;state.elevation=.82;state.zoom=.44;requestRender();});
  let drag=null;
  canvas.addEventListener('pointerdown',event=>{drag={x:event.clientX,y:event.clientY};canvas.setPointerCapture(event.pointerId);});
  canvas.addEventListener('pointermove',event=>{if(!drag)return;state.yaw+=(event.clientX-drag.x)*.008;
    state.elevation=Math.max(.12,Math.min(1.5,state.elevation+(event.clientY-drag.y)*.006));drag={x:event.clientX,y:event.clientY};requestRender();});
  canvas.addEventListener('pointerup',()=>drag=null);canvas.addEventListener('pointercancel',()=>drag=null);
  canvas.addEventListener('wheel',event=>{event.preventDefault();state.zoom=Math.max(.25,Math.min(1.25,state.zoom*Math.exp(-event.deltaY*.001)));requestRender();},{passive:false});
  window.addEventListener('resize',requestRender);
  syncAngles(180,30);requestRender();
  if(!arrayMode&&window.sketchup&&window.sketchup.ready)window.sketchup.ready();

})();
