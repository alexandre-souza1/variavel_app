const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:4325';
  const browser = await chromium.launch();
  fs.mkdirSync('tmp/automations/ai-screenshots', { recursive: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1366, height: 950 } });
    page.setDefaultTimeout(15000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('browser-automations@example.test');
    await page.locator('#user_password').fill('password123');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/automacoes`);
    await page.locator('.ai-assistant__launcher').click();
    const panel = page.locator('.ai-assistant__panel');
    const paused = page.locator('.ai-assistant__proposal').filter({ has: page.locator('> strong', { hasText: 'Combustível pela conversa' }) });
    const active = page.locator('.ai-assistant__proposal').filter({ has: page.locator('> strong', { hasText: 'Aviso de pendências' }) });
    await paused.waitFor();
    assert.equal(await paused.locator('img').count(), 0);
    assert.equal(await page.evaluate(() => window.autoInjected), undefined);
    await paused.getByRole('button', { name: 'Ajustar', exact: true }).click();
    assert.match(await page.locator('#ai-assistant-question').inputValue(), /Quero ajustar a proposta/);
    await page.locator('#ai-assistant-question').fill('');
    for (const width of [1366, 390, 320]) {
      await page.setViewportSize({ width, height: 950 });
      for (const theme of ['light', 'dark']) {
        await page.evaluate(theme => document.documentElement.dataset.bsTheme = theme, theme);
        assert(await panel.evaluate(el => el.scrollWidth <= el.clientWidth));
        assert(await paused.evaluate(el => el.scrollWidth <= el.clientWidth));
        await page.screenshot({ path: `tmp/automations/ai-screenshots/${width}-${theme}.png` });
      }
    }
    await paused.getByRole('button', { name: 'Salvar automação pausada', exact: true }).click();
    await paused.getByText('Automação salva pausada após sua confirmação.', { exact: true }).waitFor();
    await paused.getByRole('link', { name: 'Abrir automação', exact: true }).waitFor();
    await active.getByRole('button', { name: 'Salvar e ativar automação', exact: true }).click();
    await active.getByText('Automação salva e ativada após sua confirmação.', { exact: true }).waitFor();
    await page.reload();
    await page.locator('.ai-assistant__launcher').click();
    await paused.getByRole('link', { name: 'Abrir automação', exact: true }).click();
    await page.waitForURL(/\/automacoes\/\d+$/);
    assert.match(await page.locator('.dashboard-header').innerText(), /Pausada/);
    assert.match(await page.locator('.automation-history').innerText(), /Nenhuma execução/);
    await page.goto(`${base}/automacoes`);
    const state = await (await page.request.get(`${base}/assistente-ia`)).json();
    let question;
    const descriptions = [];
    await page.route('**/assistente-ia', route => {
      if (route.request().method() !== 'POST') return route.continue();
      question = route.request().postDataJSON().question;
      descriptions.push(question);
      return route.fulfill({ status: 202, json: { ...state, processing: false } });
    });
    assert.equal(await page.getByRole('button', { name: 'Montar com IA', exact: true }).count(), 0);
    const disclosure = page.locator('details.automation-description');
    const summary = disclosure.locator('summary');
    assert.equal(await disclosure.evaluate(el => el.open), false);
    assert.equal(await page.locator('#automation-description').isVisible(), false);
    await summary.focus();
    await page.keyboard.press('Enter');
    const text = 'Todo dia às 8h, some o abastecimento do mês e preencha o indicador de combustível no GEROT da Frota.';
    await page.locator('#automation-description').fill(text);
    await summary.click();
    assert.equal(await disclosure.evaluate(el => el.open), false);
    await summary.click();
    assert.equal(await page.locator('#automation-description').inputValue(), text);
    await page.getByRole('button', { name: 'Gerar prévia com IA', exact: true }).click();
    await panel.waitFor({ state: 'visible' });
    await page.waitForFunction(() => !document.querySelector('[data-ai-assistant-target="send"]').disabled);
    assert.equal(descriptions.length, 1);
    assert(question.endsWith(text));
    assert.match(question, /pergunte somente o que faltar/);
    assert.equal(question.includes('perguntando um dado por vez'), false);

    await page.getByRole('button', { name: 'Minimizar assistente', exact: true }).click();
    await page.locator('#automation-description').fill('   ');
    await page.getByRole('button', { name: 'Gerar prévia com IA', exact: true }).click();
    assert.equal(descriptions.length, 1);
    assert.equal(await panel.isVisible(), false);
    await page.locator('#automation-description').fill(text);
    for (const width of [1366, 390, 320]) {
      await page.setViewportSize({ width, height: 950 });
      for (const theme of ['light', 'dark']) {
        await page.evaluate(theme => document.documentElement.dataset.bsTheme = theme, theme);
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
        await page.screenshot({ path: `tmp/automations/ai-screenshots/description-${width}-${theme}.png`, fullPage: true });
      }
    }
    assert.deepEqual(errors, []);
    console.log('PASS: automation cards, activation, confirmation, collapsible creation panel, plain text description, empty-input validation, preserved text and responsive themes.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
