// BROWSER_EMAIL=... BROWSER_PASSWORD=... node test/browser/builtin_dark_themes_test.cjs
// Optional THEME_BASELINE points to a snapshot captured before a palette change.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const refined = ['blue_teal', 'sage_teal', 'black_mint', 'white_tea_sage', 'earthy_forest_hues'];
const protectedThemes = ['retro_orange', 'halloween', 'bosque_de_outono'];
const snapshot = async (page, key, mode) => page.evaluate(({ key, mode }) => {
  const root = document.documentElement;
  root.dataset.colorTheme = key; root.dataset.bsTheme = mode;
  document.dispatchEvent(new CustomEvent('app:theme-changed'));
  const style = getComputedStyle(root);
  const tokens = Object.fromEntries([...style].filter(name => name.startsWith('--')).map(name => [name, style.getPropertyValue(name).trim()]));
  const elements = Object.fromEntries(['body', '.kpi-card', '.invoice-dashboard-eyebrow', '.form-select', '.invoice-filter-submit', '.az-report-btn--primary', '.app-navbar'].map(selector => {
    const el = document.querySelector(selector), s = el ? getComputedStyle(el) : null;
    return [selector, s ? { color: s.color, background: s.backgroundColor, border: s.borderColor } : null];
  }));
  return { tokens, elements };
}, { key, mode });
const channels = hex => hex.slice(1).match(/../g).map(channel => parseInt(channel, 16));
const rgb = hex => `rgb(${channels(hex).join(', ')})`;
const luminance = hex => channels(hex).map(channel => {
  const value = channel / 255;
  return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
}).reduce((total, value, index) => total + value * [.2126, .7152, .0722][index], 0);
const contrast = (first, second) => {
  const [light, dark] = [luminance(first), luminance(second)].sort((a, b) => b - a);
  return (light + .05) / (dark + .05);
};

