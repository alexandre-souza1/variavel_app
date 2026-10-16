// RAILS_ENV=test bin/rails runner test/browser/automations_setup.rb
// BASE_URL=http://127.0.0.1:4325 node test/browser/automations_test.cjs
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:4325';
  const ids = JSON.parse(fs.readFileSync('tmp/automations/browser.json', 'utf8'));
  fs.mkdirSync('tmp/automations/screenshots', { recursive: true });
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1366, height: 950 } });
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    page.on('dialog', dialog => dialog.accept());
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('browser-automations@example.test');
    await page.locator('#user_password').fill('password123');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/automacoes`);
    await page.getByRole('button', { name: 'Nova automação', exact: true }).click();
    await page.locator('.automation-drawer.show').waitFor();
    assert.equal(new URL(page.url()).pathname, '/automacoes');
    await page.locator('[data-controller="automation-form"]').waitFor();
    await page.locator('#automation_rule_name').fill('Gastos do mês no GEROT');
    const categories = page.locator('#automation-categories');
    const picker = page.locator('#automation-categories + .ts-wrapper');
    await picker.locator('input').fill('Despesas navegador');
    await page.locator('.app-select-menu:popover-open [data-value="' + ids.budget_category_id + '"]').click();
    await picker.locator('input').fill('empilhadeiras');
    await page.locator('.app-select-menu:popover-open [data-value="' + ids.second_budget_category_id + '"]').click();
    await picker.locator('input').press('Escape');
    assert.match(await page.locator('[data-automation-form-target="categoryCount"]').innerText(), /2 categorias selecionadas/);
    assert.deepEqual(await categories.evaluate(el => Array.from(el.selectedOptions, option => option.value).sort()), [String(ids.budget_category_id), String(ids.second_budget_category_id)].sort());
    await page.locator('#automation_rule_action_config_routine_template_id').selectOption(String(ids.template_id));
    await page.locator('#automation_rule_action_config_routine_indicator_id').selectOption(String(ids.indicator_id));
    await page.locator('#automation_rule_schedule').selectOption('daily');
    await page.getByRole('button', { name: 'Testar prévia', exact: true }).click();
    await page.locator('#automation-preview').waitFor();
    assert.match(await page.locator('#automation-preview').innerText(), /R\$ 200,00/);
    await page.getByRole('button', { name: 'Salvar automação pausada', exact: true }).click();
    await page.locator('.automation-drawer.show').waitFor({ state: 'hidden' });
    await page.getByRole('heading', { name: 'Gastos do mês no GEROT', exact: true }).getByRole('link').click();
    await page.waitForURL(/\/automacoes\/\d+$/);
    const financeUrl = page.url();
    assert.match(await page.locator('.dashboard-header').innerText(), /Pausada/);
    await page.getByRole('button', { name: 'Executar agora', exact: true }).click();
    await page.locator('.automation-run').first().waitFor();
    assert.match(await page.locator('.automation-run').first().innerText(), /Indicador atualizado/);
    await page.getByRole('button', { name: 'Executar agora', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('.automation-run')?.textContent.includes('Sem alteração'));
    await page.getByRole('button', { name: 'Ativar automação', exact: true }).click();
    await page.getByRole('button', { name: 'Pausar automação', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Editar regra', exact: true }).click();
    assert.deepEqual(await page.locator("#automation-categories").evaluate(el => Array.from(el.selectedOptions, option => option.value).sort()), [String(ids.budget_category_id), String(ids.second_budget_category_id)].sort());
    await page.locator('#automation_rule_name').fill('Gastos mensais no GEROT');
    await page.getByRole('button', { name: 'Salvar automação pausada', exact: true }).click();
    await page.locator('.automation-drawer.show').waitFor({ state: 'hidden' });
    await page.locator('.dashboard-header h1').filter({ hasText: 'Gastos mensais no GEROT' }).waitFor();
    assert.match(await page.locator('.dashboard-header').innerText(), /Pausada/);

    await page.goto(`${base}/automacoes/new`);
    await page.locator('#automation_rule_name').fill('Aviso de tarefas vencidas');
    await page.locator('#automation_rule_source_key').selectOption('fleet');
    assert.equal(await page.locator('#automation_rule_operation').inputValue(), 'count');
    assert.equal(await page.locator('[data-automation-form-source="invoices"]').isVisible(), false);
    assert.equal(await page.locator('[data-automation-form-source="fleet"]').isVisible(), true);
    await page.locator('#automation_rule_source_key').selectOption('tasks');
    await page.locator('#automation_rule_filters_task_status').selectOption('overdue');
    await page.locator('#automation_rule_filters_action_plan_id').selectOption(String(ids.action_plan_id));
    await page.locator('#automation_rule_action_key').selectOption('notify');
    await page.locator('#automation_rule_period').selectOption('today');
    await page.locator('#automation_rule_condition_operator').selectOption('gt');
    await page.locator('#automation_rule_condition_value').fill('0');
    await page.locator('#automation_rule_action_config_title').fill('Revisar {{valor}} pendências <img src=x>');
    await page.locator('#automation_rule_schedule').selectOption('hourly');
    await page.getByRole('button', { name: 'Salvar automação pausada', exact: true }).click();
    await page.waitForURL(/\/automacoes\/\d+$/);
    await page.getByRole('button', { name: 'Executar agora', exact: true }).click();
    await page.locator('.automation-run').first().waitFor();
    assert.match(await page.locator('.automation-run').first().innerText(), /Aviso enviado/);
    assert.equal(await page.locator('.automations-page img').count(), 0);
    await page.getByRole('button', { name: 'Executar agora', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('.automation-run')?.textContent.includes('já foi realizada'));

    await page.goto(`${base}/automacoes`);
    await page.getByRole('button', { name: 'Nova automação', exact: true }).click();
    await page.locator('#automation_rule_name').fill('Rascunho preservado');
    await page.locator('.automation-drawer.show:not(.showing)').waitFor();
    for (const width of [1366, 390, 320]) {
      await page.setViewportSize({ width, height: 950 });
      for (const theme of ['light', 'dark']) {
        await page.evaluate(theme => document.documentElement.dataset.bsTheme = theme, theme);
        const drawer = page.locator('.automation-drawer');
        assert(await drawer.evaluate(el => el.scrollWidth <= el.clientWidth));
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
        const bounds = await drawer.boundingBox();
        assert(bounds.x >= -1 && bounds.x + bounds.width <= width + 1);
        assert(Math.abs(bounds.width - (width < 768 ? width : 860)) < 1);
        await page.screenshot({ path: `tmp/automations/screenshots/drawer-${width}-${theme}.png` });
      }
    }
    await page.getByRole('button', { name: 'Fechar formulário', exact: true }).click();
    await page.locator('.automation-drawer.show').waitFor({ state: 'hidden' });
    await page.getByRole('button', { name: 'Nova automação', exact: true }).click();
    assert.equal(await page.locator('#automation_rule_name').inputValue(), 'Rascunho preservado');
    await page.keyboard.press('Escape');
    await page.locator('.automation-drawer.show').waitFor({ state: 'hidden' });

    for (const route of ['/automacoes', new URL(financeUrl).pathname, '/automacoes/new']) {
      await page.goto(`${base}${route}`);
      for (const width of [1366, 390, 320]) {
        await page.setViewportSize({ width, height: 950 });
        for (const theme of ['light', 'dark']) {
          await page.evaluate(theme => document.documentElement.dataset.bsTheme = theme, theme);
          assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `Overflow ${route} ${width}`);
          await page.screenshot({ path: `tmp/automations/screenshots/${route.split('/').pop() || 'index'}-${width}-${theme}.png`, fullPage: true });
        }
      }
    }
    assert.deepEqual(errors, []);
    console.log('PASS: searchable multiple categories, preserved selections, combined financial total, GEROT execution, pause/activate, generic rules, duplicate protection and responsive themes.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
