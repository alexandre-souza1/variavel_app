// RAILS_ENV=test bin/rails runner test/browser/ai_assistant_updates_setup.rb
// BASE_URL=http://127.0.0.1:4325 node test/browser/ai_assistant_updates_test.cjs
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const setup = JSON.parse(fs.readFileSync('tmp/browser/ai_assistant_updates_setup.json', 'utf8'));
  const base = process.env.BASE_URL || 'http://127.0.0.1:4325';
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    const page = await context.newPage();
    page.setDefaultTimeout(15000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('browser-ai-updates@example.test');
    await page.locator('#user_password').fill('password');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    const state = await (await page.request.get(`${base}/assistente-ia`)).json();
    const sent = [];
    // Simulate only Gemini replies; previews, context rendering and confirmations use Rails and the real test database.
    await context.route('**/assistente-ia', async route => {
      if (route.request().method() !== 'POST') return route.continue();
      sent.push(route.request().postDataJSON());
      return route.fulfill({ json: state });
    });
    await page.goto(`${base}/action_plans/${setup.plan_id}?view=kanban`);
    const launcher = page.locator('.ai-assistant__launcher');
    const panel = page.locator('.ai-assistant__panel');
    const bar = page.locator('.ai-assistant__context');
    await launcher.click();
    await page.locator('.ai-assistant__proposal').first().waitFor();
    assert.match(await bar.innerText(), /Plano: Inspeção da frota/);
    await bar.getByRole('button', { name: 'Resumir plano', exact: true }).click();
    await page.waitForFunction(() => !document.querySelector('[data-ai-assistant-target="send"]').disabled);
    assert.deepEqual(sent.at(-1).page_context, { type: 'plan', id: setup.plan_id });
    const second = await context.newPage();
    await second.goto(`${base}/action_plans/${setup.other_plan_id}?view=kanban`);
    await second.locator('.ai-assistant__launcher').click();
    await second.getByRole('button', { name: 'Ver pendências', exact: true }).click();
    await second.waitForFunction(() => !document.querySelector('[data-ai-assistant-target="send"]').disabled);
    assert.deepEqual(sent.at(-1).page_context, { type: 'plan', id: setup.other_plan_id });
    await second.close();
    await page.locator('.ai-assistant__header button').click();
    await page.locator(`#task_${setup.task_id}`).click();
    await page.locator('#taskModal').waitFor({ state: 'visible' });
    await page.getByRole('button', { name: 'Usar esta tarefa no assistente', exact: true }).click();
    await page.locator('#taskModal').waitFor({ state: 'hidden' });
    await panel.waitFor({ state: 'visible' });
    assert.match(await bar.innerText(), /Tarefa: Inspecionar pneus/);
    await bar.getByRole('button', { name: 'Concluir tarefa', exact: true }).click();
    await page.waitForFunction(() => !document.querySelector('[data-ai-assistant-target="send"]').disabled);
    assert.deepEqual(sent.at(-1).page_context, { type: 'task', id: setup.task_id });
    assert.match(sent.at(-1).question, /conclusão desta tarefa/);
    assert.equal(await page.locator('.ai-assistant__proposal img').count(), 0);
    assert.equal(await page.evaluate(() => window.aiInjected), undefined);
    const proposed = page.locator('.ai-assistant__proposal').filter({ has: page.locator('> strong', { hasText: 'Inspecionar pneus' }) });
    assert.match(await proposed.innerText(), /Antes/);
    assert.match(await proposed.innerText(), /Depois/);
    for (const width of [1440, 390, 320]) {
      await page.setViewportSize({ width, height: width === 320 ? 740 : 1000 });
      for (const theme of ['light', 'dark']) {
        await page.evaluate(theme => document.documentElement.dataset.bsTheme = theme, theme);
        await page.locator('.ai-assistant__messages').evaluate(el => el.scrollTop = 0);
        assert(await panel.evaluate(el => el.scrollWidth <= el.clientWidth), `${width}/${theme}: panel overflow`);
        assert(await bar.evaluate(el => el.scrollWidth <= el.clientWidth), `${width}/${theme}: shortcut overflow`);
        for (const card of await page.locator('.ai-assistant__proposal').all()) {
          const rect = await card.boundingBox();
          assert(rect.x >= 0 && rect.x + rect.width <= width, `${width}/${theme}: preview overflow`);
        }
        await page.screenshot({ path: `tmp/browser/ai-updates-${width}-${theme}.png` });
      }
    }
    await proposed.getByRole('button', { name: 'Confirmar alterações', exact: true }).click();
    await proposed.getByText('Alterações salvas após sua confirmação.', { exact: true }).waitFor();
    await bar.getByRole('button', { name: 'Reabrir tarefa', exact: true }).waitFor();
    const updated = await (await page.request.get(`${base}/assistente-ia`)).json();
    const executed = updated.messages.flatMap(message => message.actions || []).find(action => action.status === 'executed');
    assert.equal(executed.result.id, setup.task_id);
    assert.equal(executed.result.completed, true);
    await page.locator(`#done-tasks-${await page.locator(`#task_${setup.task_id}`).getAttribute('data-bucket-id')} #task_${setup.task_id}`).waitFor({ state: 'attached' });
    const outsideEdit = await page.request.patch(`${base}/tasks/${setup.stale_task_id}`, {
      form: { 'task[title]': 'Editada fora da IA' }, headers: { Accept: 'text/html' }, maxRedirects: 0
    });
    assert.equal(outsideEdit.status(), 302);
    const stale = page.locator('.ai-assistant__proposal').filter({ has: page.locator('> strong', { hasText: 'Conferir estepe' }) });
    const refresh = page.waitForResponse(response => response.url() === `${base}/assistente-ia` && response.request().method() === 'GET');
    await stale.getByRole('button', { name: 'Confirmar alterações', exact: true }).click();
    await page.locator('.ai-assistant__error').filter({ hasText: 'A tarefa mudou desde a prévia' }).waitFor();
    await refresh;
    assert.match(await page.locator('.ai-assistant__error').innerText(), /A tarefa mudou desde a prévia/);
    await stale.getByRole('button', { name: 'Cancelar', exact: true }).click();
    await stale.getByText('Proposta cancelada.', { exact: false }).waitFor();
    await page.goto(`${base}/inbox`);
    await launcher.click();
    assert.equal(await bar.isVisible(), false);
    assert.deepEqual(errors, []);
    assert.equal(await page.evaluate(() => window.aiInjected), undefined);
    console.log('PASS: real update confirmation, before/after, task modal handoff, isolated tab contexts, contextual shortcuts, completion broadcast, stale edit protection, error persistence and responsive light/dark 1440/390/320.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
