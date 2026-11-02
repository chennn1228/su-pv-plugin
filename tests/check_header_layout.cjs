const assert=require('assert/strict'),fs=require('fs'),path=require('path'),{pathToFileURL}=require('url');
const {createRequire}=require('module'),runtime=createRequire('C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/package.json');
const {chromium}=runtime('playwright');
const fixtures=JSON.parse(fs.readFileSync(path.resolve('output/checks/ruby_fixtures.json')));
const folder=path.resolve('output/checks');fs.mkdirSync(folder,{recursive:true});
function array99(){
 const d=structuredClone(fixtures.array),old=d.count,cols=11,rows=9;
 const px=d.projected_width_mm,py=d.projected_height_mm,gx=d.settings.gap_x_mm,gy=d.settings.gap_y_mm;
 const minx=Math.min(...d.unit_corners.map(p=>p[0])),miny=Math.min(...d.unit_corners.map(p=>p[1])),lift=-Math.min(...d.unit_corners.map(p=>p[2]));
 d.width_mm=cols*px+(cols-1)*gx;d.height_mm=rows*py+(rows-1)*gy;
 d.positions=Array.from({length:cols*rows},(_,i)=>[(i%cols)*(px+gx)-minx,Math.floor(i/cols)*(py+gy)-miny,lift]);
 d.boundary={outer:[[0,0],[d.width_mm,0],[d.width_mm,d.height_mm],[0,d.height_mm]],holes:[]};
 d.count=cols*rows;d.columns=cols;d.rows=rows;d.capacity_kwp=d.count*d.spec.power_w/1000;
 d.prediction.values=d.prediction.values.map(v=>v*d.count/old);d.prediction.annual_kwh=d.prediction.values.reduce((a,b)=>a+b,0)/1000;d.prediction.peak_wh=Math.max(...d.prediction.values);
 return d;
}
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 const findings=[],errors=[];
 try{
  for(const [width,height] of [[3840,2066],[1440,980],[940,720]])for(const forecast of [false,true]){
   const page=await browser.newPage({viewport:{width,height}});page.on('pageerror',e=>errors.push(e.message));
   await page.addInitScript(()=>{window.requests=[];window.sketchup={ready(){},preview(){},repick(){},select_export(format){requests.push(format);},export_csv(){throw Error('CSV bypassed selection');},export_figure(){throw Error('SVG bypassed selection');}};});
   await page.goto(pathToFileURL(path.resolve('ui/pv_array.html')).href);
   const data=array99();
   if(forecast){data.forecast_only=true;data.selection_summary=[{model_id:data.spec.id,manufacturer:data.spec.manufacturer,power_w:data.spec.power_w,azimuth:180,tilt:30,count:99}];}
   await page.evaluate(d=>PVArray.receive(d),data);
   if(!forecast)await page.locator('[data-array-view=power]').click();
   await page.waitForTimeout(180);
   const sizes=await page.evaluate(()=>{
    const rect=s=>{const r=document.querySelector(s).getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height};};
    const controls=['[data-view=surface]','[data-view=day]','[data-view=month]','#period','#exportCsv','#exportSvg','#resetView'].map(rect);
    return {toolbar:rect('.chart-toolbar'),views:rect('.chart-toolbar>.view-tabs'),actions:rect('.chart-actions'),controls,bodyWidth:document.documentElement.scrollWidth};
   });
   assert(sizes.bodyWidth<=width,'Header caused horizontal scrolling');assert(sizes.toolbar.h<125,'Controls still occupy too many rows');
   if(width>=1440)assert(Math.abs((sizes.views.y+sizes.views.h/2)-(sizes.actions.y+sizes.actions.h/2))<2,'Wide-screen control groups are on separate rows');
   sizes.controls.forEach((a,i)=>sizes.controls.slice(i+1).forEach(b=>assert(!(Math.min(a.x+a.w,b.x+b.w)-Math.max(a.x,b.x)>1&&Math.min(a.y+a.h,b.y+b.h)-Math.max(a.y,b.y)>1),'Controls overlap')));
   const exportEdge=sizes.controls[5].x+sizes.controls[5].w;
   assert(Math.abs(exportEdge-sizes.toolbar.x-sizes.toolbar.w)<2,'Export buttons are not at the far right');
   assert.equal(await page.locator('#plot > #resetView').count(),1);
   const plot=await page.locator('#plot').boundingBox(),reset=await page.locator('#resetView').boundingBox();
   assert(reset.x>=plot.x && reset.y>=plot.y && reset.x+reset.width<=plot.x+plot.width && reset.y+reset.height<=plot.y+plot.height,'Reset button lies outside the plot');
   if(forecast){
    assert.equal(await page.locator('#selectionOverview svg text').count(),0);
    assert.equal(await page.locator('#selectionOverview .selection-list').count(),0);
    assert.equal(await page.locator('#selectionOverview #forecastReselect').count(),1);
    assert((await page.locator('#selectionOverview').boundingBox()).height<=130,'Selection card is too tall');
    assert.match(await page.locator('#selectionOverview #forecastCount').innerText(),/99 块/);
   }
   const file=`${forecast?'selection':'array'}_${width}.png`;await page.screenshot({path:path.join(folder,file)});
   if(width===1440&&forecast){await page.locator('#exportCsv').click();await page.locator('#exportSvg').click();assert.deepEqual(await page.evaluate(()=>requests),['csv','svg']);}
   findings.push({width,height,forecast,sizes,screenshot:file});await page.close();
  }
  assert.deepEqual(errors,[]);fs.writeFileSync(path.join(folder,'layout_checks.json'),JSON.stringify(findings,null,2));
  console.log('Header layout passed: 3840/1440/940 px, aligned wide-screen controls, compact selection card, no overlaps.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
