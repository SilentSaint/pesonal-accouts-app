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

  await page.mouse.click(195, 120);
  await page.waitForTimeout(1000);
  await page.mouse.click(500, 490);
  await page.waitForTimeout(500);

  const inputs = await page.evaluate(() => {
    return Array.from(document.querySelectorAll('input, textarea')).map(el => ({
      tagName: el.tagName,
      id: el.id,
      className: el.className,
      value: el.value,
      type: el.type
    }));
  });
  console.log('DOM inputs found:', JSON.stringify(inputs, null, 2));

  await browser.close();
})();
