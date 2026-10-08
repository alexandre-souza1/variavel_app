// Prepare with RAILS_ENV=test bundle exec rails runner test/browser/task_move_setup.rb.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const data = JSON.parse(fs.readFileSync('tmp/browser/task_move_setup.json', 'utf8'));
  const base = process.env.BASE_URL || 'http://127.0.0.1:4320';
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext({ viewport: { width: 1600, height: 1100 } });
    context.setDefaultTimeout(15000);
    await context.addInitScript(() => {
      document.addEventListener('DOMContentLoaded', () => {
        if (!document.querySelector('meta[name=csrf-token]')) {
          const token = document.createElement('meta');
          token.name = 'csrf-token';
          token.content = 'browser-test';
          document.head.append(token);
        }
      });
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('browser-inbox-owner@example.test');
    await page.locator('#user_password').fill('password');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/action_plans/${data.plan_id}?view=kanban`);
    const second = await context.newPage();
    second.on('pageerror', error => errors.push(error.message));
    await second.goto(page.url());
    for (const tab of [page, second]) {
      await tab.waitForFunction(() => [...document.querySelectorAll('turbo-cable-stream-source')].every(source => source.hasAttribute('connected')));
    }

    async function order(tab, bucketId) {
      return tab.locator(`#open-tasks-${bucketId} > .task-card`).evaluateAll(cards => cards.map(card => Number(card.dataset.taskId)));
    }

    async function move(taskId, destinationId, beforeId, expectedOrder) {
      const card = page.locator(`#task_${taskId}`);
      await card.evaluate(element => {
        window.moveObserver?.disconnect();
        window.moveOriginalNode = element;
        window.moveDocument = document;
        window.moveTrace = { removals: 0, confirmations: 0 };
        if (!window.moveTracking) {
          document.addEventListener('turbo:before-stream-render', event => {
            if (event.target.getAttribute('action') === 'task_move') window.moveTrace.confirmations++;
          });
          window.moveTracking = true;
        }
        element.parentElement.addEventListener('end', () => {
          window.moveObserver?.disconnect();
          window.moveObserver = new MutationObserver(records => {
            for (const record of records) {
              if ([...record.removedNodes].includes(element)) window.moveTrace.removals++;
            }
          });
          window.moveObserver.observe(document.body, { childList: true, subtree: true });
        }, { once: true });
      });
      const from = await card.boundingBox();
      const target = beforeId ? page.locator(`#task_${beforeId}`) : page.locator(`#open-tasks-${destinationId}`);
      const to = await target.boundingBox();
      const responsePromise = page.waitForResponse(response => response.request().method() === 'PATCH' && response.url().includes(`/tasks/${taskId}/move`));
      await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
      await page.mouse.down();
      await page.mouse.move(from.x + from.width / 2 + 15, from.y + from.height / 2 + 15, { steps: 5 });
      await page.mouse.move(to.x + to.width / 2, to.y + (beforeId ? 8 : Math.min(to.height / 2, 40)), { steps: 25 });
      await page.mouse.up();
      const response = await responsePromise;
      assert.equal(response.status(), 200);
      assert.equal(response.request().postDataJSON().position, expectedOrder.indexOf(taskId));
      await page.waitForFunction(({ taskId, destinationId }) => {
        const card = document.getElementById(`task_${taskId}`);
        return card?.parentElement.id === `open-tasks-${destinationId}` && card.dataset.taskMoveVersion && !card.dataset.taskMovePending;
      }, { taskId, destinationId });
      await second.locator(`#open-tasks-${destinationId} #task_${taskId}`).waitFor();
      // Allow both websocket and HTTP confirmation, plus any unintended reload,
      // to settle before asserting that the original DOM node stayed in place.
      await page.waitForTimeout(500);
      assert.deepEqual(await order(page, destinationId), expectedOrder);
      assert.deepEqual(await order(second, destinationId), expectedOrder);
      const trace = await page.evaluate(taskId => ({
        sameNode: document.getElementById(`task_${taskId}`) === window.moveOriginalNode,
        sameDocument: document === window.moveDocument,
        removals: window.moveTrace?.removals,
        confirmations: window.moveTrace?.confirmations
      }), taskId);
      assert.equal(trace.sameDocument, true, 'drag must not reload the page');
      assert.equal(trace.sameNode, true, 'server confirmation must retain the dragged node');
      assert.equal(trace.removals, 0, 'server confirmation must not remove or reinsert the dragged node');
      assert.ok(trace.confirmations >= 1);
      assert.equal(await page.locator(`#task_${taskId}`).count(), 1);
    }

    await move(data.moving_id, data.destination_id, data.last_id, [data.first_id, data.moving_id, data.last_id]);
    assert.equal(await page.locator(`#open-count-${data.source_id}`).innerText(), '0');
    assert.equal(await page.locator(`#open-count-${data.destination_id}`).innerText(), '3');
    await move(data.last_id, data.destination_id, data.first_id, [data.last_id, data.first_id, data.moving_id]);
    await move(data.moving_id, data.inbox_id, data.draft_id, [data.moving_id, data.draft_id]);
    await move(data.moving_id, data.destination_id, data.first_id, [data.last_id, data.moving_id, data.first_id]);
    await page.evaluate(async ({ taskId, sourceId }) => {
      const { Turbo } = await import('@hotwired/turbo-rails');
      const card = document.getElementById(`task_${taskId}`);
      for (const version of ['2000-01-01T00:00:00.000000Z', card.dataset.taskMoveVersion]) {
        const stream = document.createElement('turbo-stream');
        stream.setAttribute('action', 'task_move');
        stream.setAttribute('task-id', card.id);
        stream.setAttribute('target', `open-tasks-${sourceId}`);
        stream.setAttribute('version', version);
        stream.setAttribute('preceding-task-ids', '[]');
        const template = document.createElement('template');
        template.content.append(card.cloneNode(true));
        stream.append(template);
        Turbo.renderStreamMessage(stream.outerHTML);
      }
    }, { taskId: data.moving_id, sourceId: data.source_id });
    await page.waitForTimeout(100);
    assert.deepEqual(await order(page, data.destination_id), [data.last_id, data.moving_id, data.first_id]);

    // A rejected move must restore the prior placement without navigating.
    await page.route(`**/tasks/${data.moving_id}/move`, route => route.fulfill({ status: 403, body: '' }));
    const rejectedCard = await page.locator(`#task_${data.moving_id}`).elementHandle();
    const from = await page.locator(`#task_${data.moving_id}`).boundingBox();
    const to = await page.locator(`#open-tasks-${data.source_id}`).boundingBox();
    const rejectedResponse = page.waitForResponse(response => response.request().method() === 'PATCH' && response.url().includes(`/tasks/${data.moving_id}/move`));
    await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
    await page.mouse.down();
    await page.mouse.move(from.x + from.width / 2 + 15, from.y + from.height / 2 + 15, { steps: 5 });
    await page.mouse.move(to.x + to.width / 2, to.y + Math.min(to.height / 2, 40), { steps: 25 });
    await page.mouse.up();
    assert.equal((await rejectedResponse).status(), 403);
    await page.waitForFunction(({ taskId, bucketId }) => {
      const card = document.getElementById(`task_${taskId}`);
      return card?.parentElement.id === `open-tasks-${bucketId}` && !card.dataset.taskMovePending;
    }, { taskId: data.moving_id, bucketId: data.destination_id });
    assert.equal(await rejectedCard.evaluate(element => element.isConnected), true);
    assert.deepEqual(await order(page, data.destination_id), [data.last_id, data.moving_id, data.first_id]);
    await page.unroute(`**/tasks/${data.moving_id}/move`);
    await page.locator(`#task_${data.moving_id}`).click();
    await page.locator('#taskModal').waitFor({ state: 'visible' });
    await page.locator('#taskModal .btn-close').click();
    await page.reload();
    assert.deepEqual(await order(page, data.destination_id), [data.last_id, data.moving_id, data.first_id]);
    assert.deepEqual(await order(page, data.inbox_id), [data.draft_id]);
    assert.deepEqual(errors, []);
    console.log('PASS: stable drag and inbox round trip, cross-tab synchronization, persisted order, stale/duplicate confirmations, modal opening, and rejected move rollback.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
