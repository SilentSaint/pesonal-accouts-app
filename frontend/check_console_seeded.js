const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    executablePath: '/home/rakshith/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage({ viewport: { width: 1280, height: 950 } });
  page.on('console', msg => console.log('PAGE LOG:', msg.text()));
  page.on('pageerror', err => console.log('PAGE ERROR:', err.message));

  await page.goto('http://localhost:8088', { waitUntil: 'networkidle' });
  await page.waitForTimeout(1000);

  await page.evaluate(() => {
    localStorage.setItem('app_data_version', '5');
    localStorage.setItem('flutter.app_data_version', '5');
    localStorage.setItem('flutter.saved_accounts', 'test');
  });

  console.log('Reloading with test keys...');
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForTimeout(3000);
  await browser.close();
})();
