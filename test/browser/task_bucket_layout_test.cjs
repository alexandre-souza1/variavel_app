// Run against a test server with a plan containing a visible task.
// BASE_URL=http://127.0.0.1:4318 PLAN_ID=... node test/browser/task_bucket_layout_test.cjs
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 1000 } });
    const base = process.env.BASE_URL || 'http://127.0.0.1:4318';
    const plan = process.env.PLAN_ID || 980190962; // Rails fixture action_plans(:one).
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill(process.env.BROWSER_EMAIL || 'user_one@example.com');
    await page.locator('#user_password').fill(process.env.BROWSER_PASSWORD || 'password');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/action_plans/${plan}?view=kanban`);
    await page.locator('[data-controller~=task-modal]').first().click();
    await page.locator('#taskModal').waitFor({ state: 'visible' });
    await page.waitForFunction(() => document.querySelector('#task_bucket_id')?.tomselect);
    await page.evaluate(() => Promise.all(document.getAnimations().map(animation => animation.finished.catch(() => {}))));

    const select = page.locator('#task_bucket_id');
    const control = page.locator('#task_bucket_id + .ts-wrapper .ts-control');
    const menu = page.locator('#task_bucket_id + .ts-wrapper .ts-dropdown');
    const modal = page.locator('#taskModal .modal-content');
    const value = await select.inputValue();
    const setLabel = label => select.evaluate((element, text) => {
      const picker = element.tomselect;
      const value = picker.getValue();
      // Only the browser fixture changes; no task or bucket is saved.
      picker.updateOption(value, { ...picker.options[value], text });
    }, label);
    let saves = 0;
    page.on('request', request => {
      if (['PATCH', 'PUT'].includes(request.method()) && request.url().includes('/tasks/')) saves++;
    });

    fs.mkdirSync('tmp/browser', { recursive: true });
    for (const width of [1200, 390]) {
      await page.setViewportSize({ width, height: width === 390 ? 844 : 1000 });
      await setLabel('1.4 Checklist de Frota');
      await control.scrollIntoViewIfNeeded();
      const before = await modal.boundingBox();
      const fieldBefore = await control.boundingBox();
      await control.click();
      await menu.waitFor({ state: 'visible' });
      const open = await modal.boundingBox();
      assert(Math.abs(open.height - before.height) <= 1, 'opening bucket preserves modal height');
      assert.equal(open.width, before.width);
      assert.equal((await control.boundingBox()).height, fieldBefore.height);
      await control.locator('input').fill('Checklist');
      await page.waitForFunction(() => document.querySelector('#task_bucket_id').tomselect.lastQuery === 'Checklist');
      await menu.locator(`.option[data-value="${value}"]`).waitFor({ state: 'visible' });
      assert.equal(await select.inputValue(), value, 'search does not change the selected bucket');
      assert.equal(saves, 0, 'opening and searching do not autosave');
      assert.equal((await modal.boundingBox()).height, before.height, 'search preserves modal height');
      await page.keyboard.press('Escape');
      await menu.waitFor({ state: 'hidden' });
      assert.equal((await modal.boundingBox()).height, before.height, 'closing preserves modal height');

      const longLabel = '1.4 Checklist de Frota e manutenção de veículos com descrição extensa';
      await setLabel(longLabel);
      assert(await control.locator('.item').evaluate(element => {
        const style = getComputedStyle(element);
        return style.whiteSpace === 'nowrap' && style.textOverflow === 'ellipsis' && element.scrollWidth > element.clientWidth;
      }), 'long selected labels use ellipsis');
      assert.equal((await control.boundingBox()).height, fieldBefore.height, 'long labels do not add lines');
      await control.click();
      await menu.waitFor({ state: 'visible' });
      assert.equal(await menu.locator(`.option[data-value="${value}"] span`).textContent(), longLabel, 'menu retains the full bucket name');
      assert.equal((await modal.boundingBox()).height, before.height);
      await page.screenshot({ path: `tmp/browser/task-bucket-stable-${width}.png` });
      await page.keyboard.press('Escape');
    }
    assert.deepEqual(errors, []);
    console.log('PASS: bucket opening/search/closing preserve modal and field dimensions; long labels use ellipsis; menu retains full names; search does not autosave; desktop and mobile.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
