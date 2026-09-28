// Run against a production-mode server with precompiled assets.
// BASE_URL=http://127.0.0.1:4317 node test/browser/javascript_boot_test.cjs
const { chromium } = require('playwright');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    const baseURL = process.env.BASE_URL || 'http://127.0.0.1:4317';
    await page.route(`${baseURL}/**`, route => {
      route.continue({ headers: { ...route.request().headers(), 'X-Forwarded-Proto': 'https' } });
    });
    page.setDefaultTimeout(20000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('requestfailed', request => errors.push(request.url()));
    page.on('response', response => {
      if (response.status() >= 400) errors.push(`${response.status()} ${response.url()}`);
    });
    await page.goto(`${baseURL}/users/sign_in`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => window.Chartkick && window.Chart);
    // Exercise the libraries loaded by the real application entry point.
    await page.evaluate(() => {
      const fixture = document.createElement('div');
      fixture.innerHTML = '<div id="boot-chart"></div>' +
        '<div class="dropdown"><button id="boot-dropdown" data-bs-toggle="dropdown" aria-expanded="false">Menu</button>' +
        '<ul class="dropdown-menu"><li>Item</li></ul></div>';
      document.body.appendChild(fixture);
      new window.Chartkick.ColumnChart('boot-chart', [['Teste', 3]]);
    });
    await page.locator('#boot-chart canvas').waitFor();
    await page.locator('#boot-dropdown').click();
    assert.equal(await page.locator('#boot-dropdown').getAttribute('aria-expanded'), 'true');
    await page.locator('#boot-dropdown + .dropdown-menu.show').waitFor();
    await page.locator('#boot-dropdown').click();
    assert.equal(await page.locator('#boot-dropdown').getAttribute('aria-expanded'), 'false');
    assert.deepEqual(errors, []);
    console.log('PASS: application JavaScript, Chartkick rendering, dropdown open/close');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
