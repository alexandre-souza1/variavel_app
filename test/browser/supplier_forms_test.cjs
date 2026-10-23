// RAILS_ENV=test bin/rails server -p 4318
// node test/browser/supplier_forms_test.cjs
const { chromium } = require('playwright');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const chooseSelect = require('./helpers/select.cjs');
const rails = code => execFileSync('bin/rails', ['runner', code], { env: { ...process.env, RAILS_ENV: 'test' }, encoding: 'utf8' }).trim();
const initialCnpj = '98765432000301', newCnpj = '98765432000302';
const company = { name: 'Oficina São Lucas Ltda.', fantasy_name: 'Oficina do Lucas', situation: 'ATIVA', email: 'contato@oficinalucas.example', phone: '(45) 3025-1234', street: 'Avenida Brasil', number: '1250', complement: 'Sala 02', neighborhood: 'Centro', city: 'Foz do Iguaçu', state: 'PR', zip_code: '85851000' };

(async () => {
  const data = JSON.parse(rails(`
    abort unless Rails.env.test?
    ActiveRecord::Base.transaction do
      user = User.create!(email: "browser-supplier-forms@example.test", password: "password123", role: :admin, color_theme: "retro_orange")
      attributes = JSON.parse(%q|${JSON.stringify(company)}|).symbolize_keys
      supplier = Supplier.create!(attributes.merge(cnpj: "${initialCnpj}", supplier_type: "workshop"))
      puts({ user: user.id, supplier: supplier.id }.to_json)
    end
  `));
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, locale: 'pt-BR' });
    const base = process.env.BASE_URL || 'http://127.0.0.1:4318';
    const errors = [], requests = [];
    page.on('pageerror', error => { errors.push(error.message); console.error(error.message); });
    await page.addInitScript(() => { localStorage.setItem('theme', 'dark'); localStorage.setItem('colorTheme', 'retro_orange'); });
    await page.route('**/suppliers/search_cnpj?*', async route => {
      requests.push(new URL(route.request().url()).searchParams.get('cnpj'));
      await route.fulfill({ json: company });
    });
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('browser-supplier-forms@example.test');
    await page.locator('#user_password').fill('password123');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/suppliers`);
    const drawer = page.locator('#supplier-drawer');
    const openNew = async () => {
      await page.locator('a[href="/suppliers/new"]').click();
      await page.waitForFunction(() => document.querySelector('#supplier-drawer.show #supplier_supplier_type')?.tomselect);
    };
    const close = async () => {
      await drawer.getByRole('button', { name: 'Fechar formulário', exact: true }).click();
      await drawer.waitFor({ state: 'hidden' });
      await page.waitForFunction(() => !document.querySelector('.offcanvas-backdrop'));
      assert.notEqual(await page.locator('body').evaluate(element => getComputedStyle(element).overflowY), 'hidden');
    };
    const lookup = async cnpj => {
      await page.locator('#supplier_cnpj').fill(cnpj);
      await page.locator('#supplier_cnpj').press('Enter');
      await page.waitForFunction(() => document.querySelector('[data-supplier-target=status]')?.dataset.state === 'success');
      assert.equal(await page.locator('#supplier_name').inputValue(), company.name);
      assert.equal(await page.locator('#supplier_fantasy_name').inputValue(), company.fantasy_name);
    };
    const save = async label => {
      await drawer.getByRole('button', { name: label, exact: true }).click();
      await page.waitForFunction(() => !document.querySelector('.offcanvas-backdrop') && !document.querySelector('#supplier-drawer.show') && !document.querySelector('[data-supplier-saved-url]'));
      assert.equal(new URL(page.url()).pathname, '/suppliers');
    };
    fs.mkdirSync('tmp/browser', { recursive: true });

    // The index retains the same geometry while the drawer is open.
    const before = await page.locator('.admin-catalog-page').boundingBox();
    await openNew();
    const after = await page.locator('.admin-catalog-page').boundingBox();
    assert(Math.abs(before.x - after.x) < 1 && Math.abs(before.width - after.width) < 1, 'index width must stay stable');
    assert.equal(await page.locator('#supplier_name').getAttribute('placeholder'), '—');
    await drawer.screenshot({ path: 'tmp/browser/supplier-new-dark.png' });
    await page.keyboard.press('Escape');
    await drawer.waitFor({ state: 'hidden' });
    await openNew();
    await lookup(initialCnpj);
    await chooseSelect(page, page.locator('#supplier_supplier_type'), 'tire_shop');

    // Invalid submissions keep the form and user selection inside the drawer.
    const invalid = page.waitForResponse(response => response.request().method() === 'POST' && new URL(response.url()).pathname === '/suppliers');
    await drawer.getByRole('button', { name: 'Cadastrar fornecedor', exact: true }).click();
    assert.equal((await invalid).status(), 422);
    await drawer.locator('[role=alert]').waitFor();
    assert.equal(await page.locator('#supplier_supplier_type').inputValue(), 'tire_shop');
    assert.equal(await page.locator('#supplier_name').inputValue(), company.name);
    await lookup(newCnpj);
    await save('Cadastrar fornecedor');
    const created = page.locator('tr').filter({ hasText: newCnpj });
    assert.match(await created.textContent(), /Borracharia/);
    await created.getByTitle('Editar fornecedor', { exact: true }).click();
    await page.waitForFunction(() => document.querySelector('#supplier-drawer.show #supplier_supplier_type')?.tomselect);
    assert.equal(await page.locator('#supplier_name').inputValue(), company.name);
    assert.equal(await page.locator('#supplier-drawer-title').textContent(), 'Editar fornecedor');
    for (const theme of ['dark', 'light']) {
      await page.evaluate(theme => document.documentElement.dataset.bsTheme = theme, theme);
      await drawer.screenshot({ path: `tmp/browser/supplier-edit-${theme}.png` });
    }
    assert(await page.locator('#supplier_name').evaluate(element => element.readOnly));
    await drawer.getByRole('button', { name: 'Editar dados', exact: true }).click();
    assert(await drawer.locator('[data-supplier-target~="editableField"]').evaluateAll(fields => fields.length === 12 && fields.every(field => !field.readOnly)));
    await page.locator('#supplier_name').fill('Oficina São Lucas — nome corrigido');
    await page.locator('#supplier_fantasy_name').fill('Oficina do Lucas e Filhos');
    await page.locator('#supplier_email').fill('financeiro@oficinalucas.example');
    await page.locator('#supplier_street').fill('Avenida Brasil, acesso lateral');
    await drawer.getByRole('button', { name: 'Concluir edição', exact: true }).click();
    assert(await page.locator('#supplier_name').evaluate(element => element.readOnly));
    await chooseSelect(page, page.locator('#supplier_supplier_type'), 'contractor');
    await save('Salvar alterações');
    assert.match(await page.locator('tr').filter({ hasText: newCnpj }).textContent(), /Contratadas/);
    await page.locator('tr').filter({ hasText: newCnpj }).getByTitle('Editar fornecedor', { exact: true }).click();
    await page.waitForFunction(() => document.querySelector('#supplier-drawer.show #supplier_supplier_type')?.tomselect);
    assert.equal(await page.locator('#supplier_name').inputValue(), 'Oficina São Lucas — nome corrigido');
    assert.equal(await page.locator('#supplier_fantasy_name').inputValue(), 'Oficina do Lucas e Filhos');
    assert.equal(await page.locator('#supplier_email').inputValue(), 'financeiro@oficinalucas.example');
    assert.equal(await page.locator('#supplier_street').inputValue(), 'Avenida Brasil, acesso lateral');
    await close();

    // Direct links still show the index and automatically open the panel.
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${base}/suppliers/${data.supplier}/edit`);
    await page.waitForFunction(() => document.querySelector('#supplier-drawer.show #supplier_supplier_type')?.tomselect);
    const footer = drawer.locator('.supplier-form__footer');
    const footerBox = await footer.boundingBox();
    assert(footerBox.y + footerBox.height <= 845, 'actions must remain inside the mobile viewport');
    assert(await drawer.locator('.supplier-form__body').evaluate(element => element.scrollHeight > element.clientHeight), 'form must scroll internally');
    assert(await drawer.evaluate(element => element.scrollWidth <= element.clientWidth), 'no horizontal overflow');
    await drawer.screenshot({ path: 'tmp/browser/supplier-edit-mobile.png' });
    await close();
    assert.equal(new URL(page.url()).pathname, '/suppliers');
    await openNew();
    await chooseSelect(page, page.locator('#supplier_supplier_type'), 'fuel_station');
    await lookup(newCnpj);
    await drawer.getByRole('button', { name: 'Limpar campos', exact: true }).click();
    assert.equal(await page.locator('#supplier_cnpj').inputValue(), '');
    assert.equal(await page.locator('#supplier_name').inputValue(), '');
    assert.equal(await page.locator('#supplier_fantasy_name').inputValue(), '');
    assert.equal(await page.locator('#supplier_supplier_type').inputValue(), 'fuel_station');
    await close();
    await openNew();
    await page.evaluate(() => window.Turbo.visit('/suppliers'));
    await page.waitForFunction(() => !document.querySelector('#supplier-drawer.show') && !document.querySelector('.offcanvas-backdrop') && !document.querySelector('#supplier-form-drawer form'));
    assert.deepEqual(errors, []);
    assert.equal(requests.filter(cnpj => cnpj === initialCnpj).length, 1, 'lookup must not repeat on blur');
    console.log('PASS: stable width, offcanvas new/edit, lookup, validation, manual corrections persisted, direct links, internal scrolling and mobile actions');
  } catch (error) {
    await browser.contexts()[0]?.pages()[0]?.screenshot({ path: 'tmp/browser/supplier-form-error.png', fullPage: true });
    throw error;
  } finally {
    await browser.close();
    rails(`abort unless Rails.env.test?; Supplier.where(cnpj: ["${initialCnpj}", "${newCnpj}"]).destroy_all; User.find(${data.user}).destroy!`);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
