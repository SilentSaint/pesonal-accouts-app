const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    executablePath: '/home/rakshith/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage({ viewport: { width: 1280, height: 950 } });
  await page.goto('http://localhost:8088', { waitUntil: 'networkidle' });
  await page.waitForTimeout(3500);

  console.log('Clicking "+ Add Account" button at x=285, y=120...');
  await page.mouse.click(285, 120);
  await page.waitForTimeout(1500);

  await page.screenshot({ path: '/home/rakshith/.gemini/antigravity/brain/2db89aab-e412-4a1d-a4da-9959c0cfa59d/live_add_dialog.png' });
  console.log('Saved live_add_dialog.png!');

  await browser.close();
})();
