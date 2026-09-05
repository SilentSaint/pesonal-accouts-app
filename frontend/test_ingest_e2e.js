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

  console.log('Clicking Import Text button at x=195, y=120...');
  await page.mouse.click(195, 120);
  await page.waitForTimeout(1000);

  console.log('Clicking inside TextField at x=500, y=490...');
  await page.mouse.click(500, 490);
  await page.waitForTimeout(1000);

  console.log('Focusing textarea and typing text...');
  const ta = page.locator('textarea.flt-text-editing');
  await ta.focus();

  const lines = [
    'Available balance in your account ending XX1277 is Rs. INR 50,868.64 as on 03-AUG-26.',
    'Dear Customer, Greetings from HDFC Bank! Rs.2650.00 is debited from your account ending 1277 towards VPA 7813004130@axl (RAKSHITH GOWDA G) on 04-08-26.',
    'Dear Rakshith, Summary of your transaction: Amount Credited: INR 2650.00 Account Number: XX9343 Date: 04-08-26.',
    'Rs. 706.82 has been debited from your HDFC Bank Credit Card ending 9207 towards HDFCBPBAND on 04-08-26.',
    'Dear Customer, Rs.410.00 is debited from account ending 8173 towards VPA chicken.center@upi (CHICKEN CENTER) on 03-08-26.'
  ];

  for (const line of lines) {
    await page.keyboard.type(line);
    await page.keyboard.press('Enter');
  }
  await page.waitForTimeout(1000);

  console.log('Clicking "Parse & Ingest" button at x=650, y=630...');
  await page.mouse.click(650, 630);
  await page.waitForTimeout(3000);

  const screenshotPath = '/home/rakshith/.gemini/antigravity/brain/2db89aab-e412-4a1d-a4da-9959c0cfa59d/live_accounts_grid_ingested.png';
  await page.screenshot({ path: screenshotPath, fullPage: false });
  console.log('Saved screenshot to:', screenshotPath);

  await browser.close();
})();
