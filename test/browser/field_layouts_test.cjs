// Use a disposable test account with administrator access to RH, AZ and finance.
// BASE_URL=http://127.0.0.1:4318 BROWSER_EMAIL=... BROWSER_PASSWORD=... node test/browser/field_layouts_test.cjs
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const choose = require('./helpers/select.cjs');

(async () => {
  assert(process.env.BROWSER_EMAIL && process.env.BROWSER_PASSWORD, 'Provide a disposable test administrator');
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const base = process.env.BASE_URL || 'http://127.0.0.1:4318';
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill(process.env.BROWSER_EMAIL);
    await page.locator('#user_password').fill(process.env.BROWSER_PASSWORD);
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    const userId = await page.locator('body').getAttribute('data-user-id');
    fs.mkdirSync('tmp/browser', { recursive: true });
    const theme = async mode => {
      await page.evaluate(mode => {
        document.documentElement.dataset.bsTheme = mode;
        document.documentElement.dataset.colorTheme = 'retro_orange';
      }, mode);
      await page.evaluate(() => Promise.all(document.getAnimations().filter(animation => animation.effect.getComputedTiming().iterations !== Infinity).map(animation => animation.finished.catch(() => {}))));
    };
    const readable = async selector => assert(await page.locator(selector).evaluate(element => {
      const item = element.querySelector('.item');
      const arrow = getComputedStyle(element, '::after');
      const box = element.getBoundingClientRect();
      const range = document.createRange();
      range.selectNodeContents(item);
      const lines = [...range.getClientRects()].filter(rect => rect.width > 0);
      if (!lines.length) return false;
      const textRight = Math.max(...lines.map(rect => rect.right));
      const visibleRight = getComputedStyle(item).overflowX === 'hidden' ? Math.min(textRight, item.getBoundingClientRect().right) : textRight;
      return box.height >= 30 && lines.every(rect => Math.abs(rect.top - lines[0].top) < 1) &&
        visibleRight <= box.right - parseFloat(arrow.right) - parseFloat(arrow.width) - 4;
    }), `${selector}: full line and space before arrow`);

    for (const width of [1440, 390]) {
      await page.setViewportSize({ width, height: width === 390 ? 844 : 900 });
      await page.goto(`${base}/invoices/dashboard`);
      await page.waitForFunction(() => document.querySelector('#month')?.tomselect);
      for (const mode of ['light', 'dark']) {
        await theme(mode);
        await readable('#month + .app-select .ts-control');
        await readable('#year + .app-select .ts-control');
      }
      await choose(page, page.locator('select#month'), '9');
      const year = await page.locator('select#year').evaluate(element => [...element.options].find(option => option.value).value);
      await choose(page, page.locator('select#year'), year);
      await readable('#month + .app-select .ts-control');
      await page.locator('.filter-form').screenshot({ path: `tmp/browser/invoice-fields-${width}.png` });
      await page.locator('.filter-form').getByRole('button', { name: 'Filtrar', exact: true }).click();
      await page.waitForURL(url => url.searchParams.get('month') === '9' && url.searchParams.get('year') === year);

      await page.goto(`${base}/az_consultas/import`);
      await page.waitForFunction(() => document.querySelector('#az_mapa_tipo')?.tomselect);
      await theme('dark');
      const tipo = page.locator('select#az_mapa_tipo');
      assert.equal(await tipo.inputValue(), '');
      assert((await page.locator('#az_mapa_tipo + .app-select .ts-control').boundingBox()).height >= 36, 'empty required select keeps field height');
      assert.equal(await page.locator('#az_mapa_tipo + .app-select .item').textContent(), 'Selecione a meta');
      await choose(page, tipo, 'tempo_atendimento');
      await page.waitForFunction(() => document.querySelector('[data-resultado-target=campoHora]')?.tomselect);
      await choose(page, page.locator('select[data-resultado-target=campoHora]'), '2');
      await choose(page, page.locator('select[data-resultado-target=campoMinuto]'), '30');
      assert.equal(await page.locator('input[name="az_mapa[resultado]"]').inputValue(), '2.5');
      await choose(page, tipo, 'eficiencia_carregamento');
      await page.locator('input[name="az_mapa[resultado]"]').fill('98');
      await readable('#az_mapa_tipo + .app-select .ts-control');
      await page.locator('#manual-az').screenshot({ path: `tmp/browser/az-import-fields-${width}.png` });

      await page.setViewportSize({ width, height: width === 390 ? 844 : 700 });
      await page.goto(`${base}/admin/users?edit_user_id=${userId}`);
      await page.waitForFunction(() => document.querySelector('#user_sector')?.tomselect);
      await theme('dark');
      await page.locator('label[for=user_color_theme_retro_orange]').click();
      await theme('dark');
      const form = page.locator('.user-editor-card__form');
      const header = page.locator('.user-editor-card__header');
      const headerBefore = await header.boundingBox();
      assert(await form.evaluate(element => element.scrollHeight > element.clientHeight), 'long editor has internal scrolling');
      assert.equal(await page.locator('body').evaluate(element => getComputedStyle(element).overflowY), 'hidden');
      await form.hover();
      await page.mouse.wheel(0, 450);
      await page.waitForFunction(() => document.querySelector('.user-editor-card__form').scrollTop > 0);
      assert.equal((await header.boundingBox()).y, headerBefore.y, 'header remains visible during form scrolling');
      for (const id of ['user_role', 'user_sector']) {
        const control = page.locator(`#${id} + .app-select .ts-control`);
        await control.scrollIntoViewIfNeeded();
        assert(await control.evaluate(element => {
          const box = element.getBoundingClientRect();
          const icon = element.closest('.input-group').querySelector('.input-group-text').getBoundingClientRect();
          return Math.abs(box.y - icon.y) < 1 && Math.abs(box.height - icon.height) < 1 && icon.right <= box.left + 1;
        }), 'select and prefix icon share one row');
      }
      await choose(page, page.locator('select#user_sector'), 'finance');
      assert.equal(await page.locator('.user-editor-select-group .bi-cash-stack').count(), 1, 'icon updates after selecting sector');
      assert.equal(await form.evaluate(element => new FormData(element).get('user[sector]')), 'finance');
      await page.getByRole('button', { name: 'Salvar cadastro', exact: true }).scrollIntoViewIfNeeded();
      assert(await page.getByRole('button', { name: 'Salvar cadastro', exact: true }).evaluate(element => {
        const box = element.getBoundingClientRect();
        return box.top >= 0 && box.bottom <= innerHeight;
      }), 'save action is reachable');
      await page.locator('#userEditorModal .modal-content').screenshot({ path: `tmp/browser/user-editor-scroll-${width}.png` });
      await form.evaluate(element => { element.scrollTop = 0; });
      await page.locator('#userEditorModal .modal-content').screenshot({ path: `tmp/browser/user-editor-fields-${width}.png` });
      await header.getByRole('link', { name: 'Fechar', exact: true }).click();
      await page.waitForFunction(() => !document.querySelector('#userEditorModal'));
      assert.notEqual(await page.locator('body').evaluate(element => getComputedStyle(element).overflowY), 'hidden');
    }
    assert.deepEqual(errors, []);
    console.log('PASS: invoice filter labels and submission; AZ empty-select height and dependent time/percentage fields; editor scrolling, fixed header, icon alignment, sector values, reachable save and closing; desktop/mobile.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
