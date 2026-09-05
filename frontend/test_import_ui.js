const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    executablePath: '/home/rakshith/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage({ viewport: { width: 1280, height: 950 } });
  await page.goto('http://localhost:8088', { waitUntil: 'networkidle' });
  await page.waitForTimeout(3000);

  // Click Import Text button (in hero card next to TOTAL NET LIQUIDITY)
  console.log('Finding Import Text button...');
  // Find element with text "Import Text"
  await page.locator('text=Import Text').first().click();
  await page.waitForTimeout(1500);

  await page.screenshot({ path: '/home/rakshith/.gemini/antigravity/brain/2db89aab-e412-4a1d-a4da-9959c0cfa59d/live_import_modal.png' });
  console.log('Saved modal screenshot!');

  await browser.close();
})();
