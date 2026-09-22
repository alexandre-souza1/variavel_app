// Run against a local Rails server; requires Playwright with Chromium installed.
const baseURL = process.env.BASE_URL || 'http://127.0.0.1:3100';
const {chromium}=require('playwright');const assert=require('node:assert/strict');
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1280,height:960}});let errors=[];p.on('pageerror',e=>errors.push(e.message));
for(const [url,href] of [['/consultas/new','/rotogramas'],['/az_consultas/new','/rotogramas?origem=az']]){
 const response=await p.goto(`${baseURL}${url}`);assert.equal(response.status(),200);
 const slides=p.locator('.carousel-item');const activeIndex=await slides.evaluateAll(items=>items.findIndex(item=>item.classList.contains('active')));assert.equal(activeIndex,0);
 const link=p.locator(`a[href="${href}"]`);assert.equal(await link.count(),1);
 await p.locator('[data-bs-slide-to="1"]').click();await link.click();await p.waitForSelector('.leaflet-marker-icon');
 await p.locator('.roto-back').click();await p.waitForURL(`**${url}`);
 await p.goBack();await p.waitForSelector('.leaflet-marker-icon');assert.equal(await p.locator('.leaflet-container').count(),1);
}
await p.getByRole('searchbox').fill('Toledo');await p.locator('.leaflet-marker-icon[title="Toledo"]').click();assert.equal(await p.locator('[data-rotogramas-target=selectedName]').textContent(),'Toledo');
await p.getByRole('button',{name:'Abrir rotograma'}).click();await p.waitForSelector('[data-rotogramas-target=pageImage]:visible');await p.keyboard.press('Escape');assert.equal(await p.locator('dialog[open]').count(),0);
console.log({navigation:'passed',errors});assert.deepEqual(errors,[]);
const offline=await b.newContext();await offline.addInitScript(()=>{Object.defineProperty(window,'localStorage',{get(){throw new Error('Storage disabled')}})});const q=await offline.newPage();await q.route('https://tile.openstreetmap.org/**',r=>r.abort());await q.goto(`${baseURL}/rotogramas`);await q.waitForSelector('.roto-map-notice:visible');await q.getByRole('button',{name:'Lista',exact:true}).click();await q.getByRole('button',{name:'Consultar Cascavel',exact:true}).click();await q.waitForSelector('[data-rotogramas-target=pageImage]:visible');console.log({offlineTilesAndDisabledStorage:'passed'});await b.close();})().catch(e=>{console.error(e);process.exit(1)});
