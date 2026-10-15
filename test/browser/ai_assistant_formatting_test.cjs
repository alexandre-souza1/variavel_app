// BASE_URL=http://127.0.0.1:4325 node test/browser/ai_assistant_formatting_test.cjs
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');

(async () => {
  const base = process.env.BASE_URL || 'http://127.0.0.1:4325';
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1366, height: 900 } });
    page.setDefaultTimeout(15000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(`${base}/users/sign_in`);
    await page.locator('#user_email').fill('user_one@example.com');
    await page.locator('#user_password').fill('password');
    await page.locator('input[type=submit]').click();
    await page.waitForURL(url => !url.pathname.includes('sign_in'));
    const literalQuestion = '**Meu texto** <img src=x onerror="window.aiInjected=true">';
    const summary = 'Resumo do seu dia hoje (setor **Frota**):\n\n' +
      '- **Tarefas pessoais:** 7 tarefas pendentes/vencidas.\n' +
      'Nenhuma com prazo para hoje.\n' +
      '- **Indicadores / GEROTs:** 21 preenchimentos previstos, 16 pendentes.\n' +
      '- **Financeiro:** Gasto total no mês de **R$ 51.771,17**.\n' +
      '- **Frota:** Verifique a disponibilidade dos veículos.\n\n' +
      'Consulte os registros para mais detalhes.';
    const safety = '### Próximos passos\n1. Conferir `ABC-1234`.\n2. Verificar os pneus.\n\n' +
      'Texto com *ênfase* e __destaque__.\n\n' +
      '<img src=x onerror="window.aiInjected=true">\n' +
      '<button onclick="window.aiInjected=true">Confirmar</button>\n' +
      '<script>window.aiInjected=true</script>\n' +
      '[Executar](javascript:alert(1))\n\n' +
      '```html\n<img src=x onerror="window.aiInjected=true">\n**Exemplo literal**\n```';
    await page.route('**/assistente-ia', route => route.fulfill({ json: {
      processing: false, error: null, messages: [
        { id: 1, role: 'user', content: literalQuestion, sources: [] },
        { id: 2, role: 'assistant', content: summary, sources: [{ label: 'Tarefas', path: '/action_plans' }] },
        { id: 3, role: 'assistant', content: safety, sources: [] }
      ]
    } }));
    await page.goto(`${base}/variaveis`);
    await page.locator('.ai-assistant__launcher').click();
    const first = page.locator('.ai-assistant__content').nth(0);
    const second = page.locator('.ai-assistant__content').nth(1);
    await first.locator('ul li').first().waitFor();
    assert.equal(await first.locator('ul li').count(), 4);
    assert.equal(await first.locator('strong').first().innerText(), 'Frota');
    assert((await first.locator('strong').allTextContents()).includes('R$ 51.771,17'));
    assert.equal((await first.innerText()).includes('**'), false);
    assert.equal(await second.locator('h6').innerText(), 'Próximos passos');
    assert.equal(await second.locator('ol li').count(), 2);
    assert.equal(await second.locator('em').innerText(), 'ênfase');
    assert.equal(await second.locator('pre code').innerText(), '<img src=x onerror="window.aiInjected=true">\n**Exemplo literal**\n');
    assert.equal(await page.locator('.ai-assistant__message--user p').innerText(), literalQuestion);
    assert.equal(await page.locator('.ai-assistant__content img, .ai-assistant__content script, .ai-assistant__content button, .ai-assistant__content a').count(), 0);
    assert.equal(await page.locator('.ai-assistant__sources a').count(), 1);
    assert.equal(await page.evaluate(() => window.aiInjected), undefined);
    assert(await first.locator('ul').evaluate(el => parseFloat(getComputedStyle(el).marginTop) > 0));
    fs.mkdirSync('tmp/ai-formatting', { recursive: true });
    for (const width of [1366, 390, 320]) {
      await page.setViewportSize({ width, height: 900 });
      await page.locator('.ai-assistant__messages').evaluate(el => el.scrollTop = 0);
      for (const theme of ['light', 'dark']) {
        await page.evaluate(theme => document.documentElement.dataset.bsTheme = theme, theme);
        assert(await page.locator('.ai-assistant__panel').evaluate(el => el.scrollWidth <= el.clientWidth));
        await page.screenshot({ path: `tmp/ai-formatting/${width}-${theme}.png` });
      }
    }
    assert.deepEqual(errors, []);
    console.log('PASS: daily briefing formatting, paragraphs, bold, ordered/unordered lists, headings, code, literal user messages, safe HTML/link handling and responsive light/dark layouts.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
