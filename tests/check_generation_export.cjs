// Browser bridge checks; no SketchUp session is opened.
const assert=require('assert/strict'),path=require('path'),{pathToFileURL}=require('url');
const {createRequire}=require('module');
const runtime=createRequire('C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/package.json');
const {chromium}=runtime('playwright');
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 try{
  for(const array of [false,true]){
   const page=await browser.newPage({viewport:{width:1500,height:980}}),errors=[];
   page.on('pageerror',error=>errors.push(error.message));
   if(array)await page.route('**/pv_array.js',route=>route.fulfill({body:''}));
   await page.addInitScript(()=>{window.exports=[];window.sketchup={ready(){},angles(){},export_csv(data){window.exports.push(JSON.parse(data));}};});
   await page.goto(pathToFileURL(path.resolve('ui',array?'pv_array.html':'pv_panel.html')).href);
   const data={settings:{azimuth:180,tilt:30,model_id:'TSM-NE19R',...(array?{gap_x_mm:100,gap_y_mm:500}:{})},
    spec:{id:'TSM-NE19R',model:'TSM-NE19R',manufacturer:'天合光能',power_w:630,width_mm:1134,length_mm:2382,thickness_mm:30},
    values:Array.from({length:8760},(_,i)=>i%24),annual_kwh:100,peak_wh:23,
    ...(array?{export_context:{kind:'array',count:12,target_id:3,branch:'aggregate'}}:{})};
   data.catalog=[data.spec];
   await page.evaluate(d=>PV.receive(d),data);
   if(array)await page.evaluate(()=>{document.querySelector('.array-power').hidden=false;});
   assert.equal(await page.locator('#exportCsv').isEnabled(),true);
   await page.locator('#exportCsv').click();
   const payload=await page.evaluate(()=>window.exports[0]);
   assert.deepEqual(payload.values,data.values);assert.deepEqual(payload.settings,data.settings);
   assert.equal(payload.context.branch,array?'aggregate':'panel');
   assert.equal(await page.locator('#exportCsv').isDisabled(),true);
   await page.evaluate(()=>PV.exported({cancelled:true}));
   assert.equal(await page.locator('#exportCsv').isEnabled(),true);
   await page.evaluate(()=>PV.clear());
   assert.equal(await page.locator('#exportCsv').isDisabled(),true);
   await page.evaluate(d=>PV.receive({...d,data_available:false}),data);
   assert.equal(await page.locator('#exportCsv').isDisabled(),true);
   if(!array){
    await page.evaluate(d=>PV.receive(d),data);
    await page.locator('#azimuth').evaluate(node=>{node.value='185';node.dispatchEvent(new Event('input',{bubbles:true}));});
    assert.equal(await page.locator('#exportCsv').isDisabled(),true);
   }
   assert.deepEqual(errors,[]);await page.close();
  }
  console.log('CSV browser checks passed: single/array payload, pending/cancel, missing data and stale scheme.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
