// Run against a local server using the disposable test database.
// BASE_URL=http://127.0.0.1:4321 BROWSER_EMAIL=... BROWSER_PASSWORD=... node test/browser/employees_test.cjs
const chooseSelect = require('./helpers/select.cjs');
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

(async () => {
  assert(process.env.BROWSER_EMAIL && process.env.BROWSER_PASSWORD, 'Provide a test user in BROWSER_EMAIL/BROWSER_PASSWORD');
  const browser = await chromium.launch();
  const base = process.env.BASE_URL || 'http://127.0.0.1:4321';
  const registration = `BROWSER-${Date.now()}`;
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.setDefaultTimeout(20000);
  try {
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill(process.env.BROWSER_EMAIL);
    await page.locator('#user_password').fill(process.env.BROWSER_PASSWORD);
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/rh/colaboradores/new?employee_sector=az&employee_cargo=operador`);
    await page.waitForFunction(() => document.querySelector('#initial_promax')?.disabled);
    assert(await page.locator('[data-employee-role-target=du]').isHidden());
    assert(await page.locator('[data-employee-role-target=az]').isVisible());
    assert.equal(await page.locator('#initial_cargo').inputValue(), 'operador');
    await chooseSelect(page, page.locator('#initial_sector'), 'du');
    await page.waitForFunction(() => document.querySelector('#initial_turno').disabled);
    assert(await page.locator('[data-employee-role-target=az]').isHidden());
    assert(await page.locator('[data-employee-role-target=du]').isVisible());
    assert.equal(await page.locator('#initial_promax').getAttribute('required'), null);
    await chooseSelect(page, page.locator('#initial_sector'), 'az');
    await chooseSelect(page, page.locator('#initial_cargo'), 'operador');
    await page.locator('#employee_nome').fill('Pessoa de teste do navegador');
    await page.locator('#employee_matricula').fill(registration);
    await page.locator('#employee_data_nascimento').fill('1990-01-01');
    await page.locator('#employee_registered_on').fill('2025-12-22');
    assert.equal(await page.locator('#initial_starts_on').getAttribute('required'), null);
    assert.equal(await page.locator('#initial_turno').inputValue(), '');
    assert.equal(await page.locator('#initial_turno').getAttribute('required'), null);
    await page.locator('#initial_starts_on').fill('2026-01-01');
    await page.waitForFunction(() => document.querySelector('#initial_turno').required);
    await page.locator('#initial_starts_on').fill('');
    await page.waitForFunction(() => !document.querySelector('#initial_turno').required);
    assert.equal(await page.locator('#initial_reason').count(), 0, 'Initial registration should not ask for a change reason');
    await page.getByRole('button', { name: 'Cadastrar colaborador' }).click();
    await page.waitForURL(url => /^\/rh\/colaboradores\/\d+$/.test(url.pathname));
    await page.locator('.employees-overview').getByText('Em integração', { exact: true }).waitFor();
    assert.equal(await page.locator('#promotion_starts_on').count(), 0);
    await page.getByRole('link', { name: 'Informar início na função', exact: true }).click();
    await chooseSelect(page, page.locator('#initial_turno'), '0');
    await page.locator('#initial_starts_on').fill('2026-01-01');
    await page.locator('#reason').fill('Integração concluída para teste');
    await page.getByRole('button', { name: 'Salvar dados do colaborador' }).click();
    await page.locator('.employees-overview').getByText('Ativo', { exact: true }).waitFor();
    await page.locator('.employees-overview').getByText('22/12/2025', { exact: true }).waitFor();
    assert.equal(await page.locator('.app-page-actions a[href*=escala-folgas]').count(), 0);
    assert.equal(await page.locator('#promotion_cargo').inputValue(), 'operador', 'A shift change should retain the current cargo');
    await chooseSelect(page, page.locator('#promotion_turno'), '1');
    await page.locator('#promotion_starts_on').fill('2026-08-01');
    await page.locator('#promotion_reason').fill('Troca de turno para teste');
    await page.getByRole('button', { name: 'Registrar movimentação', exact: true }).click();
    await page.locator('.employees-timeline').getByText('Turno B', { exact: false }).first().waitFor();
    assert.equal(await page.locator('.employees-overview strong').first().innerText(), 'Operador');
    await chooseSelect(page, page.locator('#promotion_sector'), 'du');
    await chooseSelect(page, page.locator('#promotion_cargo'), 'van');
    await page.locator('#promotion_promax').fill(registration);
    await page.locator('#promotion_starts_on').fill('2026-09-01');
    await page.locator('#promotion_reason').fill('Transferência DU para teste');
    await page.getByRole('button', { name: 'Registrar movimentação', exact: true }).click();
    await page.locator('.employees-overview').getByText('Motorista de van', { exact: true }).waitFor();
    assert.equal(await page.locator('.app-page-actions a[href*=escala-folgas]').count(), 1);
    await page.getByRole('link', { name: 'Editar dados', exact: true }).click();
    await page.locator('#employee_nome').fill('Pessoa corrigida no navegador');
    await page.locator('#reason').fill('Conferência dos dados');
    await page.getByRole('button', { name: 'Salvar dados do colaborador' }).click();
    await page.getByRole('heading', { name: 'Pessoa corrigida no navegador', exact: true }).waitFor();
    fs.mkdirSync('tmp/browser', { recursive: true });
    await page.screenshot({ path: 'tmp/browser/employees-desktop.png', fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: 'tmp/browser/employees-mobile.png', fullPage: true });
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'Ficha should fit the mobile viewport');
    await page.goto(`${base}/rh/colaboradores?employee_sector=du&q=${registration}`);
    await page.getByText('Pessoa corrigida no navegador', { exact: true }).waitFor();
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'List should fit the mobile viewport');
    const publicPage = await browser.newPage();
    await publicPage.goto(`${base}/chat-variaveis`);
    assert.equal(await publicPage.locator('select[name=profile]').count(), 0);
    await publicPage.locator('input[name=registration]').fill(registration);
    await publicPage.locator('input[name=birth_date]').fill('1990-01-01');
    await publicPage.getByRole('button', { name: 'Entrar na consulta' }).click();
    await publicPage.locator('.public-variable-chat-session').getByText('Pessoa corrigida no navegador', { exact: true }).waitFor();
    assert.deepEqual(errors, []);
    console.log('PASS: DU/AZ fields, optional function start during integration, employment dates, dated shift/sector changes, identity editing, mobile layout and public identification');
  } finally {
    await browser.close();
    // Remove only this run's synthetic identity, including audit rows. Without
    // this cleanup Rails fixtures would remove its test user while leaving FKs.
    execFileSync('bin/rails', ['runner', '-e', 'test', `
      person = Employee.find_by(matricula: ENV.fetch('EMPLOYEES_BROWSER_REGISTRATION'))
      if person
        Employee.transaction do
          [EmployeeCareerEvent, EmployeeRole, EmployeeName, Driver, Ajudante, Operator, AzAjudante].each do |model|
            model.where(employee_id: person.id).delete_all
          end
          person.delete
        end
      end
    `], { env: { ...process.env, EMPLOYEES_BROWSER_REGISTRATION: registration }, stdio: 'pipe' });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
