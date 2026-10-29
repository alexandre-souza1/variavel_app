// Use a disposable administrator: BROWSER_EMAIL=... BROWSER_PASSWORD=... node test/browser/color_theme_picker_test.cjs
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
    await page.goto(`${base}/admin/temas/new`);
    assert.equal(await page.locator('[data-color-theme-editor-target=preview]').count(), 2);
    await page.locator('#color_theme_name').fill('Paleta de teste');
    await page.locator('#color_theme_decoration').fill('🎄');
    assert.deepEqual(await page.locator('[data-preview-name]').allTextContents(), ['Paleta de teste', 'Paleta de teste']);
    assert.deepEqual(await page.locator('[data-preview-decoration]').allTextContents(), ['🎄', '🎄']);
    const picker = page.locator('[data-controller=color-picker]').first();
    const trigger = picker.locator('.color-picker-trigger');
    const panel = picker.locator('.color-picker-panel');
    const input = picker.locator('[data-color-picker-target=input]');
    const settle = async () => panel.evaluate(el => Promise.all(el.getAnimations({ subtree: true }).map(animation => animation.finished.catch(() => {}))));
    const hsv = async (h, s, v) => panel.evaluate((el, values) => {
      ['hue', 'saturation', 'brightness'].forEach((name, index) => el.querySelector(`[data-color-picker-target=${name}]`).value = values[index]);
      el.querySelector('[data-color-picker-target=hue]').dispatchEvent(new Event('input', { bubbles: true }));
    }, [h, s, v]);

    const initial = await input.inputValue();
    await trigger.click();
    await settle();
    assert.equal(await input.inputValue(), initial, 'opening does not round or change saved colors');
    assert.equal(await page.locator('input[type=color]').count(), 0, 'the browser native dialog is replaced');
    for (const [h, s, v, expected] of [[0, 100, 100, '#FF0000'], [120, 100, 100, '#00FF00'], [240, 100, 100, '#0000FF'], [0, 0, 100, '#FFFFFF'], [0, 100, 0, '#000000']]) {
      await hsv(h, s, v);
      assert.equal(await input.inputValue(), expected);
    }
    await hsv(0, 100, 100);
    const plane = await panel.locator('.color-picker-plane').boundingBox();
    await page.mouse.click(plane.x + plane.width / 2, plane.y + plane.height / 2);
    assert.equal(await input.inputValue(), '#804040', 'saturation and brightness plane maps correctly');
    await page.mouse.move(plane.x + plane.width / 2, plane.y + plane.height / 2);
    await page.mouse.down();
    await page.mouse.move(plane.x + plane.width + 40, plane.y + plane.height / 2);
    await page.mouse.up();
    assert.equal(await input.inputValue(), '#800000', 'dragging outside the plane clamps the value');
    const hex = panel.getByRole('textbox', { name: 'Código hexadecimal' });
    await hex.fill('#XYZ');
    assert.equal(await panel.getByRole('button', { name: 'Pronto' }).isDisabled(), true);
    assert.equal(await input.inputValue(), '#800000');
    await hex.fill('#123abc');
    assert.equal(await input.inputValue(), '#123ABC');
    assert.deepEqual(await page.locator('[data-color-theme-editor-target=preview]').evaluateAll(elements => elements.map(el => el.style.getPropertyValue('--preview-base'))), ['#123ABC', '#123ABC']);
    await input.fill('#8BBB92');
    assert.equal(await hex.inputValue(), '#8BBB92', 'typing the main hex field updates the picker');
    await panel.getByRole('button', { name: 'Usar #FFFFFF', exact: true }).click();
    assert.equal(await input.inputValue(), '#FFFFFF');
    await page.keyboard.press('Escape');
    assert.equal(await panel.isVisible(), false);
    assert.equal(await trigger.evaluate(el => el === document.activeElement), true);
    await trigger.press('Space');
    await settle();
    const hue = panel.getByRole('slider', { name: 'Matiz', exact: true });
    await hsv(0, 100, 100);
    await hue.focus();
    await hue.press('ArrowRight');
    assert.notEqual(await input.inputValue(), '#FF0000', 'native slider keyboard input changes the color');
    await panel.getByRole('button', { name: 'Pronto', exact: true }).click();
    assert.equal(await panel.isVisible(), false);
    assert.equal(await page.locator('.color-theme-form').evaluate(form => new FormData(form).get('color_theme[base_color]')), await input.inputValue());

    fs.mkdirSync('tmp/browser', { recursive: true });
    for (const width of [1440, 390]) {
      await page.setViewportSize({ width, height: 900 });
      for (const mode of ['light', 'dark']) {
        await page.evaluate(mode => document.documentElement.dataset.bsTheme = mode, mode);
        const previewState = await page.evaluate(() => {
          const surface = getComputedStyle(document.querySelector('.color-theme-form > .card')).backgroundColor;
          const page = getComputedStyle(document.body).backgroundColor;
          const panels = [...document.querySelectorAll('.color-theme-preview__body')].map(el => getComputedStyle(el).backgroundColor);
          return { surface, page, panels };
        });
        assert.notEqual(previewState.surface, previewState.page, 'editor panel is distinct from the page');
        assert.notEqual(previewState.panels[0], previewState.panels[1], 'light and dark previews are always distinct');
        await page.locator('.color-theme-preview-panel').screenshot({ path: `tmp/browser/theme-previews-${width}-${mode}.png` });
        await trigger.click();
        await settle();
        const box = await panel.boundingBox();
        assert(box.x >= 0 && box.y >= 0 && box.x + box.width <= width && box.y + box.height <= 900, 'popup stays inside viewport');
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
        await panel.screenshot({ path: `tmp/browser/color-picker-${width}-${mode}.png` });
        await page.mouse.click(width - 24, 100);
        assert.equal(await panel.isVisible(), false, 'outside click dismisses the picker');
      }
    }
    await trigger.click();
    const second = page.locator('[data-controller=color-picker]').nth(1);
    await second.locator('.color-picker-trigger').click();
    assert.equal(await page.locator('.color-picker-panel:popover-open').count(), 1);
    assert.equal(await trigger.getAttribute('aria-expanded'), 'false');
    await page.keyboard.press('Escape');
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await trigger.click();
    assert.equal(await panel.evaluate(el => getComputedStyle(el).animationName), 'none');
    assert.deepEqual(errors, []);
    console.log('PASS: HSV primaries, pointer selection and drag limits, hex validation and sync, palette suggestions, live preview, form value, keyboard, focus, outside dismissal, one popup at a time, viewport bounds, light/dark, desktop/mobile and reduced motion; no JS errors.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
