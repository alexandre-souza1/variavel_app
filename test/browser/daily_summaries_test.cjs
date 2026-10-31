// RAILS_ENV=test bin/rails server -p 4318
// node test/browser/daily_summaries_test.cjs
const { chromium } = require('playwright');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const rails = code => execFileSync('bin/rails', ['runner', code], {
  env: { ...process.env, RAILS_ENV: 'test' }, encoding: 'utf8'
}).trim();
const token = `daily-summary-browser-${Date.now()}`;

(async () => {
  const data = JSON.parse(rails(`
    abort unless Rails.env.test?
    user = User.create!(name: "Resumo Browser", email: "${token}@example.test", password: "password123", role: :user, sector: :fleet)
    summary = user.daily_summaries.create!(summary_date: Date.current, status: :delivered, next_attempt_at: Time.current,
      delivered_at: Time.current, content: "**Agenda de hoje**\n- Conferir 2 tarefas.\n\n**Prioridades**\n<img src=x onerror=alert(1)>",
      sources: [{ label: "Entrada pessoal", path: Rails.application.routes.url_helpers.inbox_path }])
    notification = user.notifications.create!(kind: "daily_summary", title: "Resumo do dia", body: "Sua agenda está disponível.",
      action_text: "Ler resumo", action_url: Rails.application.routes.url_helpers.daily_summary_path(summary), notifiable: summary)
    puts({ user: user.id, summary: summary.id, notification: notification.id }.to_json)
  `));
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, locale: 'pt-BR' });
    page.setDefaultTimeout(15000);
    const base = process.env.BASE_URL || 'http://127.0.0.1:4318';
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill(`${token}@example.test`);
    await page.locator('#user_password').fill('password123');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    const menu = page.locator('#notifications-menu .notification-menu');
    const openMenu = async () => { if (!await menu.isVisible()) await page.getByRole('button', { name: 'Notificações', exact: true }).click(); };
    await openMenu();
    const toggle = page.getByRole('switch', { name: 'Resumo do dia', exact: true });
    assert.equal(await toggle.isChecked(), false, 'existing and new accounts must default to disabled');
    assert.match(await page.locator('#notification-daily-summary-help').innerText(), /8h.*Brasília/);
    const initialUrl = page.url();
    const setPreference = async enabled => {
      const saved = page.waitForResponse(response => new URL(response.url()).pathname === '/notifications/preferences');
      if (enabled) await toggle.check(); else await toggle.uncheck();
      assert.equal((await saved).status(), 200);
      await page.waitForFunction(() => !document.getElementById('notification-daily-summary').disabled);
      assert.equal(await toggle.isChecked(), enabled);
      assert.equal(await menu.isVisible(), true, 'the menu stays open after changing preferences');
      assert.equal(page.url(), initialUrl);
    };
    await setPreference(true);
    await page.reload();
    await openMenu();
    assert.equal(await toggle.isChecked(), true);
    assert.equal(rails(`puts User.find(${data.user}).daily_summary_enabled?`), 'true');

    // Network errors restore the persisted preference and use the floating flash.
    await page.route('**/notifications/preferences', route => route.abort('failed'));
    await toggle.uncheck();
    await page.locator('#flash-container').getByText('Não foi possível salvar a preferência. Tente novamente.').waitFor();
    assert.equal(await toggle.isChecked(), true);
    await page.unroute('**/notifications/preferences');
    await setPreference(false);
    assert.equal(rails(`puts User.find(${data.user}).daily_summary_next_run_at.nil?`), 'true');

    fs.mkdirSync('tmp/browser', { recursive: true });
    await page.locator('#flash-container .btn-close').evaluateAll(buttons => buttons.forEach(button => button.click()));
    await openMenu();
    await page.screenshot({ path: 'tmp/browser/daily-summary-bell-desktop.png' });
    await page.setViewportSize({ width: 390, height: 844 });
    for (const theme of ['light', 'dark']) {
      await page.evaluate(theme => document.documentElement.dataset.bsTheme = theme, theme);
      await openMenu();
      await page.screenshot({ path: `tmp/browser/daily-summary-bell-mobile-${theme}.png` });
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    }

    await openMenu();
    await page.getByRole('button', { name: 'Ler resumo', exact: true }).click();
    await page.waitForURL(url => url.pathname === `/resumos-do-dia/${data.summary}`);
    await page.locator('.daily-summary-content strong').first().waitFor();
    assert.equal(await page.locator('.daily-summary-content strong').first().innerText(), 'Agenda de hoje');
    assert.equal(await page.locator('.daily-summary-content img, .daily-summary-content script').count(), 0);
    assert.match(await page.locator('.daily-summary-content').innerText(), /<img src=x/);
    assert.equal(await page.getByRole('link', { name: 'Entrada pessoal', exact: true }).count(), 1);
    assert.equal(rails(`puts Notification.find(${data.notification}).read?`), 'true');
    await page.screenshot({ path: 'tmp/browser/daily-summary-reading-mobile.png', fullPage: true });
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    assert.equal(rails(`puts User.find(${data.user}).ai_api_requests.count`), '0', 'toggling and reading must not call Gemini');
    assert.deepEqual(errors, []);
    console.log('PASS: default off, own-account preference persistence, failed-toggle rollback, no navigation or Gemini call, notification opens private formatted summary, mobile light/dark layout.');
  } finally {
    await browser.close();
    rails(`abort unless Rails.env.test?; User.find(${data.user}).destroy!`);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
