// Disposable admin required. RUN_LIVE_GEMINI=1 also makes one real Gemini call; drafts are never saved.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  assert(process.env.BROWSER_EMAIL && process.env.BROWSER_PASSWORD, 'Provide a disposable administrator');
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const base = process.env.BASE_URL || 'http://127.0.0.1:3000';
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill(process.env.BROWSER_EMAIL);
    await page.locator('#user_password').fill(process.env.BROWSER_PASSWORD);
    await page.locator('input[name=commit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/admin/temas`);
    await page.getByRole('link', { name: 'Criar com IA', exact: true }).click();
    const generator = page.locator('.color-theme-ai');
    await generator.waitFor();
    assert.equal(await generator.getAttribute('open'), '');
    const colors = generator.locator('[data-color-theme-generator-target=colors]');
    const button = generator.locator('[data-color-theme-generator-target=button]');
    const error = generator.locator('[data-color-theme-generator-target=error]');
    const status = generator.locator('[data-color-theme-generator-target=status]');
    let calls = 0;
    let success = false;
    let release;
    let arrived;
    const pending = new Promise(resolve => { release = resolve; });
    const started = new Promise(resolve => { arrived = resolve; });
    const theme = { name: 'Bosque da Meia-Noite', description: 'Verdes profundos com detalhes em menta.',
      base_color: '#092328', primary_color: '#12544F', accent_color: '#2A835F', highlight_color: '#8BBB92',
      extra_color: null, decoration: '🌿', promotion_text: 'Experimente o Bosque da Meia-Noite' };
    await page.route('**/admin/temas/gerar-com-ia', async route => {
      calls++;
      assert.equal(route.request().method(), 'POST');
      assert(route.request().headers()['x-csrf-token']);
      assert.equal(route.request().postDataJSON().colors, '#8BBB92 #092328 #2A835F #12544F');
      if (!success) return route.fulfill({ status: 429, contentType: 'application/json', body: JSON.stringify({ error: 'O limite de uso do Gemini foi atingido.' }) });
      arrived();
      await pending;
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ theme }) });
    });
    await colors.fill('not a HEX');
    await button.click();
    assert.equal(await error.isVisible(), true);
    assert.equal(calls, 0);
    await page.keyboard.press('Escape');
    assert.equal(await generator.isVisible(), false);
    await page.locator('#color_theme_name').fill('Meu rascunho');
    await page.getByRole('button', { name: 'Criar com IA', exact: true }).click();
    await colors.fill('#8bbb92, #092328; #2a835f\n#12544f');
    await button.click();
    await page.waitForFunction(() => document.querySelector('.color-theme-ai').getAttribute('aria-busy') === 'false');
    assert.match(await error.textContent(), /limite/);
    assert.equal(await page.locator('#color_theme_name').inputValue(), 'Meu rascunho', 'provider error preserves manual edits');
    assert.equal(await button.isEnabled(), true);
    success = true;
    await button.click();
    await started;
    assert.equal(await page.locator('.color-theme-form input[type=submit]').isDisabled(), true);
    assert.equal(await colors.isDisabled(), true);
    await button.evaluate(el => el.click());
    assert.equal(calls, 2, 'double clicks do not create duplicate requests');
    release();
    await page.waitForFunction(() => document.querySelector('[data-color-theme-generator-target=feedback]').textContent.includes('Sugestão gerada'));
    assert.equal(await generator.isVisible(), false, 'success closes the modal and returns to the editor');
    assert.equal(await page.locator('#color_theme_name').inputValue(), theme.name);
    assert.equal(await page.locator('#color_theme_description').inputValue(), theme.description);
    assert.deepEqual(await page.locator('[data-preview-name]').allTextContents(), [theme.name, theme.name]);
    assert.deepEqual(await page.locator('[data-color-theme-editor-target=preview]').evaluateAll(elements => elements.map(el => el.style.getPropertyValue('--preview-base'))), [theme.base_color, theme.base_color]);
    assert.equal(await page.locator('[data-color-key=base_color]').evaluate(el => el.closest('[data-controller=color-picker]').querySelector('.color-picker-trigger__swatch').style.backgroundColor), 'rgb(9, 35, 40)');
    assert.equal(await page.locator('#color_theme_promotion_enabled').isChecked(), false);
    assert.equal(await page.locator('[data-color-theme-editor-target=promotionFields]').evaluate(el => el.disabled), true);
    assert.equal(await page.locator('.color-theme-form input[type=submit]').isEnabled(), true);
    assert.equal(await colors.isEnabled(), true);
    assert.equal(new URL(page.url()).pathname, '/admin/temas/new', 'AI only fills the form');
    fs.mkdirSync('tmp/browser', { recursive: true });
    for (const width of [1440, 390]) {
      await page.setViewportSize({ width, height: 1000 });
      await page.getByRole('button', { name: 'Criar com IA', exact: true }).click();
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      assert.equal(await generator.locator('[data-color-theme-generator-target=swatches] > span').count(), 4);
      const box = await generator.boundingBox();
      assert(box.x >= 0 && box.y >= 0 && box.x + box.width <= width && box.y + box.height <= 1000);
      await generator.screenshot({ path: `tmp/browser/theme-generator-${width}.png` });
      await page.keyboard.press('Escape');
    }
    await page.unroute('**/admin/temas/gerar-com-ia');
    if (process.env.RUN_LIVE_GEMINI === '1') {
      await page.goto(`${base}/admin/temas/new?ai=1`);
      await colors.fill('#8BBB92 #092328 #2A835F #12544F');
      await button.click();
      await page.waitForFunction(() => {
        const generator = document.querySelector('.color-theme-ai');
        return generator.getAttribute('aria-busy') === 'false' &&
          (!generator.open || !generator.querySelector('[data-color-theme-generator-target=error]').hidden);
      }, null, { timeout: 40000 });
      assert.equal(await error.isVisible(), false, await error.textContent());
      const generated = await page.locator('[data-color-theme-editor-target=color]').evaluateAll(inputs => inputs.map(input => input.value).filter(Boolean));
      assert.deepEqual(generated.sort(), ['#8BBB92', '#092328', '#2A835F', '#12544F'].sort(), 'live Gemini preserves supplied colors');
      assert((await page.locator('#color_theme_name').inputValue()).trim());
      assert.equal(await page.locator('#color_theme_promotion_enabled').isChecked(), false);
      console.log('PASS: one live Gemini request populated an unsaved theme and preserved all supplied HEX colors.');
    }
    assert.deepEqual(errors, []);
    console.log('PASS: focused AI dialog, Escape and focus, client validation, errors preserve edits, loading state, double-click guard, color samples, generated draft returned to the editor, both previews, desktop/mobile and no JS errors.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
