// Interact with the displayed app menu; the native select remains the form field.
module.exports = async function chooseSelect(page, select, choice) {
  const enhanced = await select.evaluate(element => Boolean(element.tomselect));
  if (!enhanced) return select.selectOption(choice);
  const option = await select.evaluate((element, choice) => {
    const found = [...element.options].find(option => typeof choice === 'object'
      ? option.textContent.trim().replace(/\s+/g, ' ') === choice.label
      : option.value === String(choice));
    if (!found) throw new Error(`Option not found: ${JSON.stringify(choice)}`);
    return { label: found.textContent.trim().replace(/\s+/g, ' '), menuId: element.tomselect.dropdown_content.id };
  }, choice);
  await select.locator('xpath=following-sibling::*[1]').locator('.ts-control').click();
  const menu = page.locator(`[id="${option.menuId}"]`);
  await menu.waitFor({ state: 'visible' });
  await menu.getByRole('option', { name: option.label, exact: true }).click();
};
