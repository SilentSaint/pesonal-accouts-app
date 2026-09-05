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

  // Click "+ Add Account"
  await page.mouse.click(285, 120);
  await page.waitForTimeout(1000);

  // Click Account Name field at (500, 370)
  await page.mouse.click(500, 370);
  await page.keyboard.type('HDFC Bank');
  await page.keyboard.press('Tab');
  await page.keyboard.type('1277');
  await page.keyboard.press('Tab');
  await page.keyboard.type('50868.64');
  await page.keyboard.press('Tab');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(2000);

  const keys = await page.evaluate(() => {
    const res = {};
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      res[k] = localStorage.getItem(k);
    }
    return res;
  });
  console.log('All localStorage entries after Add Account:', JSON.stringify(keys, null, 2));

  await page.screenshot({ path: '/home/rakshith/.gemini/antigravity/brain/2db89aab-e412-4a1d-a4da-9959c0cfa59d/live_after_add_modal.png' });
  await browser.close();
})();
