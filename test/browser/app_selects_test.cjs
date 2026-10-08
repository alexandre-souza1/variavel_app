// Uses the existing test fixtures and a Rails server in test mode.
// BASE_URL=http://127.0.0.1:4318 node test/browser/app_selects_test.cjs
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, locale: 'pt-BR' });
    const base = process.env.BASE_URL || 'http://127.0.0.1:4318';
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill(process.env.BROWSER_EMAIL || 'user_one@example.com');
    await page.locator('#user_password').fill(process.env.BROWSER_PASSWORD || 'password');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    await page.goto(`${base}/rh/colaboradores/new?employee_sector=az&employee_cargo=operador`);
    await page.waitForFunction(() => document.querySelector('#initial_sector')?.tomselect);
    assert.equal(await page.locator('#initial_sector + .app-select .ts-control').getAttribute('aria-invalid'), 'false');
    assert.equal(await page.locator('#initial_sector + .app-select').evaluate(element => element.classList.contains('is-invalid')), false, 'valid selects must not start with an error');

    const choose = async (selector, value) => {
      const wrapper = page.locator(`${selector} + .app-select`);
      await wrapper.locator('.ts-control').click();
      const id = await page.locator(selector).evaluate(element => element.tomselect.dropdown_content.id);
      const menu = page.locator('.app-select-menu').filter({ has: page.locator(`[id="${id}"]`) });
      await menu.waitFor({ state: 'visible' });
      await menu.locator(`.option[data-value="${value}"]`).click();
    };
    await choose('#initial_sector', 'du');
    await page.waitForFunction(() => document.querySelector('#initial_turno').disabled);
    assert(await page.locator('[data-employee-role-target=az]').isHidden());
    await choose('#initial_sector', 'az');
    await choose('#initial_cargo', 'operador');
    assert.equal(await page.locator('#initial_cargo').inputValue(), 'operador');
    assert.equal(await page.locator('#initial_cargo + .app-select .item').textContent(), 'Operador');
    assert.equal(await page.locator('#initial_cargo + .app-select').evaluate(element => element.classList.contains('is-invalid')), false, 'sync must not toggle a valid select into an error');
    assert(await page.locator('[data-employee-role-target=az]').isVisible());

    // Independent DOM fixtures exercise existing native-select contracts.
    await page.evaluate(() => {
      const fixture = document.createElement('section');
      fixture.id = 'select-contracts';
      fixture.style.cssText = 'margin:24px;max-width:700px';
      fixture.innerHTML = `<form id="select-form"><label for="contract-select">Mês</label><select id="contract-select" name="month" required class="form-select"><option value="">Escolha</option><optgroup label="Primeiro semestre"><option value="jan" data-person="123" data-group-code="A">Janeiro</option><option value="feb" disabled>Fevereiro</option><option value="mar">Março</option></optgroup></select><fieldset id="select-fieldset"><label for="dependent-select">Grupo</label><select id="dependent-select" class="form-select" name="group"><option value="A" selected>Grupo A</option><option value="FIXO">Fixo</option></select></fieldset><label for="long-select">Responsável</label><select id="long-select" name="user" class="form-select">${Array.from({length:75},(_,i)=>`<option value="${i}">Pessoa ${String(i).padStart(2,'0')}</option>`).join('')}</select><label for="multi-select">Seleção múltipla</label><select id="multi-select" multiple name="tags[]" class="form-select"><option value="one" selected>Um</option><option value="two">Dois</option><option value="three">Três</option></select><textarea id="contract-textarea" class="form-control" rows="3">Observação que pode ser redimensionada.</textarea></form>`;
      document.querySelector('.app-content').prepend(fixture);
      window.contractChanges = 0;
      document.querySelector('#select-form').addEventListener('change', () => window.contractChanges++);
      document.querySelector('#select-form').addEventListener('submit', event => event.preventDefault());
    });
    await page.waitForFunction(() => document.querySelector('#contract-select').tomselect && document.querySelector('#multi-select').tomselect);
    await choose('#contract-select', 'jan');
    assert.equal(await page.evaluate(() => window.contractChanges), 1, 'one native change per choice');
    assert.deepEqual(await page.locator('#contract-select').evaluate(element => ({
      value: element.value, index: element.selectedIndex, values: [...element.options].map(option => option.value),
      parent: element.selectedOptions[0].parentElement.tagName, person: element.selectedOptions[0].dataset.person,
      group: element.selectedOptions[0].dataset.groupCode, form: new FormData(element.form).get('month')
    })), { value: 'jan', index: 1, values: ['', 'jan', 'feb', 'mar'], parent: 'OPTGROUP', person: '123', group: 'A', form: 'jan' });

    await page.locator('#contract-select').evaluate(element => { element.value = 'mar'; });
    assert.equal(await page.locator('#contract-select + .app-select .item').textContent(), 'Março');
    assert.equal(await page.evaluate(() => window.contractChanges), 1, 'programmatic changes are silent');
    await page.locator('#contract-select').evaluate(element => { element.selectedIndex = 1; });
    assert.equal(await page.locator('#contract-select + .app-select .item').textContent(), 'Janeiro');
    await page.locator('#contract-select').evaluate(element => {
      element.innerHTML = '<option value="">Escolha</option><option value="apr" data-group-code="B">Abril</option>';
      element.value = 'apr';
    });
    assert.equal(await page.locator('#contract-select + .app-select .item').textContent(), 'Abril');
    await choose('#contract-select', '');
    assert.equal(await page.locator('#contract-select').evaluate(element => element.reportValidity()), false);
    assert.equal(await page.locator('#contract-select + .app-select .ts-control').getAttribute('aria-invalid'), 'true');
    assert.equal(await page.locator('#contract-select + .app-select').evaluate(element => getComputedStyle(element).paddingRight), '0px', 'validation must not reserve native icon space on the outer wrapper');
    await choose('#contract-select', 'apr');
    assert.equal(await page.locator('#contract-select').evaluate(element => element.checkValidity()), true);
    assert.equal(await page.locator('#contract-select + .app-select .ts-control').getAttribute('aria-invalid'), 'false');

    await page.locator('#select-fieldset').evaluate(element => { element.disabled = true; });
    await page.waitForFunction(() => document.querySelector('#dependent-select').tomselect.isDisabled);
    assert.equal(await page.locator('#dependent-select').evaluate(element => element.disabled), false, 'fieldset must not change the child disabled flag');
    await page.locator('#select-fieldset').evaluate(element => { element.disabled = false; });
    await page.waitForFunction(() => !document.querySelector('#dependent-select').tomselect.isDisabled);
    await choose('#dependent-select', 'FIXO');
    await page.locator('#dependent-select').evaluate(element => { element.querySelector('[value=A]').disabled = true; });
    await page.waitForFunction(() => document.querySelector('#dependent-select').tomselect.options.A.disabled);
    await page.locator('#dependent-select + .app-select .ts-control').click();
    const disabledOption = page.locator('.app-select-menu .option[data-value=A]:visible');
    await disabledOption.click({ force: true });
    assert.equal(await page.locator('#dependent-select').inputValue(), 'FIXO', 'disabled option cannot be selected');
    await page.keyboard.press('Escape');

    await page.locator('#long-select + .app-select .ts-control').click();
    await page.locator('#long-select + .app-select input').fill('Pessoa 74');
    await page.waitForFunction(() => document.querySelector('#long-select').tomselect.lastQuery === 'Pessoa 74');
    await page.keyboard.press('Enter');
    assert.equal(await page.locator('#long-select').inputValue(), '74', 'search includes options beyond the default limit of 50');
    await choose('#multi-select', 'two');
    assert.deepEqual(await page.locator('#multi-select').evaluate(element => new FormData(element.form).getAll('tags[]')), ['one', 'two']);
    await page.locator('#multi-select + .app-select .item[data-value=two] .remove').click();
    assert.deepEqual(await page.locator('#multi-select').evaluate(element => [...element.selectedOptions].map(option => option.value)), ['one']);
    await page.locator('#select-form').evaluate(element => element.reset());
    await page.waitForFunction(() => document.querySelector('#dependent-select').value === 'A' && document.querySelector('#dependent-select').tomselect.getValue() === 'A');

    // Menus are not clipped by narrow, scrolling or modal containers.
    fs.mkdirSync('tmp/browser', { recursive: true });
    for (const width of [1440, 390]) for (const theme of ['light', 'dark']) {
      await page.setViewportSize({ width, height: width === 390 ? 844 : 1000 });
      await page.evaluate(theme => { document.documentElement.dataset.bsTheme = theme; document.documentElement.dataset.colorTheme = 'retro_orange'; }, theme);
      await page.locator('#contract-select + .app-select .ts-control').scrollIntoViewIfNeeded();
      await page.locator('#contract-select + .app-select .ts-control').click();
      const menu = page.locator('.app-select-menu:visible');
      await menu.waitFor({ state: 'visible' });
      assert(await menu.evaluate(element => { const box = element.getBoundingClientRect(); return box.left >= 0 && box.right <= innerWidth + 1 && box.top >= 0 && box.bottom <= innerHeight + 1; }), 'menu fits viewport');
      await page.screenshot({ path: `tmp/browser/app-selects-${theme}-${width}.png` });
      await page.keyboard.press('Escape');
      assert.equal(await menu.isVisible(), false);
    }
    await page.locator('#contract-textarea').screenshot({ path: 'tmp/browser/app-selects-textarea.png' });
    const beforeResize = await page.locator('#contract-textarea').boundingBox();
    await page.mouse.move(beforeResize.x + beforeResize.width - 7, beforeResize.y + beforeResize.height - 7);
    await page.mouse.down();
    await page.mouse.move(beforeResize.x + beforeResize.width - 7, beforeResize.y + beforeResize.height + 53, { steps: 10 });
    await page.mouse.up();
    const afterResize = await page.locator('#contract-textarea').boundingBox();
    assert(afterResize.height > beforeResize.height + 40, 'the styled resize handle still resizes the textarea');
    assert.equal(afterResize.width, beforeResize.width, 'resizing remains vertical');

    // Turbo cache cleanup retains current values, options and original labels.
    await page.locator('#dependent-select').evaluate(element => { element.value = 'FIXO'; });
    await page.evaluate(() => document.dispatchEvent(new Event('turbo:before-cache')));
    assert.equal(await page.locator('.app-select, .app-select-menu').count(), 0);
    assert.equal(await page.locator('#dependent-select').inputValue(), 'FIXO');
    assert.equal(await page.locator('label[for=dependent-select]').count(), 1);
    assert.equal(await page.locator('#contract-select').evaluate(element => element.selectedOptions[0].dataset.groupCode), undefined);
    await page.evaluate(() => window.Stimulus.getControllerForElementAndIdentifier(document.body, 'app-selects').connect());
    await page.waitForFunction(() => document.querySelector('#dependent-select').tomselect);
    assert.equal(await page.locator('#dependent-select + .app-select .item').textContent(), 'Fixo');
    await page.locator('#select-contracts').evaluate(element => element.remove());
    await page.waitForFunction(() => ![...document.querySelectorAll('.app-select-menu')].some(element => element.querySelector('#dependent-select-ts-dropdown')));
    assert.deepEqual(errors, []);
    console.log('PASS: common menus; real dependent fields; native values/events/order/metadata/groups; silent programmatic updates; dynamic options and disabled states; required validation; long-list search; multiple selection/removal; form reset; viewport positioning; textarea resizing; Turbo cleanup and reconnection.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
