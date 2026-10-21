const { chromium } = require('playwright');
const assert = require('node:assert/strict');

// Use a local administrator account via NAV_EMAIL and NAV_PASSWORD.
(async () => {
  assert(process.env.NAV_EMAIL && process.env.NAV_PASSWORD, 'Set NAV_EMAIL and NAV_PASSWORD');
  const browser = await chromium.launch();
  const base = process.env.BASE_URL || 'http://127.0.0.1:3100';
  const widths = [320, 390, 650, 651, 768, 1280, 1920];
  const pages = [
    ['/rh/colaboradores', '.employees-page'],
    ['/dashboard', '.fleet-dashboard-page'],
    ['/variaveis', '.workstation-home__inner'],
    ['/invoices', '.invoice-index-page'],
    ['/invoices/dashboard', '.invoice-dashboard-page'],
    ['/invoices/new', '.invoice-entry-content'],
    ['/action_plans', '.action-plans-index'],
    ['/action_plans/new', '.action-plan-form-page'],
    ['/routines', '.routines-page'],
    ['/routine_templates', '.templates-page'],
    ['/routine_templates/new', '.routine-template-form-page'],
    ['/admin/cost_centers', '.admin-catalog-page'],
    ['/admin/cost_centers/new', '.catalog-form-page'],
    ['/rh/colaboradores/new', '.employees-page'],
    ['/parametro_calculos', '.calculation-parameters-page'],
    ['/checklists', '.app-content > .container']
  ];
  try {
    const page = await browser.newPage({ ignoreHTTPSErrors: true });
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill(process.env.NAV_EMAIL);
    await page.locator('#user_password').fill(process.env.NAV_PASSWORD);
    await page.locator('input[name=commit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    const references = new Map();
    const edges = locator => locator.evaluate(element => {
      const box = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return { left: box.left + parseFloat(style.paddingLeft), right: box.right - parseFloat(style.paddingRight) };
    });

    for (const [path, selector] of pages) {
      const response = await page.goto(`${base}${path}`, { waitUntil: 'domcontentloaded' });
      assert.equal(response.status(), 200, path);
      for (const width of widths) {
        await page.setViewportSize({ width, height: 1000 });
        const actual = await edges(page.locator(selector).first());
        if (path === '/rh/colaboradores') {
          const original = await page.evaluate(() => {
            const rem = parseFloat(getComputedStyle(document.documentElement).fontSize);
            const gutter = innerWidth <= 650 ? rem : 3 * rem + Math.min(4.5 * rem, Math.max(1.5 * rem, innerWidth * .04));
            const main = document.querySelector('.app-main').getBoundingClientRect();
            return { left: main.left + gutter, right: main.right - gutter };
          });
          assert(Math.abs(actual.left - original.left) < 1 && Math.abs(actual.right - original.right) < 1,
            `RH at ${width}px no longer matches its original lateral spacing`);
          references.set(width, actual);
        }
        const expected = references.get(width);
        assert(Math.abs(actual.left - expected.left) < 1 && Math.abs(actual.right - expected.right) < 1,
          `${path} at ${width}px differs from rh/colaboradores: ${JSON.stringify({ expected, actual })}`);
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false,
          `${path} at ${width}px widens the viewport`);
      }
    }
    console.log(`PASS: ${pages.length} pages share the original RH content edges at ${widths.join(', ')}px, without horizontal page overflow.`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
