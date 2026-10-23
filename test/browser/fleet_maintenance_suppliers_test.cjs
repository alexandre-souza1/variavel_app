// Run against a Rails server in test mode:
// RAILS_ENV=test bin/rails server -p 4318
// node test/browser/fleet_maintenance_suppliers_test.cjs
const { chromium } = require('playwright');
const { execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');
const chooseSelect = require('./helpers/select.cjs');

const rails = code => execFileSync('bin/rails', ['runner', code], {
  env: { ...process.env, RAILS_ENV: 'test' }, encoding: 'utf8'
}).trim();

(async () => {
  const data = JSON.parse(rails(`
    abort "Use somente o banco de testes" unless Rails.env.test?
    ActiveRecord::Base.transaction do
      user = User.create!(email: "browser-fleet-suppliers@example.test", password: "password123", role: :admin, sector: :fleet)
      availability = FleetAvailability.create!(date: Date.new(2090, 10, 23), agreed_quantity: 1, user: user)
      plate = Plate.create!(placa: "BFS1A23", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")
      item = availability.fleet_availability_items.create!(plate: plate, status: :exchange, position: 0)
      extra_plates = ["BFS2A34", "BFS3A45"].each_with_index.map do |number, i|
        extra = Plate.create!(placa: number, setor: "ROTA", tipo: "Caminhão", perfil: "TRUCK")
        availability.fleet_availability_items.create!(plate: extra, status: :unavailable, position: i + 1,
          reason: :maintenance, observation: i.zero? ? nil : "Reparo de portas e vazamento de óleo no motor")
        extra.id
      end
      suppliers = %w[workshop tire_shop store fuel_station contractor other].each_with_index.map do |type, i|
        name = { "workshop" => "Oficina Central", "tire_shop" => "Borracharia São Lucas" }[type] || "Fornecedor navegador #{type}"
        maintenance = %w[workshop tire_shop].include?(type)
        Supplier.create!(name: maintenance ? "Razão social #{type} LTDA" : name, fantasy_name: maintenance ? name : nil,
          cnpj: "9876543200020#{i}", supplier_type: type)
      end
      puts({ user: user.id, availability: availability.id, plates: [plate.id, *extra_plates], item: item.id, suppliers: suppliers.map(&:id) }.to_json)
    end
  `));
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, locale: 'pt-BR' });
    const base = process.env.BASE_URL || 'http://127.0.0.1:4318';
    const errors = [];
    page.on('pageerror', error => { errors.push(error.message); console.error(error.message); });
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('browser-fleet-suppliers@example.test');
    await page.locator('#user_password').fill('password123');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/fleet_availabilities/${data.availability}`);
    await page.waitForFunction(() => document.querySelector('#unavailableSupplier')?.tomselect);
    const item = page.locator(`#fleet_availability_item_${data.item}`);
    const modal = page.locator('#unavailableModal');
    const supplier = page.locator('#unavailableSupplier');
    const confirm = async () => {
      const response = page.waitForResponse(response => response.url().endsWith(`/fleet_availability_items/${data.item}`) && response.request().method() === 'PATCH');
      await page.locator('#confirmUnavailable').click();
      assert.equal((await response).status(), 200);
      await modal.waitFor({ state: 'hidden' });
    };

    // Cancel leaves the vehicle in the deposit.
    await item.locator('.fleet-vehicle-card__profile').click();
    await page.locator('button[data-mobile-destination=unavailable]').click();
    await modal.waitFor({ state: 'visible' });
    await modal.getByRole('button', { name: 'Cancelar', exact: true }).click();
    await modal.waitFor({ state: 'hidden' });
    assert.equal(await item.getAttribute('data-status'), 'exchange');

    await item.locator('.fleet-vehicle-card__profile').click();
    await page.locator('button[data-mobile-destination=unavailable]').click();
    await modal.waitFor({ state: 'visible' });
    assert.deepEqual(await supplier.locator('option').evaluateAll(options => options.map(option => option.value).sort()), ['', ...data.suppliers.slice(0, 2).map(String)].sort());
    await chooseSelect(page, supplier, String(data.suppliers[0]));
    await page.locator('#unavailableObservation').fill('Aguardando peças');
    await confirm();
    assert.match(await item.locator('[data-supplier-label]').textContent(), /Oficina Central/);

    // An observation edit must preserve the assigned supplier.
    await item.locator('[data-unavailable-edit]').click();
    await modal.waitFor({ state: 'visible' });
    await page.locator('#unavailableObservation').fill('Peças chegaram');
    await confirm();

    // Edit on desktop, then reload to verify persistence.
    await page.setViewportSize({ width: 1440, height: 1000 });
    await item.locator('[data-unavailable-edit]').click();
    await modal.waitFor({ state: 'visible' });
    assert.equal(await supplier.inputValue(), String(data.suppliers[0]));
    assert.equal(await page.locator('#unavailableObservation').inputValue(), 'Peças chegaram');
    await chooseSelect(page, supplier, String(data.suppliers[1]));
    await confirm();
    await page.reload();
    assert.match(await item.locator('[data-supplier-label]').textContent(), /Borracharia São Lucas/);
    if (process.env.SCREENSHOT_PATH) {
      await page.evaluate(() => document.documentElement.setAttribute('data-bs-theme', 'dark'));
      await page.locator('.fleet-board-card--danger').screenshot({ path: process.env.SCREENSHOT_PATH.replace('.png', '.narrow.png') });
      await page.setViewportSize({ width: 1920, height: 1000 });
      await page.locator('.fleet-board-card--danger').screenshot({ path: process.env.SCREENSHOT_PATH });
    }

    // Mobile return clears the supplier from the vehicle.
    await page.setViewportSize({ width: 390, height: 844 });
    await item.locator('.fleet-vehicle-card__profile').click();
    const returned = page.waitForResponse(response => response.url().endsWith(`/fleet_availability_items/${data.item}`));
    await page.locator('button[data-mobile-destination=exchange]').click();
    assert.equal((await returned).status(), 200);
    await item.locator('[data-supplier-display]').waitFor({ state: 'hidden' });
    assert.equal(await item.getAttribute('data-supplier-id'), '');
    assert.deepEqual(errors, []);
    console.log('PASS: cancel, maintenance suppliers, observation preservation, desktop editing, reload and mobile return');
  } finally {
    await browser.close();
    rails(`
      abort unless Rails.env.test?
      FleetAvailability.find(${data.availability}).destroy_without_lock_version!
      Plate.where(id: ${JSON.stringify(data.plates)}).destroy_all
      Supplier.where(id: ${JSON.stringify(data.suppliers)}).destroy_all
      User.find(${data.user}).destroy!
    `);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
