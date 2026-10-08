// Prepare with RAILS_ENV=test bundle exec rails runner test/browser/personal_inbox_setup.rb.
// BASE_URL=http://127.0.0.1:4320 node test/browser/personal_inbox_test.cjs
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const data = JSON.parse(fs.readFileSync('tmp/browser/personal_inbox_setup.json', 'utf8'));
  const base = process.env.BASE_URL || 'http://127.0.0.1:4320';
  const browser = await chromium.launch();
  const errors = [];
  try {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    context.setDefaultTimeout(15000);
    await context.addInitScript(() => {
      // Rails omits this meta tag when CSRF protection is disabled in tests.
      document.addEventListener('DOMContentLoaded', () => {
        if (document.querySelector('meta[name=csrf-token]')) return;
        const token = document.createElement('meta');
        token.name = 'csrf-token';
        token.content = 'browser-test';
        document.head.append(token);
      });
    });
    const page = await context.newPage();
    const second = await context.newPage();
    for (const tab of [page, second]) {
      tab.on('pageerror', error => errors.push(error.message));
      tab.on('console', message => {
        if (message.type() === 'error' && /Error .*controller|Missing target/.test(message.text())) errors.push(message.text());
      });
    }
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('browser-inbox-owner@example.test');
    await page.locator('#user_password').fill('password');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/action_plans/${data.plans[0].id}?view=kanban`);
    await second.goto(`${base}/action_plans/${data.plans[1].id}?view=kanban`);
    await second.waitForFunction(() => [...document.querySelectorAll('turbo-cable-stream-source')].every(source => source.hasAttribute('connected')));
    const inbox = page.locator(`#open-tasks-${data.inbox_id}`);
    await page.locator('.action-plan-inbox-capture [data-new-task-target=button]').click();
    await page.locator('.action-plan-inbox-capture input[name="task[title]"]').fill('Captura pessoal no navegador');
    await page.locator('.action-plan-inbox-capture [data-new-task-target=submit]').click();
    await inbox.locator('.task-card').waitFor();
    const taskId = await inbox.locator('.task-card').getAttribute('data-task-id');
    await second.locator(`#open-tasks-${data.inbox_id} #task_${taskId}`).waitFor();
    assert.equal(await page.locator('.action-plan-inbox-count').innerText(), '1 tarefa');
    assert.equal(await second.locator('.action-plan-inbox-count').innerText(), '1 tarefa');
    assert.equal(await page.getByText('Segredo Browser Inbox').count(), 0);

    await second.locator(`#task_${taskId}`).click();
    await second.locator('#taskModal').waitFor({ state: 'visible' });
    assert.equal(await second.locator('#taskModal select[name="task[label_ids][]"]').count(), 0);
    await second.locator('#taskModal textarea[name="comment[content]"]').fill('Comentário antes do plano');
    await second.locator('#taskModal input[type=submit][value=Comentar]').click();
    await second.getByText('Comentário antes do plano', { exact: true }).waitFor();
    await second.locator('[data-action="click->task-checklist#addItem"]').click();
    await second.locator('.task-checklist-item__input').waitFor();
    await second.waitForFunction(() => document.querySelector('#task_bucket_id')?.tomselect);
    const launchedCard = await second.locator(`#task_${taskId}`).elementHandle();
    let responsePromise = second.waitForResponse(response => ['PATCH', 'POST'].includes(response.request().method()) && new URL(response.url()).pathname === `/tasks/${taskId}`);
    await second.locator('#task_bucket_id').evaluate((select, value) => select.tomselect.setValue(String(value)), data.plans[1].bucket_id);
    assert.equal((await responsePromise).status(), 200);
    await second.locator('#taskModal select[name="task[label_ids][]"]').waitFor({ state: 'attached' });
    await page.locator(`#task_${taskId}`).waitFor({ state: 'detached' });
    await second.locator(`#open-tasks-${data.plans[1].bucket_id} #task_${taskId}`).waitFor();
    assert.equal(await launchedCard.evaluate((element, bucketId) => element.isConnected && element.parentElement.id === `open-tasks-${bucketId}`, data.plans[1].bucket_id), true);
    await second.locator('#taskModal .btn-close').click();
    await second.locator('#taskModal').waitFor({ state: 'hidden' });
    await second.locator(`#task_${taskId}`).click();
    await second.locator('#taskModal').waitFor({ state: 'visible' });
    assert.equal(await second.locator('#taskModal select[name="task[label_ids][]"]').count(), 1);
    await second.getByText('Comentário antes do plano', { exact: true }).waitFor();
    await second.locator('.task-checklist-item__input').waitFor();
    const returnedCard = await second.locator(`#task_${taskId}`).elementHandle();
    responsePromise = second.waitForResponse(response => ['PATCH', 'POST'].includes(response.request().method()) && new URL(response.url()).pathname === `/tasks/${taskId}`);
    await second.locator('#task_bucket_id').evaluate((select, value) => select.tomselect.setValue(String(value)), data.inbox_id);
    assert.equal((await responsePromise).status(), 200);
    await page.locator(`#open-tasks-${data.inbox_id} #task_${taskId}`).waitFor();
    assert.equal(await returnedCard.evaluate((element, bucketId) => element.isConnected && element.parentElement.id === `open-tasks-${bucketId}`, data.inbox_id), true);
    await second.locator('#taskModal select[name="task[label_ids][]"]').waitFor({ state: 'detached' });
    await second.locator('#taskModal .btn-close').click();

    const card = page.locator(`#task_${taskId}`);
    const destination = page.locator(`#open-tasks-${data.plans[0].bucket_id}`);
    const from = await card.boundingBox();
    const to = await destination.boundingBox();
    responsePromise = page.waitForResponse(response => response.request().method() === 'PATCH' && response.url().includes(`/tasks/${taskId}/move`));
    await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
    await page.mouse.down();
    await page.mouse.move(from.x + from.width / 2 + 15, from.y + from.height / 2 + 15, { steps: 5 });
    await page.mouse.move(to.x + to.width / 2, to.y + Math.min(to.height / 2, 40), { steps: 25 });
    await page.mouse.up();
    assert.equal((await responsePromise).status(), 200);
    await page.locator(`#open-tasks-${data.plans[0].bucket_id} #task_${taskId}`).waitFor();
    await second.locator(`#task_${taskId}`).waitFor({ state: 'detached' });
    await page.locator(`#task_${taskId}`).click();
    await page.locator('#taskModal').waitFor({ state: 'visible' });
    await page.locator('#taskModal .btn-close').click();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.reload();
    await page.locator('.action-plan-inbox-launcher').click();
    await page.locator('#actionPlanInbox.show').waitFor();
    assert.equal(await page.locator('.action-plan-inbox-count').innerText(), '0 tarefas');
    assert.equal(await page.locator('.action-plan-inbox-empty').innerText(), 'Nada na Entrada\nCapture uma tarefa acima e organize-a quando estiver pronto.');
    fs.mkdirSync('tmp/browser', { recursive: true });
    await page.screenshot({ path: 'tmp/browser/personal-inbox-mobile.png' });
    await page.goto(`${base}/inbox`);
    await page.locator('.action-plan-inbox-capture [data-new-task-target=button]').click();
    await page.locator('.action-plan-inbox-capture input[name="task[title]"]').fill('Tarefa fora do plano');
    await page.locator('.action-plan-inbox-capture [data-new-task-target=submit]').click();
    await page.locator(`#open-tasks-${data.inbox_id} .task-card`).waitFor();
    const draftId = await page.locator(`#open-tasks-${data.inbox_id} .task-card`).getAttribute('data-task-id');
    await page.goto(`${base}/inbox?task_id=${draftId}`);
    await page.locator('#taskModal').waitFor({ state: 'visible' });
    for (const plan of data.plans) assert.equal(await page.locator(`#task_bucket_id option[value="${plan.bucket_id}"]`).count(), 1);
    assert.equal(await page.locator('#modal-container').count(), 1);
    assert.deepEqual(errors, []);
    console.log('PASS: personal inbox capture, live synchronization across plans, modal refresh, comments, checklist, launch, return, drag, mobile drawer, standalone inbox, and notification links.');
  } catch (error) {
    if (errors.length) console.error(errors);
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
