const { chromium } = require('playwright');

(async () => {
  console.log('🌐 Testing live Flutter Web App with request tracing and DOM inputs...');
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();

  page.on('request', req => {
    if (req.url().includes('execute-api')) {
      console.log('🚀 HTTP REQUEST:', req.method(), req.url(), req.postData());
    }
  });

  page.on('response', res => {
    if (res.url().includes('execute-api')) {
      console.log('📥 HTTP RESPONSE:', res.status(), res.url());
    }
  });

  page.on('console', msg => console.log('🖥️ BROWSER CONSOLE:', msg.text()));

  await page.goto('https://ddfkc7j77rh2i.cloudfront.net', { waitUntil: 'networkidle', timeout: 45000 });
  await page.waitForTimeout(4000);

  // Click "+ Add Transaction" FAB at (1200, 745)
  console.log('👆 Clicking "+ Add Transaction" FAB at (1200, 745)...');
  await page.mouse.click(1200, 745);
  await page.waitForTimeout(1500);

  // Focus the first textfield
  await page.mouse.click(500, 440);
  await page.waitForTimeout(500);

  // Check inputs in DOM
  const inputs = await page.$$('input');
  console.log(`Found ${inputs.length} DOM input elements.`);
  if (inputs.length > 0) {
    await inputs[inputs.length - 1].fill('Swiggy Order');
  }

  // Focus second textfield
  await page.mouse.click(500, 510);
  await page.waitForTimeout(500);
  const inputs2 = await page.$$('input');
  if (inputs2.length > 0) {
    await inputs2[inputs2.length - 1].fill('450');
  }

  await page.screenshot({ path: '/home/rakshith/Antigravity/AutomaticExpenseTracker/frontend/prod_dialog_filled.png' });

  // Click "Save Transaction" at (546, 686)
  await page.mouse.click(546, 686);
  await page.waitForTimeout(4000);

  await page.screenshot({ path: '/home/rakshith/Antigravity/AutomaticExpenseTracker/frontend/prod_after_save_traced.png' });

  await browser.close();
  console.log('✅ Tracing complete.');
})();
