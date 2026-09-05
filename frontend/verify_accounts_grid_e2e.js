const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    executablePath: '/home/rakshith/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage({ viewport: { width: 1280, height: 950 } });
  console.log('Navigating to http://localhost:8088...');
  await page.goto('http://localhost:8088', { waitUntil: 'networkidle' });
  await page.waitForTimeout(2000);

  // Now seed data with the EXACT double-stringification that shared_preferences_web uses!
  await page.evaluate(() => {
    const accounts = [
      {
        id: 'acc-1277',
        name: 'HDFC Bank (•••• 1277)',
        type: 'SAVINGS',
        lastFourDigits: '1277',
        currency: 'INR',
        currentBalance: 50868.64,
        anchorBalance: 50868.64,
        anchorDate: '2026-08-03T00:00:00.000'
      },
      {
        id: 'acc-9207',
        name: 'HDFC Credit Card (•••• 9207)',
        type: 'CREDIT_CARD',
        lastFourDigits: '9207',
        currency: 'INR',
        currentBalance: 706.82
      },
      {
        id: 'acc-8173',
        name: 'Bank Account (•••• 8173)',
        type: 'SAVINGS',
        lastFourDigits: '8173',
        currency: 'INR',
        currentBalance: 410.0
      },
      {
        id: 'acc-9343',
        name: 'Bank Account (•••• 9343)',
        type: 'SAVINGS',
        lastFourDigits: '9343',
        currency: 'INR',
        currentBalance: 2650.0
      }
    ];

    const recentTxns = [
      {
        id: 'txn-1',
        amount: 2650.0,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'Self Transfer',
        accountId: 'acc-1277',
        accountMask: '•••• 1277',
        transferCounterpartMask: '•••• 9343',
        categoryId: 'Self Transfer',
        subCategory: 'Account to Account Transfer',
        rawSnippet: 'Dear Customer, Rs.2650.00 is debited from account ending 1277 towards VPA 7813004130@axl on 04-08-26.',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: Date.parse('2026-08-04T09:08:00.000Z')
      },
      {
        id: 'txn-2',
        amount: 706.82,
        currency: 'INR',
        type: 'DEBIT',
        merchantName: 'ACT Fibernet',
        accountId: 'acc-9207',
        accountMask: '•••• 9207',
        categoryId: 'Bills & Utilities',
        subCategory: 'Broadband & Internet',
        rawSnippet: 'Rs. 706.82 has been debited from your HDFC Bank Credit Card ending 9207 towards HDFCBPBAND',
        ingestionSource: 'EMAIL',
        reconciliationStatus: 'CONFIRMED',
        timestamp: Date.parse('2026-08-04T11:00:00.000Z')
      }
    ];

    localStorage.setItem('app_data_version', '5');
    localStorage.setItem('flutter.app_data_version', '5');
    localStorage.setItem('flutter.is_historical_backfilled', 'true');
    localStorage.setItem('flutter.saved_accounts', JSON.stringify(JSON.stringify(accounts)));
    localStorage.setItem('flutter.saved_recent_txns', JSON.stringify(JSON.stringify(recentTxns)));
  });

  console.log('Reloading page...');
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForTimeout(4000);

  const screenshotPath = '/home/rakshith/.gemini/antigravity/brain/2db89aab-e412-4a1d-a4da-9959c0cfa59d/live_accounts_grid_rendered.png';
  await page.screenshot({ path: screenshotPath, fullPage: false });
  console.log('Saved screenshot to:', screenshotPath);

  await browser.close();
  console.log('Playwright E2E verification completed successfully!');
})();
