// Use the fixture written by check_prediction.rb with PV_PREDICTION_FIXTURE.
const assert=require('assert/strict'),fs=require('fs'),path=require('path'),{pathToFileURL}=require('url');
const {createRequire}=require('module');
const runtime=createRequire('C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/package.json');
const {chromium}=runtime('playwright');
const fixture=JSON.parse(fs.readFileSync(process.env.PV_PREDICTION_FIXTURE||'.prediction_check/fixture.json','utf8'));
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1400,height:900}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.exports=[];window.sketchup={ready(){},repick(){},export_csv(data){window.exports.push(JSON.parse(data));}};});
  await page.goto(pathToFileURL(path.resolve('ui/pv_array.html')).href);
  await page.evaluate(data=>PVArray.receive(data),fixture);
  assert.equal(await page.locator('.array-mode-tabs').isVisible(),false);
  assert.equal(await page.locator('#arrayLayout').isVisible(),false);
  assert.equal(await page.locator('#panelModel').isDisabled(),true);
  assert.equal(await page.locator('#hour').isEnabled(),true);
  await page.locator('#exportCsv').click();
  const original=await page.evaluate(()=>window.exports.at(-1));
  assert.deepEqual(original.values,fixture.prediction.values);assert.equal(original.context.count,3);
  await page.evaluate(()=>PV.exported({cancelled:true}));
  const shots=process.env.PV_UI_CHECK_DIR||'.prediction_check';
  await page.screenshot({path:path.join(shots,'forecast.png')});
  await page.locator('#predictionBranch').selectOption('shade');
  await page.locator('[data-lab-step="3"]').click();
  await page.locator('[data-lab-step="4"]').click();
  assert.equal(await page.locator('#labCompute').count(),0);
  await page.waitForFunction(()=>document.querySelector('#shadeStatus').classList.contains('annual-loss'));
  await page.locator('#exportCsv').click();
  const corrected=await page.evaluate(()=>window.exports.at(-1));
  assert.equal(corrected.context.branch,'aggregate');assert.equal(corrected.values.length,8760);
  assert(corrected.values.every((v,i)=>v<=original.values[i]+1e-6));
  await page.evaluate(()=>PV.exported({cancelled:true}));
  await page.locator('#forecastReselect').click();
  assert.equal(await page.locator('#exportCsv').isDisabled(),true);
  await page.goto(pathToFileURL(path.resolve('ui/pv_panel.html')).href);
  await page.setViewportSize({width:940,height:660});
  await page.evaluate(data=>PV.receive({...data.prediction,placement_only:true}),fixture);
  assert.equal(await page.locator('.chart-section').isVisible(),false);
  assert.equal(await page.locator('#place').isVisible(),true);
  await page.screenshot({path:path.join(shots,'panel.png')});
  assert.deepEqual(errors,[]);
  await page.close();console.log('Prediction UI passed: actual array, raw/shaded CSV, selection invalidation and separate panel placement.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
