const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const base = process.env.BASE_URL || 'http://127.0.0.1:4318';
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('user_one@example.com');
    await page.locator('#user_password').fill('password');
    await page.locator('input[type="submit"]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/escala-folgas?date=2026-10-07&group=E&role=driver&settings=1&correction=1`);
    await page.locator('#time-off-settings.show').waitFor();
    const form = page.locator('.time-off-correction-form');
    const member = await form.locator('option').filter({ hasText: 'PATRICK VIEIRA DA SILVA' }).getAttribute('value');
    await page.locator('#correction-membership').selectOption(member);
    assert.equal(await page.locator('#correction-start').inputValue(), '2026-10-08');
    assert.equal(await page.locator('#correction-group').inputValue(), 'A');
    assert.ok(await page.locator('#correction-updated-at').inputValue());
    await page.locator('#correction-start').fill('2026-10-14');
    await page.locator('#correction-reason').fill('Início lançado em 08/10; começa após o dia 13.');
    await form.getByRole('button', { name: 'Salvar correção', exact: true }).click();
    await page.getByText('Vigência corrigida. A correção foi registrada no histórico.', { exact: true }).waitFor();
    await page.locator('#time-off-settings.show').waitFor();
    assert.equal(await page.locator('#correction-start').inputValue(), '2026-10-14');
    assert.equal(await page.locator('#correction-membership').inputValue(), member);
    assert.equal(new URL(page.url()).searchParams.get('group'), 'E');
    await page.setViewportSize({ width: 390, height: 844 });
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
    fs.mkdirSync('tmp/time_off', { recursive: true });
    await page.locator('#time-off-settings').screenshot({ path: 'tmp/time_off/membership_correction_mobile.png' });
    await page.getByRole('button', { name: 'Fechar configuração', exact: true }).click();
    await page.goto(`${base}/escala-folgas?date=2026-10-13&tab=day`);
    assert.equal(await page.locator('.time-off-person').filter({ hasText: 'PATRICK' }).count(), 0);
    await page.goto(`${base}/escala-folgas?date=2026-10-14&tab=day`);
    assert.equal(await page.locator('.time-off-person').filter({ hasText: 'PATRICK' }).count(), 1);
    await page.goto(`${base}/escala-folgas?date=2026-10-14&tab=history`);
    assert.match(await page.locator('.time-off-history').innerText(), /08\/10\/2026.*14\/10\/2026/);
    assert.deepEqual(errors, []);
    console.log('PASS: future helper start corrected from 08/10 to 14/10, form prefill, filters, availability, history and mobile.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
