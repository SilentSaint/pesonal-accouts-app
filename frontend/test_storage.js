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

  const keys = await page.evaluate(() => {
    return Object.keys(localStorage);
  });
  console.log('Existing localStorage keys:', keys);
  await browser.close();
})();
