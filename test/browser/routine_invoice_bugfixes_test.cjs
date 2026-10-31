// RAILS_ENV=test bin/rails server -p 4318
// node test/browser/routine_invoice_bugfixes_test.cjs
const { chromium } = require('playwright');
const { execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');
const rails = code => execFileSync('bin/rails', ['runner', code], {
  env: { ...process.env, RAILS_ENV: 'test' }, encoding: 'utf8'
}).trim();
const token = `browser-bugfix-${Date.now()}`;

(async () => {
  const data = JSON.parse(rails(`
    abort unless Rails.env.test?
    user = User.create!(name: "Comprador ${token}", email: "${token}@example.test", password: "password123", role: :admin, sector: :fleet)
    other = User.create!(name: "Outro ${token}", email: "other-${token}@example.test", password: "password123", sector: :du)
    supplier = Supplier.create!(name: "${token}", cnpj: SecureRandom.random_number(10**14).to_s, supplier_type: "other")
    category = BudgetCategory.create!(name: "${token}", sector: :frota)
    center = CostCenter.create!(name: "${token}", sector: :frota)
    duplicate = Invoice.create!(code: "${token}-duplicate", supplier: supplier, purchaser: user, budget_category: category,
      date_issued: Date.new(2026, 10, 31), due_date: Date.new(2026, 11, 10))
    plan = ActionPlan.create!(name: "${token}", user: user, sector: :fleet)
    template = RoutineTemplate.create!(name: "${token}", sector: :fleet, action_plan: plan)
    routine = Routine.create!(routine_template: template, action_plan: plan, created_by: user, title: "${token}",
      period_start: Date.new(2026, 10, 1), period_end: Date.new(2026, 10, 31), status: :open)
    puts({ user: user.id, other: other.id, supplier: supplier.id, category: category.id, center: center.id,
      duplicate: duplicate.id, plan: plan.id, template: template.id, routine: routine.id }.to_json)
  `));
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, locale: 'pt-BR' });
    page.setDefaultTimeout(15000);
    const base = process.env.BASE_URL || 'http://127.0.0.1:4318';
    const select = async (locator, choice) => {
      const menu = await locator.evaluate((element, value) => {
        const option = [...element.options].find(option => option.value === String(value));
        element.tomselect.open();
        return { id: element.tomselect.dropdown_content.id, label: option.textContent.trim() };
      }, choice);
      await page.locator(`[id="${menu.id}"]`).getByRole('option', { name: menu.label, exact: true }).click();
    };
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('dialog', dialog => dialog.accept());
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill(`${token}@example.test`);
    await page.locator('#user_password').fill('password123');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));

    // Routine navigation preserves the list or the exact originating plan view.
    await page.goto(`${base}/routines`);
    const routineRow = () => page.locator('tr').filter({ hasText: token });
    await routineRow().getByRole('link', { name: 'Abrir', exact: true }).click();
    await page.waitForURL(url => url.pathname === `/routines/${data.routine}`);
    assert.equal(await page.locator('.routine-show-header a').first().getAttribute('href'), '/routines');
    await page.reload();
    await page.locator('.routine-show-header a[href="/routines"]').click();
    await page.waitForURL(url => url.pathname === '/routines');
    const planPath = `/action_plans/${data.plan}?view=gerots&year=2026`;
    await page.goto(`${base}${planPath}`);
    await page.locator('.plan-gerots__record').filter({ hasText: token }).click();
    await page.waitForURL(url => url.pathname === `/routines/${data.routine}`);
    assert.equal(await page.locator('.routine-show-header a').first().getAttribute('href'), planPath);
    await page.locator('.routine-show-header a').first().click();
    await page.waitForURL(`${base}${planPath}`);
    await page.goto(`${base}/routines`);
    await routineRow().getByRole('button', { name: 'Arquivar rotina', exact: true }).click();
    await routineRow().waitFor({ state: 'detached' });
    assert.equal(new URL(page.url()).pathname, '/routines');

    await page.goto(`${base}/invoices/new`);
    await page.waitForFunction(() => document.querySelector('form[data-controller="invoice-form"]')?.noValidate);
    const form = page.locator('form[data-controller="invoice-form"]');
    let posts = 0;
    page.on('request', request => { if (request.method() === 'POST' && new URL(request.url()).pathname === '/invoices') posts++; });
    const files = () => page.locator('#invoice_documents').evaluate(element => [...element.files].map(file => file.name));
    await page.locator('#invoice_documents').setInputFiles([
      { name: 'nota.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4 nota') },
      { name: 'boleto.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4 boleto') }
    ]);
    await page.locator('[data-documents-target="list"] .type-btn').nth(1).click();
    await form.locator('[type=submit]').click();
    assert.equal(posts, 0, 'invalid form must not send files to the server');
    assert(await form.locator('[aria-invalid="true"]').count() >= 8);
    assert.equal(await form.locator('.alert').count(), 0, 'validation must not add a banner to the form');
    assert.deepEqual(await files(), ['nota.pdf', 'boleto.pdf']);

    await page.locator('#invoice_code').fill(`${token}-duplicate`);
    await select(page.locator('#invoice_supplier_id'), data.supplier);
    await select(page.locator('#invoice_budget_category_id'), data.category);
    await select(page.locator('#invoice_purchaser_id'), data.other);
    await page.locator('#invoice_date_issued').fill('2026-10-31');
    await page.locator('#invoice_due_date').fill('2026-11-10');
    const rows = () => page.locator('[data-invoice-numbers-target="container"] .nested-fields');
    await rows().first().locator('input[name$="[number]"]').fill('123');
    await rows().first().locator('input[name$="[amount]"]').fill('1.234,56');
    await select(rows().first().locator('select'), data.center);
    await form.locator('[type=submit]').click();
    assert.equal(posts, 0);
    assert.match(await page.locator('#invoice_purchaser_id').locator('..').textContent(), /setor FROTA/);
    await select(page.locator('#invoice_purchaser_id'), data.user);

    await page.getByTitle('Adicionar NF', { exact: true }).click();
    await form.locator('[type=submit]').click();
    assert.equal(posts, 0);
    assert.equal(await rows().nth(1).locator('input[required][aria-invalid="true"], select[required][aria-invalid="true"]').count(), 2);
    await rows().nth(1).getByTitle('Remover NF', { exact: true }).click();
    assert.equal(await rows().count(), 1);

    const duplicate = page.waitForResponse(response => response.request().method() === 'POST' && new URL(response.url()).pathname === '/invoices');
    await form.locator('[type=submit]').click();
    assert.equal((await duplicate).status(), 422);
    await page.locator('#invoice_code[aria-invalid="true"]').waitFor();
    assert.equal(await form.locator('.alert').count(), 0);
    assert.deepEqual(await files(), ['nota.pdf', 'boleto.pdf']);
    assert.equal(await rows().first().locator('input[name$="[amount]"]').inputValue(), '1.234,56');
    assert.equal(await page.locator('[name="document_types[]"]').nth(1).inputValue(), 'boleto');

    // A connection failure also leaves the same inputs and attachments intact.
    await page.locator('#invoice_code').fill(`${token}-new`);
    await page.route('**/invoices', route => route.abort('failed'));
    await form.locator('[type=submit]').click();
    await page.locator('#flash-container [role=status]').filter({ hasText: 'Não foi possível salvar' }).waitFor();
    assert.deepEqual(await files(), ['nota.pdf', 'boleto.pdf']);
    await page.unroute('**/invoices');
    await form.locator('[type=submit]').click();
    await page.waitForURL(url => /^\/invoices\/\d+$/.test(url.pathname));
    const createdId = Number(new URL(page.url()).pathname.split('/').pop());
    const saved = JSON.parse(rails(`invoice = Invoice.find(${createdId}); puts({ total: invoice.total.to_s, files: invoice.documents.map { |document| [document.filename.to_s, document.blob.metadata["document_type"]] } }.to_json)`));
    assert.equal(saved.total, '1234.56');
    assert.deepEqual(saved.files.sort(), [['boleto.pdf', 'boleto'], ['nota.pdf', 'nf']]);

    // Edit failures preserve both stored files and the new local selection.
    await page.goto(`${base}/invoices/${createdId}/edit`);
    await page.waitForFunction(() => document.querySelector('form[data-controller="invoice-form"]')?.noValidate);
    await page.locator('#invoice_documents').setInputFiles({ name: 'extra.pdf', mimeType: 'application/pdf', buffer: Buffer.from('%PDF-1.4 extra') });
    await page.locator('#invoice_code').fill(`${token}-duplicate`);
    await page.locator('form[data-controller="invoice-form"] [type=submit]').click();
    await page.locator('#invoice_code[aria-invalid="true"]').waitFor();
    assert.deepEqual(await files(), ['extra.pdf']);
    await page.locator('#invoice_code').fill(`${token}-updated`);
    await page.locator('form[data-controller="invoice-form"] [type=submit]').click();
    await page.waitForURL(url => url.pathname === `/invoices/${createdId}`);
    assert.equal(rails(`puts Invoice.find(${createdId}).documents.count`), '3');
    assert.deepEqual(errors, []);
    console.log('PASS: routine archive and navigation; client validation, sector and nested rows; duplicate-code and network failures retain files; create/edit retries preserve uploads and metadata.');
  } finally {
    await browser.close();
    rails(`
      abort unless Rails.env.test?
      Invoice.where(supplier_id: ${data.supplier}).find_each(&:destroy!)
      Routine.find(${data.routine}).destroy!
      RoutineTemplate.find(${data.template}).destroy!
      ActionPlan.find(${data.plan}).destroy!
      Supplier.find(${data.supplier}).destroy!
      BudgetCategory.find(${data.category}).destroy!
      CostCenter.find(${data.center}).destroy!
      User.where(id: [${data.user}, ${data.other}]).destroy_all
    `);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
