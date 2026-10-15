// Prepare with RAILS_ENV=test bin/rails runner test/browser/ai_assistant_actions_setup.rb.
// Run against a test Rails server with assets: BASE_URL=http://127.0.0.1:4325 node test/browser/ai_assistant_actions_test.cjs
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:4325';
  const setup = JSON.parse(fs.readFileSync('tmp/browser/ai_assistant_actions_setup.json', 'utf8'));
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    page.setDefaultTimeout(15000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('browser-ai-actions@example.test');
    await page.locator('#user_password').fill('password');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/action_plans/${setup.plan_id}`);
    assert.equal(await page.locator('.public-variable-chat-fab').count(), 0);
    const launcher = page.locator('.ai-assistant__launcher');
    const panel = page.locator('.ai-assistant__panel');
    await launcher.click();
    await page.locator('.ai-assistant__proposal').first().waitFor();
    assert.equal(await page.getByRole('button', { name: 'Confirmar criação', exact: true }).count(), 2);
    assert.equal(await page.locator('.ai-assistant__proposal img').count(), 0);
    assert.equal(await page.evaluate(() => window.aiInjected), undefined);
    for (const width of [1440, 390, 320]) {
      await page.setViewportSize({ width, height: width === 320 ? 740 : 1000 });
      for (const theme of ['light', 'dark']) {
        await page.evaluate(theme => document.documentElement.dataset.bsTheme = theme, theme);
        assert(await panel.evaluate(el => el.scrollWidth <= el.clientWidth), `${width}/${theme}: panel overflow`);
        for (const card of await page.locator('.ai-assistant__proposal').all()) {
          const bounds = await card.boundingBox();
          assert(bounds.x >= 0 && bounds.x + bounds.width <= width, `${width}/${theme}: proposal overflow`);
        }
        await page.screenshot({ path: `tmp/browser/ai-actions-${width}-${theme}.png` });
      }
      await page.locator('.meeting-recorder-widget__launcher').click();
      await panel.waitFor({ state: 'hidden' });
      await launcher.click();
      assert(await page.locator('#meeting-recorder-widget').evaluate(el => el.classList.contains('is-collapsed')));
    }
    const task = page.locator('.ai-assistant__proposal').filter({ has: page.locator('> strong', { hasText: 'Inspecionar pneus' }) });
    const plan = page.locator('.ai-assistant__proposal').filter({ has: page.locator('> strong', { hasText: 'Plano sugerido pela IA' }) });
    await task.getByRole('button', { name: 'Ajustar', exact: true }).click();
    assert.match(await page.locator('#ai-assistant-question').inputValue(), /Quero ajustar a proposta "Inspecionar pneus"/);
    await page.locator('#ai-assistant-question').fill('');
    await plan.getByRole('button', { name: 'Cancelar', exact: true }).click();
    await plan.getByText('Proposta cancelada.', { exact: false }).waitFor();
    await task.getByRole('button', { name: 'Confirmar criação', exact: true }).click();
    await task.getByText('Criação concluída após sua confirmação.', { exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Confirmar criação', exact: true }).count(), 0);
    const state = await (await page.request.get(`${base}/assistente-ia`)).json();
    const action = state.messages.flatMap(message => message.actions || []).find(item => item.status === 'executed');
    assert(action.result.id);
    assert.equal(action.confirmation_token, null);
    // Mobile Kanban can collapse the bucket; the broadcast must still add its card.
    await page.locator(`#task_${action.result.id}`).waitFor({ state: 'attached' });
    await page.reload();
    await launcher.click();
    await task.getByRole('link', { name: 'Abrir tarefa' }).waitFor();
    await task.getByRole('link', { name: 'Abrir tarefa' }).click();
    await page.waitForURL(url => url.searchParams.get('task_id') === String(action.result.id));
    await page.locator('#taskModal').waitFor({ state: 'visible' });
    assert.equal(await page.locator('#taskModal input[name="task[title]"]').inputValue(), 'Inspecionar pneus');
    await page.goto(`${base}/action_plans/${setup.plan_id}`);
    await launcher.click();
    await task.waitFor();
    page.once('dialog', dialog => dialog.accept());
    await page.getByRole('button', { name: 'Limpar conversa', exact: true }).click();
    await page.locator('.ai-assistant__welcome').waitFor();
    const cleared = await (await page.request.get(`${base}/assistente-ia`)).json();
    assert.deepEqual(cleared.messages, []);
    assert.deepEqual(errors, []);
    console.log('PASS: real previews, responsive light/dark 1440/390/320, escaped content, recorder coexistence, adjustment, cancellation, confirmed task, persistence, links and clearing.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
