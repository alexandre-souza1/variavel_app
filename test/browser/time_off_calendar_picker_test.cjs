// Prepare the test database with test/browser/time_off_setup.rb and start Rails
// in test mode on port 4318 (or set BASE_URL) before running this check.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch();
  try {
    fs.mkdirSync('tmp/time_off', { recursive: true });
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, timezoneId: 'America/Sao_Paulo' });
    const base = process.env.BASE_URL || 'http://127.0.0.1:4318';
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('user_one@example.com');
    await page.locator('#user_password').fill('password');
    await page.locator('input[type="submit"]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));

    const open = async mode => {
      await page.waitForFunction(() => window.Stimulus?.getControllerForElementAndIdentifier(document.querySelector('.calendar-picker'), 'calendar-picker'));
      await page.getByRole('button', { name: mode === 'month' ? 'Escolher mês' : 'Escolher dia', exact: true }).click();
      const panel = page.locator(`#time-off-${mode}-picker`);
      await panel.waitFor({ state: 'visible' });
      return panel;
    };
    const selected = async date => {
      await page.waitForURL(url => url.searchParams.get('date') === date);
      await page.locator('.time-off-date-trigger').waitFor();
    };
    const insideViewport = panel => panel.evaluate(element => {
      const box = element.getBoundingClientRect();
      return box.left >= 0 && box.right <= innerWidth && box.top >= 0 && box.bottom <= innerHeight;
    });

    await page.goto(`${base}/escala-folgas?tab=day&date=2026-10-02&role=driver&group=A&name=ADAIR&per_page=24&calendar_period=month`);
    let panel = await open('day');
    assert.equal(await panel.locator('button[data-date]').count(), 31);
    assert.equal(await panel.locator('[aria-pressed="true"]').getAttribute('data-date'), '2026-10-02');
    assert.equal(await panel.locator('[aria-pressed="true"]').evaluate(e => e === document.activeElement), true);
    await panel.press('Escape');
    assert.equal(await panel.isVisible(), false);
    assert.equal(await page.getByRole('button', { name: 'Escolher dia', exact: true }).evaluate(e => e === document.activeElement), true);
    panel = await open('day');
    await panel.locator('[aria-pressed="true"]').press('ArrowRight');
    await page.keyboard.press('Enter');
    await selected('2026-10-03');
    let url = new URL(page.url());
    for (const [key, value] of Object.entries({ month: '2026-10', role: 'driver', group: 'A', name: 'ADAIR', per_page: '24', calendar_period: 'month' })) {
      assert.equal(url.searchParams.get(key), value, `${key} preserved after choosing a day`);
    }

    await page.goto(`${base}/escala-folgas?tab=day&date=2026-12-31`);
    panel = await open('day');
    await panel.getByRole('button', { name: 'Próximo mês', exact: true }).click();
    assert.match(await panel.locator('[data-calendar-picker-target="heading"]').innerText(), /janeiro de 2027/i);
    await panel.locator('[data-date="2027-01-01"]').click();
    await selected('2027-01-01');
    assert.equal(new URL(page.url()).searchParams.get('month'), '2027-01');

    await page.goto(`${base}/escala-folgas?tab=day&date=2028-02-10`);
    panel = await open('day');
    assert.equal(await panel.locator('button[data-date]').count(), 29, 'leap-year February');
    await panel.getByRole('button', { name: 'Cancelar', exact: true }).click();
    assert.equal(await panel.isVisible(), false);
    assert.equal(new URL(page.url()).searchParams.get('date'), '2028-02-10');

    await page.goto(`${base}/escala-folgas?tab=calendar&date=2026-10-02&month=2026-10&calendar_period=2026-10-08&role=helper&group=A&name=PATRICK&per_page=48`);
    panel = await open('month');
    assert.equal(await panel.locator('button[data-date]').count(), 12);
    assert.equal(await panel.locator('[aria-pressed="true"]').getAttribute('data-date'), '2026-10-01');
    await panel.getByRole('button', { name: 'Próximo ano', exact: true }).click();
    await panel.getByRole('button', { name: 'março de 2027', exact: true }).click();
    await selected('2027-03-01');
    url = new URL(page.url());
    for (const [key, value] of Object.entries({ month: '2027-03', calendar_period: '2027-03-01', page: '1', role: 'helper', group: 'A', name: 'PATRICK', per_page: '48' })) {
      assert.equal(url.searchParams.get(key), value, `${key} after choosing a month`);
    }
    assert.match(await page.locator('#calendar-heading').innerText(), /Março de 2027/);

    // Frame filters update the body without replacing the month-picker header.
    await page.goto(`${base}/escala-folgas?tab=calendar&date=2026-10-02&calendar_period=month`);
    await page.route('**/escala-folgas?**', async route => {
      if (route.request().headers()['turbo-frame'] === 'time-off-calendar-content') {
        await new Promise(resolve => setTimeout(resolve, 500));
      }
      await route.continue();
    });
    await page.locator('.time-off-role-picker').getByRole('button', { name: 'Ajudantes', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('.time-off-calendar-filters input[name="role"]').value === 'helper');
    panel = await open('month');
    await panel.locator('[data-date="2026-11-01"]').click();
    await selected('2026-11-01');
    assert.equal(new URL(page.url()).searchParams.get('role'), 'helper');
    assert.equal(new URL(page.url()).searchParams.get('calendar_period'), 'month');
    await page.unroute('**/escala-folgas?**');

    for (const width of [1440, 390]) for (const mode of ['day', 'month']) for (const theme of ['light', 'dark']) {
      await page.setViewportSize({ width, height: width === 390 ? 844 : 1000 });
      await page.goto(`${base}/escala-folgas?tab=${mode === 'day' ? 'day' : 'calendar'}&date=2026-10-02`);
      await page.evaluate(theme => { document.documentElement.dataset.bsTheme = theme; }, theme);
      panel = await open(mode);
      assert(await insideViewport(panel), `${mode}/${theme}/${width}: popover fits viewport`);
      if (width === 390) {
        assert(await page.getByRole('button', { name: mode === 'day' ? 'Escolher dia' : 'Escolher mês', exact: true }).evaluate(e => e.getBoundingClientRect().width >= 44));
        assert(await panel.locator('button[data-date]').first().evaluate(e => e.getBoundingClientRect().height >= 44));
      }
      await page.screenshot({ path: `tmp/time_off/picker-${mode}-${theme}-${width}.png` });
      await page.mouse.click(8, 8);
      assert.equal(await panel.isVisible(), false, 'click outside closes the picker');
    }
    assert.deepEqual(errors, []);
    console.log('PASS: day/month selection, keyboard, cancel/outside click, year boundary and leap year; filters and full-month view preserved after Turbo frame changes; light/dark desktop/mobile positioning and touch targets.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
