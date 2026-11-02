const assert=require('assert/strict'),fs=require('fs'),path=require('path'),{pathToFileURL}=require('url');
const {createRequire}=require('module'),runtime=createRequire('C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/package.json'),{chromium}=runtime('playwright');
const folder=path.resolve('output/checks'),fixtures=JSON.parse(fs.readFileSync(path.join(folder,'access_fixtures.json'))),auto=JSON.parse(fs.readFileSync(path.join(folder,'access_auto_fixture.json')));
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.previews=[];window.builds=[];window.picks=[];window.sketchup={ready(){},preview(p){previews.push(JSON.parse(p));},build(p){builds.push(JSON.parse(p));},access_pick(p){picks.push(JSON.parse(p));}};});
  await page.goto(pathToFileURL(path.resolve('ui/pv_array.html')).href);
  await page.evaluate(d=>PVArray.receive(d),fixtures.base);
  assert.deepEqual(await page.locator('[data-array-view]').allTextContents(),['阵列排布','出力预测']);
  assert.equal(await page.locator('#accessWorkspace').isVisible(),false);
  await page.evaluate(()=>PVArray.selectView('access'));assert.equal(await page.locator('#accessWorkspace').isVisible(),false,'Array window still opens the removed constraints tab');
  const boundary=d=>{const copy=structuredClone(d);copy.constraints_only=true;copy.editing_existing=true;delete copy.prediction;return copy;};
  const show=async d=>page.evaluate(d=>PVArray.receive(d),boundary(d));
  await show(fixtures.base);assert.equal(await page.locator('#accessWorkspace').isVisible(),true);
  assert.equal(await page.locator('#constraintsTitle').isVisible(),true);assert.equal(await page.locator('.array-mode-tabs').isVisible(),false);
  await page.evaluate(()=>PVArray.selectView('power'));assert.equal(await page.locator('#accessWorkspace').isVisible(),true);assert.equal(await page.locator('.array-power').isVisible(),false);
  assert.deepEqual(await page.locator('.access-step').evaluateAll(nodes=>nodes.map(n=>n.dataset.accessStep)),['scope','conditions','generate']);
  assert.equal(await page.locator('.access-process-strip canvas').count(),3);assert.equal(await page.locator('#accessPartitionSize').textContent(),'15 × 15 m');
  assert.equal(await page.locator('#accessRouteSummary').textContent(),'待选入口');assert.equal(await page.locator('#accessProcessRoute').getAttribute('data-route-paths'),'0');
  assert(Number(await page.locator('#accessCanvas').getAttribute('data-zone-count'))>0,'Legend is visible but subdivisions were not rendered');
  assert.equal(await page.locator('#accessCanvas').getAttribute('data-partition-span'),'15000');
  await page.locator('#accessShowZones').uncheck();assert.equal(await page.locator('#accessCanvas').getAttribute('data-partition-span'),'');await page.locator('#accessShowZones').check();
  assert.equal(await page.locator('#arrayLayout').isVisible(),false);assert.equal(await page.locator('#shadingLab').isVisible(),false);
  assert.equal(await page.locator('#accessAuto').isDisabled(),true);
  assert.equal(await page.locator('#accessExclusions').textContent(),'未设禁布区');
  assert.equal(await page.locator('.access-legend .route').evaluate(node=>node.classList.contains('inactive')),true);
  await page.locator('#accessWidthRange').fill('0.95');await page.locator('#accessSpanRange').fill('18.5');await page.waitForTimeout(180);
  const sliders=await page.evaluate(()=>previews.at(-1));assert.equal(sliders.access.width_mm,950);assert.equal(sliders.access.span_mm,18500);
  assert.equal(await page.locator('#accessWidth').inputValue(),'0.95');assert.equal(await page.locator('#accessSpan').inputValue(),'18.5');
  await page.locator('#accessWidth').fill('4');await page.waitForTimeout(180);assert.equal(await page.locator('#accessWidthRange').inputValue(),'4');
  const reset=structuredClone(fixtures.base);reset.request_id=await page.evaluate(()=>previews.at(-1).request_id);await show(reset);
  assert.equal(await page.locator('#accessCentred').textContent(),String(fixtures.base.count));assert.equal(await page.locator('#accessRetained').textContent(),String(fixtures.base.count));
  await page.locator('[data-access-mode=entry]').click();let pick=await page.evaluate(()=>picks.at(-1));assert.equal(pick.pick_mode,'entry');assert.equal(pick.target_id,fixtures.base.target_id);assert.equal(await page.locator('#build').isDisabled(),true);
  const entry=structuredClone(fixtures.connected);entry.settings.access.automatic=true;entry.request_id=pick.request_id;await show(entry);
  assert(Number(await page.locator('#accessCanvas').getAttribute('data-access-paths'))>0,'Returning from entrance picking did not display the generated corridor');
  assert.equal(await page.locator('.access-legend .route').evaluate(node=>node.classList.contains('inactive')),false);
  assert.equal(await page.locator('#accessAuto').textContent(),'重新预览方案');
  await page.locator('#accessAuto').click();await page.waitForTimeout(420);let payload=await page.evaluate(()=>previews.at(-1));assert.equal(payload.access.automatic,true);assert.equal(payload.access.span_mm,15000);
  const routed=structuredClone(fixtures.connected);routed.request_id=payload.request_id;routed.settings.access.automatic=true;await show(routed);
  await page.locator('[data-access-mode=exclude]').click();pick=await page.evaluate(()=>picks.at(-1));assert.equal(pick.pick_mode,'exclude');assert.equal(pick.access.automatic,true);
  const excluded=structuredClone(fixtures.combined);excluded.request_id=pick.request_id;excluded.settings.access.automatic=true;await show(excluded);
  assert.equal(await page.locator('#accessCanvas').getAttribute('data-exclusions'),'1');assert.equal(await page.locator('#build').isEnabled(),true);
  assert.equal(await page.locator('.access-legend .excluded').evaluate(node=>node.classList.contains('inactive')),false);
  await page.locator('#edgeSetbackRange').fill('0.65');await page.locator('#holeSetback').fill('0.3');await page.waitForTimeout(420);payload=await page.evaluate(()=>previews.at(-1));assert.equal(payload.access.edge_mm,650);assert.equal(payload.access.hole_mm,300);assert.equal(payload.access.automatic,true);
  // Real Ruby-generated automatic plan, including concave boundary and hole.
  await show(auto);
  assert.equal(await page.locator('#targetPreview').getAttribute('data-rings'),'2');assert.equal(await page.locator('#targetPreview path').getAttribute('fill-rule'),'evenodd');
  assert.equal(await page.locator('#accessRetained').textContent(),String(auto.count));assert.equal(await page.locator('#accessRemoved').textContent(),String(auto.access_removed_count));
  assert.equal(await page.locator('#accessCanvas').getAttribute('data-access-paths'),String(auto.settings.access.paths.length));
  assert.equal(await page.locator('#accessAvailable').textContent(),String(auto.access_baseline_count));
  for(const id of ['accessProcessZones','accessProcessRoute','accessProcessResult'])assert.equal(await page.locator('#'+id).getAttribute('data-outer-vertices'),String(auto.boundary.outer.length),'Process thumbnail is not derived from the current roof');
  assert.equal(await page.locator('#accessProcessZones').getAttribute('data-zone-count'),String(auto.access_trace.zones.length));
  await page.locator('[data-access-result=zones]').click();assert.equal(await page.locator('#accessCanvas').getAttribute('data-stage'),'zones');assert.equal(await page.locator('#accessCanvas').getAttribute('data-access-paths'),'0');
  await page.locator('[data-access-stage=route]').click();assert.equal(await page.locator('#accessCanvas').getAttribute('data-stage'),'route');assert.equal(await page.locator('[data-access-result=route]').getAttribute('aria-pressed'),'true');
  const selectedColors=await page.evaluate(()=>['[data-access-stage=route]','[data-access-result=route]'].map(s=>getComputedStyle(document.querySelector(s)).backgroundColor));
  assert.equal(selectedColors[0],selectedColors[1],'Process thumbnail and metric do not share their visible selection');assert.notEqual(selectedColors[0],'rgba(0, 0, 0, 0)');
  const legendColors=await page.evaluate(()=>['.access-legend .setback','.access-legend .excluded'].map(s=>getComputedStyle(document.querySelector(s),'::before').backgroundColor));assert.notEqual(legendColors[0],legendColors[1]);
  assert.equal(await page.locator('#accessCanvas').getAttribute('data-access-paths'),String(auto.settings.access.paths.length));
  await page.locator('[data-access-result=result]').focus();await page.keyboard.press('Enter');assert.equal(await page.locator('#accessCanvas').getAttribute('data-stage'),'result');
  for(const [width,height] of [[940,720],[1440,1000],[2560,1440]]){
   await page.setViewportSize({width,height});await page.waitForTimeout(120);
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'Access UI overflows viewport');
   const geometry=await page.evaluate(()=>{const r=s=>{const q=document.querySelector(s).getBoundingClientRect();return {x:q.x,y:q.y,right:q.right,bottom:q.bottom,w:q.width,h:q.height};};return {module:r('#accessModule'),map:r('.access-map'),canvas:r('#accessCanvas')};});
   assert(geometry.canvas.w>200&&geometry.canvas.h>250,'Preview collapsed');assert(geometry.map.y>=geometry.module.bottom-1||geometry.map.x>=geometry.module.right-1,'Controls overlap preview');
   const correspondence=await page.evaluate(()=>[...document.querySelectorAll('.access-step>.section-label')].map((heading,i)=>({heading:heading.getBoundingClientRect().x,result:document.querySelectorAll('[data-access-result]')[i].getBoundingClientRect().x})));
   assert(correspondence.every(p=>Math.abs(p.heading-p.result)<1),'Results do not align with their corresponding operation columns');
   await page.screenshot({path:path.join(folder,`access_native_${width}.png`)});
   if(width===1440){
    await page.locator('.array-chart').evaluate(node=>node.scrollTop=0);
    const clip=await page.evaluate(()=>{const a=document.querySelector('.array-heading').getBoundingClientRect(),b=document.querySelector('.access-impact').getBoundingClientRect();return {x:Math.floor(b.x),y:Math.floor(a.y),width:Math.ceil(b.width),height:Math.ceil(b.bottom-a.y)};});
    await page.screenshot({path:path.join(folder,'access_workflow.png'),clip});
   }
  }
  await page.setViewportSize({width:1440,height:1000});await page.locator('#build').click();assert.equal((await page.evaluate(()=>builds.at(-1))).access.paths.length,auto.settings.access.paths.length);
  const forecast=structuredClone(auto);forecast.target_id=auto.target_id+1;await page.evaluate(d=>PVArray.receive(d),forecast);
  assert.equal(await page.locator('#accessWorkspace').isVisible(),false);assert.equal(await page.locator('#constraintsTitle').isVisible(),false);await page.locator('[data-array-view=power]').click();
  assert(Math.abs(Number(await page.locator('#annual').textContent())-auto.prediction.annual_kwh)<.006,'Forecast count differs from retained panels');
  await page.locator('[data-array-view=layout]').click();assert.equal(await page.locator('#arrayLayout').isVisible(),true);assert.equal(await page.locator('#accessWorkspace').isVisible(),false);
  const slope=structuredClone(fixtures.slope);slope.target_id=9;await show(slope);assert.equal(await page.locator('#accessCanvas').getAttribute('data-projection'),'horizontal');
  const all=JSON.parse(fs.readFileSync(path.join(folder,'ruby_fixtures.json'))),fence=structuredClone(all.long_fence);fence.target_id=10;await page.evaluate(d=>PVArray.receive(d),fence);
  assert.equal(await page.locator('[data-array-view=access]').count(),0);assert.equal(await page.locator('#accessWorkspace').isVisible(),false);assert.equal(await page.locator('#targetName').textContent(),'围墙');
  await page.reload();await show(fixtures.base);
  const edit=structuredClone(fixtures.combined);edit.target_id=80;await show(edit);
  assert.equal(await page.locator('#build').textContent(),'更新阵列');
  for(const clearance of [0.5,1.25,2]){
   await page.locator('#holeSetback').fill(String(clearance));await page.waitForTimeout(180);
   const current=await page.evaluate(()=>previews.at(-1));assert.equal(current.access.hole_mm,clearance*1000);
   assert.equal(await page.locator('#accessCanvas').getAttribute('data-internal-setback'),String(clearance*1000),'Internal setback did not repaint immediately');
   const reply=structuredClone(edit);reply.request_id=current.request_id;reply.settings.access.hole_mm=clearance*1000;await show(reply);
  }
  await page.locator('#build').click();await page.evaluate(()=>PVArray.built({count:12,editing_existing:true}));assert.equal(await page.locator('#build').textContent(),'已更新阵列');
  await page.evaluate(()=>delete window.sketchup.access_pick);await page.locator('[data-access-mode=entry]').click();
  assert.match(await page.locator('#arrayError').textContent(),/选取功能尚未加载/,'An old dialog with no native callback silently ignored the action');
  assert.deepEqual(errors,[]);console.log('Access UI verified: standalone boundary workspace without prediction payload, removed array tab, native picking, live setbacks, responsive layouts, existing-array updates and preserved array forecasts.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