(async () => {
  assert(process.env.BROWSER_EMAIL && process.env.BROWSER_PASSWORD, 'Provide a disposable administrator');
  const base = process.env.BASE_URL || 'http://127.0.0.1:3000';
  const baseline = process.env.THEME_BASELINE ? JSON.parse(fs.readFileSync(process.env.THEME_BASELINE, 'utf8')) : null;
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill(process.env.BROWSER_EMAIL);
    await page.locator('#user_password').fill(process.env.BROWSER_PASSWORD);
    await page.locator('input[name=commit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/admin/temas`);
    const catalog = await page.evaluate(() => JSON.parse(document.body.dataset.colorThemes));
    const cards = await page.locator('.color-theme-card').evaluateAll(cards => cards.map(card => ({
      name: card.querySelector('h2').textContent.trim(), edit: card.querySelector('a[href$="/edit"]').getAttribute('href')
    })));
    const editPaths = Object.fromEntries(refined.map(key => [key, cards.find(card => card.name.endsWith(catalog[key].name)).edit]));
    await page.goto(`${base}/invoices/dashboard?month=10&year=2026`);
    await page.addStyleTag({ content: '*, *::before, *::after { transition: none !important; animation: none !important; }' });
    const states = {};
    fs.mkdirSync('tmp/browser', { recursive: true });
    for (const key of Object.keys(catalog)) {
      await page.setViewportSize({ width: 1440, height: 1000 });
      for (const mode of ['light', 'dark']) {
        const state = await snapshot(page, key, mode);
        if (baseline?.[key] && (mode === 'light' || protectedThemes.includes(key))) {
          const expected = baseline[key][mode];
          const changes = [...new Set([...Object.keys(state.tokens), ...Object.keys(expected.tokens)])]
            .filter(name => state.tokens[name] !== expected.tokens[name])
            .map(name => ({ name, before: expected.tokens[name], after: state.tokens[name] }));
          // The baseline's rendered elements may have been mid-transition;
          // custom properties provide the exact settled palette for comparison.
          assert.deepEqual(state.tokens, expected.tokens, `${key} ${mode} palette is unchanged: ${JSON.stringify(changes)}`);
        }
        if (mode !== 'dark' || !refined.includes(key)) continue;
        states[key] = state;
        const color = name => state.tokens[`--${name}`];
        for (const background of ['app-dark-page', 'app-dark-surface', 'app-dark-elevated', 'app-dark-hover', 'app-strong']) {
          for (const foreground of ['app-dark-text', 'app-dark-muted', 'app-primary', 'app-soft']) {
            assert(contrast(color(foreground), color(background)) >= 4.5, `${key}: ${foreground} on ${background} needs readable contrast`);
          }
        }
        const layers = ['app-dark-input', 'app-dark-page', 'app-dark-surface', 'app-dark-elevated', 'app-dark-hover'].map(name => luminance(color(name)));
        assert(layers.every((value, index) => !index || value > layers[index - 1]), `${key}: distinct surface layers`);
        assert(contrast('#FFFFFF', color('app-button-solid')) >= 4.5, `${key}: white button labels remain readable`);
        assert.equal(color('app-primary-rgb'), channels(color('app-primary')).join(', '));
        assert.equal(color('app-muted'), color('app-dark-muted'), 'chart labels use the dark muted color');
        assert.equal(state.elements.body.background, rgb(color('app-dark-page')));
        assert.equal(state.elements['.kpi-card'].background, rgb(color('app-dark-surface')));
        assert.equal(state.elements['.invoice-dashboard-eyebrow'].color, rgb(color('app-primary')));
        const launcher = await page.locator('.ai-assistant__launcher').evaluate(el => {
          const style = getComputedStyle(el);
          return { color: style.color, background: style.backgroundColor };
        });
        assert.equal(launcher.color, 'rgb(255, 255, 255)');
        assert.equal(launcher.background, rgb(color('app-button-solid')), 'launcher uses the solid action color for readable labels');
        for (const width of [1440, 390]) {
          await page.setViewportSize({ width, height: 1000 });
          assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${key} fits ${width}px`);
          await page.screenshot({ path: `tmp/browser/builtin-dark-${key}-${width}.png` });
        }
      }
    }
    assert.equal(new Set(Object.values(states).map(state => state.tokens['--app-dark-page'])).size, 5, 'each theme keeps its own background');
    await page.setViewportSize({ width: 1440, height: 1000 });
    for (const key of refined) {
      await page.goto(`${base}${editPaths[key]}`);
      await page.waitForFunction(() => document.querySelector('[data-preview-mode=dark]')?.style.getPropertyValue('--preview-background'));
      const preview = page.locator('[data-preview-mode=dark]');
      for (const mode of ['light', 'dark']) {
        await page.evaluate(mode => document.documentElement.dataset.bsTheme = mode, mode);
        const colors = await preview.evaluate(el => Object.fromEntries(['bar', 'action', 'background', 'ink', 'muted', 'accent-ink'].map(name => [name, el.style.getPropertyValue(`--preview-${name}`)])));
        for (const [name, token] of Object.entries({ bar: 'app-strong', action: 'app-button-solid', background: 'app-dark-page', ink: 'app-dark-text', muted: 'app-dark-muted', 'accent-ink': 'app-primary' })) {
          assert.equal(colors[name], states[key].tokens[`--${token}`], `${key}: preview matches actual ${token} inside ${mode} page`);
        }
      }
      const primary = page.locator('#color_theme_primary_color');
      const initial = await primary.inputValue();
      const originalBackground = await preview.evaluate(el => el.style.getPropertyValue('--preview-background'));
      await primary.fill('#8050A0');
      assert.notEqual(await preview.evaluate(el => el.style.getPropertyValue('--preview-background')), originalBackground, 'editing a palette uses generated preview');
      await primary.fill(initial.toLowerCase());
      assert.equal(await preview.evaluate(el => el.style.getPropertyValue('--preview-background')), originalBackground, 'restoring the original palette restores its preview');
      await page.locator('.color-theme-preview-panel').screenshot({ path: `tmp/browser/builtin-dark-preview-${key}.png` });
    }
    assert.deepEqual(errors, []);
    console.log('PASS: five distinct dark palettes, foreground/button contrast, layered surfaces, real dashboard and chart tokens, desktop/mobile, accurate original previews and edited fallback, no JavaScript errors.');
    if (baseline) console.log('PASS: every light palette and all excluded themes exactly match their previous CSS tokens.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
