const assert=require('assert/strict'),fs=require('fs'),path=require('path'),{pathToFileURL}=require('url');
const {createRequire}=require('module'),runtime=createRequire('C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/package.json');
const {chromium}=runtime('playwright');
const folder=path.resolve('output/checks'),fixtures=JSON.parse(fs.readFileSync(path.join(folder,'ruby_fixtures.json'))),evidence=[];
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true,args:['--enable-webgl','--use-angle=swiftshader']});
 const errors=[];
 async function pageFor(array){
  const page=await browser.newPage({viewport:{width:1440,height:980},deviceScaleFactor:1});
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.sent=[];window.sketchup={ready(){},angles(){},preview(){},export_csv(body){sent.push({format:'csv',payload:JSON.parse(body)});},export_figure(body){sent.push(JSON.parse(body));}};});
  await page.goto(pathToFileURL(path.resolve('ui',array?'pv_array.html':'pv_panel.html')).href);return page;
 }
 async function query(page,index){
  const date=new Date(Date.UTC(2025,0,1+Math.floor(index/24)));
  await page.evaluate(({m,d,h})=>{for(const [id,value] of [['month',m],['day',d],['hour',h]]){const node=document.getElementById(id);node.value=value;node.dispatchEvent(new Event('input',{bubbles:true}));}}, {m:date.getUTCMonth()+1,d:date.getUTCDate(),h:index%24});
 }
 try{
  const panel=await pageFor(false);
  for(let i=0;i<fixtures.cases.length;i++){
   const data=fixtures.cases[i],h=data.values.indexOf(Math.max(...data.values));
   await panel.evaluate(d=>PV.receive(d),data);await panel.locator('[data-view="day"]').click();await query(panel,h);
   await panel.waitForTimeout(200);
   const value=Number((await panel.locator('#pointPower').textContent()).replaceAll(',',''));
   assert.equal(value,Number(data.values[h].toFixed(2)));
   const day=Math.floor(h/24),total=data.values.slice(day*24,day*24+24).reduce((a,b)=>a+b,0)/1000;
   const shown=Number((await panel.locator('#chartEnergy').textContent()).replaceAll(',',''));assert(Math.abs(shown-total)<.006);
   const file=`panel_${i+1}.png`;await panel.screenshot({path:path.join(folder,file)});
   evidence.push({kind:'single',model:data.spec.id,index:h,expected:data.values[h],display:value,daily_expected_kwh:total,daily_display_kwh:shown,screenshot:file});
   await panel.locator('#profilePeriod').selectOption('monthly');await query(panel,171*24+12);
   const mean=Array.from({length:30},(_,d)=>data.values[(151+d)*24+12]).reduce((a,b)=>a+b)/30;
   const monthly=Number((await panel.locator('#pointPower').textContent()).replaceAll(',',''));assert.equal(monthly,Number(mean.toFixed(2)));
   evidence.push({kind:'monthly_mean',model:data.spec.id,month:6,hour:12,expected:mean,display:monthly});
   await panel.locator('#profilePeriod').selectOption('daily');
  }
  await panel.locator('#exportSvg').click();
  let exported=await panel.evaluate(()=>sent.at(-1));assert.equal(exported.format,'svg');fs.writeFileSync(path.join(folder,'single_plan.svg'),exported.body);
  const array=await pageFor(true),data=structuredClone(fixtures.array);
  // Synthetic external wall is intentionally separate from CSV value evidence.
  data.environment=[[[0,-1000,3500],[12000,-1000,3500],[12000,-1000,0]],[[0,-1000,3500],[12000,-1000,0],[0,-1000,0]]];
  await array.evaluate(d=>PVArray.receive(d),data);await array.waitForTimeout(250);await array.screenshot({path:path.join(folder,'array_layout.png')});
  assert.equal(await array.locator('#targetName').textContent(),'屋顶');
  assert.equal(await array.locator('#layoutViewTitle').textContent(),'水平俯视图');
  assert.equal(await array.locator('#layoutCanvas').getAttribute('data-north'),'[0,-1]');
  await array.locator('[data-array-view="power"]').click();await array.locator('[data-view="day"]').click();await query(array,171*24+12);
  const expected=data.prediction.values[171*24+12],display=Number(await array.locator('#pointPower').textContent());assert.equal(display,Number(expected.toFixed(2)));
  evidence.push({kind:'array',count:data.count,expected,display,screenshot:'array_baseline.png'});
  await array.screenshot({path:path.join(folder,'array_baseline.png')});
  await array.locator('[data-branch="shade"]').click();await array.waitForFunction(()=>document.querySelector('#shadeStatus').classList.contains('annual-loss'),{timeout:60000});
  await array.locator('[data-lab-step="3"]').click();await query(array,355*24+9);
  for(const layer of ['external','self','union']){await array.locator(`[data-shadow-layer="${layer}"]`).click();await array.waitForTimeout(150);await array.screenshot({path:path.join(folder,`shade_${layer}.png`)});}
  await array.locator('[data-lab-step="4"]').click();await array.locator('[data-view="day"]').click();await array.waitForTimeout(150);await array.screenshot({path:path.join(folder,'array_corrected.png')});
  assert.equal(Number(await array.locator('#labHourBaseline').textContent()),Number(data.prediction.values[355*24+9].toFixed(2)));
  assert.equal(await array.locator('#labHourCorrected').textContent(),await array.locator('#pointPower').textContent());
  assert.equal(await array.locator('#labHourRange').textContent(),'09:00—10:00');
  const baselineDay=JSON.parse(await array.locator('#lineChart').getAttribute('data-reference-values'));
  assert.deepEqual(baselineDay,data.prediction.values.slice(355*24,356*24),'The 2D baseline comparison was removed');
  await array.locator('[data-view="surface"]').click();await array.waitForTimeout(100);
  assert.equal(await array.locator('#plot').getAttribute('data-comparison'),'false');
  assert.equal(await array.locator('#plot > #resetView').isVisible(),true);
  await array.screenshot({path:path.join(folder,'array_corrected_surface.png')});
  const cardBounds=await array.locator('.array-power').boundingBox(),legendBounds=await array.locator('#legendArea').boundingBox();
  assert(legendBounds.y+legendBounds.height<=cardBounds.y+cardBounds.height,'The plot overflowed its card');
  for(const [width,height] of [[1131,764],[940,720]]){
   await array.setViewportSize({width,height});await array.waitForTimeout(100);
   const summary=await array.locator('#labHourSummary').boundingBox();
   for(const node of await array.locator('#labHourSummary>div').all()){
    const bounds=await node.boundingBox();assert(bounds.x>=summary.x && bounds.x+bounds.width<=summary.x+summary.width,'Hourly summary overflowed at a small window size');
   }
   await array.screenshot({path:path.join(folder,`array_corrected_surface_${width}.png`)});
  }
  await array.setViewportSize({width:1440,height:980});
  await array.locator('#exportCsv').click();
  const csv=await array.evaluate(()=>sent.at(-1));assert.equal(csv.payload.context.branch,'shade');assert(csv.payload.values.every((v,i)=>v<=data.prediction.values[i]+1e-6));
  await array.evaluate(()=>PV.exported({cancelled:true}));
  await array.locator('#exportSvg').click();
  exported=await array.evaluate(()=>sent.at(-1));assert.equal(exported.format,'svg');
  fs.writeFileSync(path.join(folder,'array_plan.svg'),exported.body);
  await array.evaluate(()=>PV.exported({cancelled:true}));
  assert.equal(await array.locator('#exportFigures,[data-export=png],[data-export=chart]').count(),0);
  const fence=structuredClone(fixtures.fence);await array.evaluate(d=>PVArray.receive(d),fence);
  assert.equal(await array.locator('#azimuth').isDisabled(),true);assert.equal(await array.locator('#panelModel').isEnabled(),true);
  await array.locator('[data-array-view="layout"]').click();
  assert.equal(await array.locator('#targetName').textContent(),'围墙');
  assert.equal(await array.locator('#targetPreview').getAttribute('data-kind'),'fence');
  assert.equal(await array.locator('#layoutViewTitle').textContent(),'围墙正视图');
  assert.equal(await array.locator('#layoutCanvas').getAttribute('data-projection'),'elevation');
  const projectedPanel=JSON.parse(await array.locator('#layoutCanvas').getAttribute('data-first-panel'));
  const span=axis=>Math.max(...projectedPanel.map(p=>p[axis]))-Math.min(...projectedPanel.map(p=>p[axis]));
  assert(Math.abs(span(0)-fence.spec.width_mm)<1e-6 && Math.abs(span(1)-fence.spec.length_mm)<1e-6,'Fence elevation lost its board width or height');
  const dimensions=JSON.parse(await array.locator('#layoutCanvas').getAttribute('data-dimensions'));
  assert(dimensions.some(d=>Math.abs(d.metres-1.8)<1e-7),'Fence elevation omitted the host height');
  await array.screenshot({path:path.join(folder,'fence_flush.png')});
  await array.evaluate(d=>PVArray.receive(d),fixtures.mixed);assert.equal(await array.locator('#selectionOverview .selection-meta').count(),1);
  assert.equal(await array.locator('#selectionOverview svg text').count(),0);
  assert.equal(await array.locator('#selectedModels>div').count(),2);
  const polygons=await array.locator('#selectionOverview polygon').evaluateAll(nodes=>nodes.map(n=>n.getAttribute('points')));assert(polygons.every(p=>new Set(p.split(' ')).size>2),'Selection preview collapsed its polygons');
  await array.locator('[data-branch="baseline"]').click();await array.screenshot({path:path.join(folder,'mixed_selection.png')});
  await array.evaluate(d=>PVArray.receive(d),fixtures.wall);await array.locator('[data-array-view="layout"]').click();
  assert.equal(await array.locator('#targetName').textContent(),'立面');
  assert.equal(await array.locator('#layoutViewTitle').textContent(),'立面正视图');
  assert.equal(await array.locator('#targetPreview').getAttribute('data-kind'),'wall');
  await array.screenshot({path:path.join(folder,'wall_elevation.png')});
  await array.evaluate(d=>PVArray.receive(d),fixtures.long_fence);
  assert.equal(await array.locator('#targetName').textContent(),'围墙');
  assert.equal(await array.locator('#panelCount').textContent(),'53');
  const longPanel=JSON.parse(await array.locator('#layoutCanvas').getAttribute('data-first-panel'));
  assert(Math.max(...longPanel.map(p=>p[1]))-Math.min(...longPanel.map(p=>p[1]))>2200,'Long fence collapsed to a line');
  await array.screenshot({path:path.join(folder,'long_fence_elevation.png')});
  await array.locator('[data-array-view="power"]').click();
  assert.equal(await array.locator('#missingData').isVisible(),false);
  await array.screenshot({path:path.join(folder,'north_generation.png')});
  await array.locator('[data-branch="shade"]').click();
  assert.notEqual(await array.locator('#labCalculationState').textContent(),'北向出力数据暂缺');
  assert.deepEqual(errors,[]);
  fs.writeFileSync(path.join(folder,'ui_audit.json'),JSON.stringify({rendering:'offline Chromium, actual production HTML/JS + actual Ruby fixture data',evidence,errors},null,2));
  console.log(`UI verified: ${evidence.length} data checks; branch tabs, 3 shading layers, mixed summary, fence locks, separate CSV/SVG bridges.`);
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
