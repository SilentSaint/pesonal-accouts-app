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

  // Click "+ Add Your Bank Account"
  const addBtn = page.getByText('Add Your Bank Account');
  if (await addBtn.isVisible()) {
    console.log('Clicking Add Your Bank Account...');
    await addBtn.click();
    await page.waitForTimeout(1000);
    // Fill in Account Name
    await page.keyboard.type('HDFC Bank');
    await page.keyboard.press('Tab');
    await page.keyboard.type('1277');
    await page.keyboard.press('Tab');
    await page.keyboard.type('50868.64');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(2000);
  }

  const items = await page.evaluate(() => {
    const res = {};
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      res[k] = localStorage.getItem(k);
    }
    return res;
  });
  console.log('localStorage content:', JSON.stringify(items, null, 2));

  await page.screenshot({ path: '/home/rakshith/.gemini/antigravity/brain/2db89aab-e412-4a1d-a4da-9959c0cfa59d/live_after_add.png' });
  await browser.close();
})();
