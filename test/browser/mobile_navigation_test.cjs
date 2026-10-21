const { chromium } = require('playwright');
const assert = require('node:assert/strict');

// Run against a local server with an administrator account supplied through NAV_EMAIL/NAV_PASSWORD.
(async () => {
  const browser = await chromium.launch();
  const base = process.env.BASE_URL || 'http://127.0.0.1:3100';
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, ignoreHTTPSErrors: true });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill(process.env.NAV_EMAIL);
    await page.locator('#user_password').fill(process.env.NAV_PASSWORD);
    await page.locator('input[name=commit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/variaveis`);
    const open = page.getByRole('button', { name: 'Abrir menu de navegação' });
    const drawer = page.locator('#mobileNavOffcanvas');
    const opened = () => page.locator('#mobileNavOffcanvas.show:not(.showing)').waitFor();
    const closed = () => page.waitForFunction(() => !document.querySelector('#mobileNavOffcanvas').matches('.show, .showing, .hiding'));
    const insideViewport = async locator => {
      const box = await locator.boundingBox();
      const viewport = page.viewportSize();
      assert(box && box.x >= 0 && box.x + box.width <= viewport.width + 1 && box.y + box.height <= viewport.height + 1);
    };

    for (const width of [320, 390, 768, 991]) {
      await page.setViewportSize({ width, height: width === 320 ? 568 : 844 });
      for (const mode of ['light', 'dark']) {
        await page.evaluate(mode => { document.documentElement.dataset.bsTheme = mode; }, mode);
        for (const control of [open, page.locator('#notificationsDropdown'), page.locator('#navbarDropdown')]) {
          const box = await control.boundingBox();
          assert(box.width >= 44 && box.height >= 44, `Touch target at ${width}px`);
        }
        const positions = await page.locator('.app-mobile-menu-btn, .app-navbar > .container-fluid > .navbar-brand, #notificationsDropdown, #navbarDropdown').evaluateAll(elements => elements.map(e => e.getBoundingClientRect().toJSON()));
        for (let i = 1; i < positions.length; i++) assert(positions[i - 1].right <= positions[i].left, 'Header controls overlap');
        await page.locator('#navbarDropdown').click();
        await insideViewport(page.locator('.app-user-menu'));
        assert.equal(await page.locator('.app-user-menu').evaluate(e => getComputedStyle(e).overflowY), 'auto');
        if (width === 320) assert(await page.locator('.app-user-menu').evaluate(e => e.scrollHeight > e.clientHeight), 'Profile scrolls on short screens');
        await page.keyboard.press('Escape');
        await page.locator('#notificationsDropdown').click();
        await insideViewport(page.locator('.notification-menu'));
        await page.keyboard.press('Escape');
        await open.click();
        await opened();
        await insideViewport(drawer);
        assert.equal(await drawer.locator('[aria-current]').count(), 1);
        assert.equal(await drawer.locator('.app-mobile-shortcuts__grid a[href="/variaveis"]').count(), 1, 'Home is not duplicated');
        const fleet = drawer.locator('[aria-controls=mobileFleetCollapse]');
        await fleet.click();
        await page.locator('#mobileFleetCollapse.show:not(.collapsing)').waitFor();
        assert.equal(await fleet.getAttribute('aria-expanded'), 'true');
        await drawer.locator('[aria-controls=mobileFinanceCollapse]').click();
        await page.locator('#mobileFinanceCollapse.show:not(.collapsing)').waitFor();
        assert.equal(await fleet.getAttribute('aria-expanded'), 'false', 'Only one module stays open');
        if (width === 390) await page.screenshot({ path: `tmp/mobile-navbar-${mode}-390.png` });
        await page.keyboard.press('Escape');
        await closed();
        assert.equal(await open.evaluate(e => document.activeElement === e), true, 'Closing returns focus to the menu button');
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'No horizontal overflow');
      }
    }

    await page.setViewportSize({ width: 390, height: 844 });
    await open.click();
    await opened();
    if (await drawer.locator('[aria-controls=mobileFinanceCollapse]').getAttribute('aria-expanded') !== 'true') {
      await drawer.locator('[aria-controls=mobileFinanceCollapse]').click();
    }
    await page.locator('#mobileFinanceCollapse.show:not(.collapsing)').waitFor();
    await drawer.locator('#mobileFinanceCollapse a').filter({ hasText: /^Lançamentos$/ }).click();
    await page.waitForURL(url => url.pathname === '/invoices');
    assert.equal(await page.locator('.offcanvas-backdrop').count(), 0);
    assert.notEqual(await page.locator('body').evaluate(e => getComputedStyle(e).overflow), 'hidden');
    await open.click();
    await opened();
    assert.equal(await drawer.locator('#mobileFinanceCollapse [aria-current=page]').innerText(), 'Lançamentos');
    assert.equal(await drawer.locator('[aria-controls=mobileFinanceCollapse]').getAttribute('aria-expanded'), 'true');
    await page.setViewportSize({ width: 1280, height: 900 });
    await closed();
    assert.equal(await open.isVisible(), false);
    assert.equal(await page.locator('.offcanvas-backdrop').count(), 0, 'Resizing releases the backdrop');
    assert.notEqual(await page.locator('body').evaluate(e => getComputedStyle(e).overflow), 'hidden');
    assert.equal(await page.locator('#navbarMain').isVisible(), true);
    await page.goBack();
    await page.waitForURL(url => url.pathname === '/variaveis');
    await page.setViewportSize({ width: 390, height: 844 });
    await open.click();
    await opened();
    await page.goto(`${base}/rh/colaboradores?employee_sector=az`);
    await open.click();
    await opened();
    assert.equal(await drawer.locator('#mobileAzCollapse [aria-current=page]').count(), 1, 'Shared paths respect sector query parameters');
    await page.keyboard.press('Escape');
    await closed();
    assert.deepEqual(errors, []);
    console.log('PASS: 320–991px, light/dark, touch targets, bounded scrolling menus, accordion, current section, query parameters, Turbo navigation/back, desktop resize and focus.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
