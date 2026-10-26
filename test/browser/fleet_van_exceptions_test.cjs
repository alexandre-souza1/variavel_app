// RAILS_ENV=test bin/rails server -p 4318
// node test/browser/fleet_van_exceptions_test.cjs
const { chromium } = require('playwright');
const { execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');

const rails = code => execFileSync('bin/rails', ['runner', code], {
  env: { ...process.env, RAILS_ENV: 'test' }, encoding: 'utf8'
}).trim();

(async () => {
  const data = JSON.parse(rails(`
    abort unless Rails.env.test?
    ActiveRecord::Base.transaction do
      user = User.create!(email: "browser-van-exception@example.test", password: "password123", role: :admin, sector: :fleet)
      availability = FleetAvailability.create!(date: Date.new(2090, 10, 24), agreed_quantity: 1,
        special_routes: { "van" => 1 }, user: user)
      plates = [["BVE1A23", "Caminhão", "TOCO"], ["BVE2A34", "Van", "VAN"]].map do |number, type, profile|
        Plate.create!(placa: number, setor: "ROTA", tipo: type, perfil: profile)
      end
      items = plates.each_with_index.map do |plate, index|
        availability.fleet_availability_items.create!(plate: plate, status: :exchange, position: index)
      end
      puts({ user: user.id, availability: availability.id, plates: plates.map(&:id), items: items.map(&:id) }.to_json)
    end
  `));
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, locale: 'pt-BR' });
    const base = process.env.BASE_URL || 'http://127.0.0.1:4318';
    const errors = [];
    const dialogs = [];
    const patches = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('request', request => {
      if (request.method() === 'PATCH' && request.url().includes('/fleet_availability_items/')) patches.push(request.postDataJSON());
    });
    const answer = accept => page.once('dialog', async dialog => {
      dialogs.push(dialog.message());
      await (accept ? dialog.accept() : dialog.dismiss());
    });
    const response = () => page.waitForResponse(r => r.request().method() === 'PATCH' && r.url().includes('/fleet_availability_items/'));
    const item = page.locator(`#fleet_availability_item_${data.items[0]}`);
    const van = page.locator(`#fleet_availability_item_${data.items[1]}`);
    const target = page.locator('#special-route-van-list');
    const select = async locator => locator.locator('.fleet-vehicle-card__profile').click();

    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('browser-van-exception@example.test');
    await page.locator('#user_password').fill('password123');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/fleet_availabilities/${data.availability}`);
    await page.waitForFunction(() => window.Stimulus?.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller~=fleet-availability]'), 'fleet-availability'));

    // Cancel on mobile leaves the plate selected in the deposit without a PATCH.
    await select(item);
    answer(false);
    await target.click();
    assert.equal(patches.length, 0);
    assert.equal(await item.locator('..').getAttribute('id'), 'exchange-list');
    assert.match(dialogs[0], /BVE1A23.*perfil correto.*TOCO.*exceção/);

    answer(true);
    let saved = response();
    await target.click();
    assert.equal((await saved).status(), 200);
    await page.waitForFunction(id => document.getElementById(id).dataset.status === 'special_route', `fleet_availability_item_${data.items[0]}`);
    assert.equal(patches.at(-1).fleet_availability_item.confirm_non_van_plate, true);
    await page.reload();
    assert.equal(await item.locator('..').getAttribute('id'), 'special-route-van-list');

    // Editing the exception does not ask for confirmation again.
    await item.locator('[data-observation-edit]').click();
    await page.locator('#plateObservationText').fill('Exceção para esta operação');
    saved = response();
    await page.locator('#confirmPlateObservation').click();
    assert.equal((await saved).status(), 200);
    await page.locator('#plateObservationModal').waitFor({ state: 'hidden' });
    assert.equal(dialogs.length, 2);

    // A full Van list stays full, including on mobile.
    await select(van);
    await target.click({ position: { x: 1, y: 1 } });
    assert.equal(patches.length, 2);
    await page.locator('[data-limit-alert]').waitFor({ state: 'visible' });

    await select(item);
    saved = response();
    await page.locator('button[data-mobile-destination=exchange]').click();
    assert.equal((await saved).status(), 200);
    await page.waitForFunction(id => document.getElementById(id).dataset.status === 'exchange', `fleet_availability_item_${data.items[0]}`);

    // Exercise the actual Sortable pointer interaction on desktop.
    await page.setViewportSize({ width: 1920, height: 1400 });
    await page.reload();
    const drag = async () => {
      await item.scrollIntoViewIfNeeded();
      const source = await item.locator('.fleet-vehicle-card__profile').boundingBox();
      const destination = await target.boundingBox();
      await page.mouse.move(source.x + source.width / 2, source.y + source.height / 2);
      await page.mouse.down();
      await page.mouse.move(source.x + source.width / 2 + 10, source.y + source.height / 2, { steps: 5 });
      await page.mouse.move(destination.x + destination.width / 2, destination.y + destination.height / 2, { steps: 25 });
      await page.mouse.up();
    };
    answer(false);
    await drag();
    assert.equal(dialogs.length, 3);
    assert.equal(await item.locator('..').getAttribute('id'), 'exchange-list');
    assert.equal(patches.length, 3);

    await page.reload();
    await page.waitForFunction(() => window.Stimulus?.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller~=fleet-availability]'), 'fleet-availability'));
    answer(true);
    saved = response();
    await drag();
    assert.equal((await saved).status(), 200);
    await page.reload();
    assert.equal(await item.locator('..').getAttribute('id'), 'special-route-van-list');
    assert.equal(patches.at(-1).fleet_availability_item.confirm_non_van_plate, true);
    assert.match(await item.locator('[data-observation-display]').textContent(), /Exceção para esta operação/);
    assert.deepEqual(errors, []);
    console.log('PASS: mobile and desktop cancellation/confirmation, persistence, observation editing and full Van quota');
  } finally {
    await browser.close();
    rails(`
      abort unless Rails.env.test?
      FleetAvailability.find(${data.availability}).destroy_without_lock_version!
      Plate.where(id: ${JSON.stringify(data.plates)}).destroy_all
      User.find(${data.user}).destroy!
    `);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
