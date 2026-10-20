const assert=require('assert/strict'),fs=require('fs'),path=require('path'),{pathToFileURL}=require('url');
const {createRequire}=require('module');
const runtime=createRequire('C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/package.json');
const {chromium}=runtime('playwright');
const source=JSON.parse(fs.readFileSync(process.env.PV_ROOF_FIXTURE||'.roof_check/slope.json','utf8'));
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1120,height:780}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{
   window.previews=[];window.sketchup={ready(){},preview(payload){window.previews.push(JSON.parse(payload));}};
   const context=CanvasRenderingContext2D.prototype,paths=new WeakMap();
   for(const name of ['beginPath','moveTo','lineTo','fill']){
    const original=context[name];context[name]=function(...args){
     if(this.canvas.id==='layoutCanvas'){
      if(name==='beginPath')paths.set(this,[]);
      if(name==='moveTo'||name==='lineTo')paths.get(this).push(args.slice(0,2));
      if(name==='fill'&&args[0]==='evenodd')window.installationOutline=paths.get(this).map(p=>p.slice());
     }
     return original.apply(this,args);
    };
   }
  });
  await page.goto(pathToFileURL(path.resolve('ui/pv_array.html')).href);
  await page.evaluate(data=>PVArray.receive(data),source);
  const outline=await page.evaluate(()=>window.installationOutline);
  const length=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]);
  assert(Math.abs(length(outline[0],outline[1])/source.width_mm-length(outline[1],outline[2])/source.height_mm)<1e-9,'Sloped installation dimensions were foreshortened in the plan view');
  const edgeA=outline[1].map((v,i)=>v-outline[0][i]),edgeB=outline[2].map((v,i)=>v-outline[1][i]);
  assert(Math.abs(edgeA[0]*edgeB[0]+edgeA[1]*edgeB[1])<1e-7,'Orthogonal installation axes are not perpendicular in the plan view');
  assert.equal(await page.locator('#roofSlopeValue').textContent(),'27.4°');
  assert(Math.abs(Number(await page.locator('#tilt').getAttribute('min'))-27.4)<1e-7);
  assert(Math.abs(Number(await page.locator('#tiltSelect option').first().getAttribute('value'))-27.4)<1e-7);
  assert.equal(await page.locator('#tiltBounds').textContent(),'27.4° — 90°');
  await page.locator('#tiltDiagram').press('Home');
  assert(Math.abs(Number(await page.locator('#tilt').inputValue())-27.4)<1e-7);
  assert.equal(await page.locator('#azimuthSelect').inputValue(),'180');
  await page.locator('#fitRoof').click();
  await page.waitForFunction(()=>window.previews.length>0&&Math.abs(window.previews[window.previews.length-1].azimuth-151.2)<1e-7);
  const fitted=await page.evaluate(()=>window.previews[window.previews.length-1]);
  assert(Math.abs(fitted.tilt-27.4)<1e-7);
  const alignment=await page.evaluate(()=>['x2','y2'].every(key=>Math.abs(Number(document.querySelector('#roofSlopeLine').getAttribute(key))-Number(document.querySelector('#tiltPanel').getAttribute(key)))<1e-7));
  assert(alignment,'Roof section and panel diagram do not coincide after fitting');
  assert(Number(await page.locator('#roofRelativeAngle').getAttribute('data-degrees'))<1e-5);
  const fittedData=structuredClone(source.fitted_plan);fittedData.request_id=fitted.request_id;
  await page.evaluate(data=>PVArray.receive(data),fittedData);
  assert.equal(await page.locator('#arrayError').isVisible(),false);
  assert.equal(await page.locator('#build').isEnabled(),true);
  await page.locator('[data-array-view="power"]').click();
  assert.equal(await page.locator('#missingData').isVisible(),true);
  await page.locator('[data-array-view="layout"]').click();
  await page.locator('#azimuthSelect').selectOption('180');
  assert(Math.abs(Number(await page.locator('#tilt').inputValue())-27.4)<1e-7);
  assert.equal(await page.locator('#azimuthSelect').inputValue(),'180');
  await page.evaluate(data=>PVArray.receive({...data,request_id:100}),fittedData);
  await page.screenshot({path:process.env.PV_ROOF_SCREENSHOT||'.roof_check/angles.png'});
  await page.evaluate(data=>PVArray.receive(data),source.opposing_plan);
  assert.equal(await page.locator('#roofAspectValue').textContent(),'0°');
  assert.equal(await page.locator('#tilt').getAttribute('max'),'60');
  assert.equal(await page.locator('#tiltBounds').textContent(),'30° — 60°');
  assert.equal(await page.locator('#roofRelativeAngle').textContent(),'与屋面夹角 60°');
  await page.locator('#tiltDiagram').press('End');
  assert.equal(await page.locator('#tilt').inputValue(),'60');
  assert.equal(await page.locator('#roofRelativeAngle').textContent(),'与屋面夹角 90°');
  await page.locator('#fitRoof').click();
  assert.equal(await page.locator('#azimuthSelect').inputValue(),'0');
  assert.equal(await page.locator('#tilt').inputValue(),'30');
  assert.equal(await page.locator('#roofRelativeAngle').textContent(),'与屋面夹角 0°');
  assert.equal(await page.locator('#tilt').getAttribute('max'),'90');
  const next=structuredClone(source),r=Math.PI/4;
  next.target_id=3;next.settings.tilt=45;next.prediction.settings.tilt=45;
  next.roof_normal=[0,-Math.sin(r),Math.cos(r)];
  next.frame_axes=[[1,0,0],[0,Math.cos(r),Math.sin(r)],next.roof_normal];
  await page.evaluate(data=>PVArray.receive(data),next);
  assert.equal(await page.locator('#tilt').getAttribute('min'),'45');
  assert.equal(await page.locator('#tiltSelect').inputValue(),'45');
  next.target_id=4;next.settings.tilt=0;next.prediction.settings.tilt=0;next.roof_normal=[0,0,1];next.frame_axes=[[1,0,0],[0,1,0],[0,0,1]];
  await page.evaluate(data=>PVArray.receive(data),next);
  assert.equal(await page.locator('#tilt').getAttribute('min'),'0');
  assert.equal(await page.locator('#tiltSelect option').count(),31);
  // Existing instances remain faithful in the read-only prediction view.
  next.target_id=5;next.forecast_only=true;next.roof_normal=[0,-Math.sin(r),Math.cos(r)];
  await page.evaluate(data=>PVArray.receive(data),next);
  assert.equal(await page.locator('#tiltSelect').inputValue(),'0');
  assert.equal(await page.locator('#roofSlopeValue').textContent(),'45°');
  assert.equal(await page.locator('#tiltBounds').isVisible(),false);
  assert.equal(await page.locator('#fitRoof').isVisible(),false);
  assert.deepEqual(errors,[]);await page.close();
  console.log('Roof angle UI passed: independent azimuth, exact roof fitting, callback angles, missing data, changing roofs and read-only angles.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
