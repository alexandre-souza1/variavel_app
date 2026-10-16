const { chromium } = require('playwright');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch();
  const base = process.env.BASE_URL || 'http://127.0.0.1:4325';
  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(15000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('browser-automations@example.test');
    await page.locator('#user_password').fill('password123');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));

    let release;
    const paused = new Promise(resolve => { release = resolve; });
    await page.route('**/controllers/automation_drawer_controller*.js', async route => {
      await paused;
      await route.continue();
    });
    await page.goto(`${base}/automacoes`, { waitUntil: 'domcontentloaded' });
    const button = page.getByRole('button', { name: 'Nova automação', exact: true });
    assert(await button.isDisabled());
    await button.evaluate(element => element.click());
    assert.equal(new URL(page.url()).pathname, '/automacoes');
    release();
    await button.click();
    await page.locator('.automation-drawer.show:not(.showing)').waitFor();
    await page.locator('#automation_rule_name').fill('Rascunho');
    assert.equal(new URL(page.url()).pathname, '/automacoes');
    await page.getByRole('button', { name: 'Fechar formulário', exact: true }).click();
    await page.locator('.automation-drawer.show').waitFor({ state: 'hidden' });
    await page.getByRole('link', { name: 'GEROTs', exact: true }).click();
    await page.waitForURL(url => url.pathname !== '/automacoes');
    await page.goBack();
    await button.click();
    await page.locator('.automation-drawer.show:not(.showing)').waitFor();
    assert.equal(new URL(page.url()).pathname, '/automacoes');
    await page.locator('#automation_rule_name').waitFor();
    assert.deepEqual(errors, []);
    console.log('PASS: click during delayed JavaScript cannot navigate; drawer opens after loading and after browser back.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
