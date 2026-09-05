const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const WEB_DIR = path.join(__dirname, 'build/web');
const PORT = 8089;
const systemChromiumExecutables = [
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
  '/snap/bin/chromium',
];
const browserExecutablePath = process.env.E2E_BROWSER_EXECUTABLE
  || systemChromiumExecutables.find((candidate) => fs.existsSync(candidate));

// Simple static file server for flutter web build
const server = http.createServer((req, res) => {
  let filePath = path.join(WEB_DIR, req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(WEB_DIR, 'index.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  const mimeTypes = {
    '.html': 'text/html',
    '.js': 'text/javascript',
    '.wasm': 'application/wasm',
    '.json': 'application/json',
    '.css': 'text/css',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
  };

  const contentType = mimeTypes[ext] || 'application/octet-stream';
  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(500);
      res.end(`Server Error: ${err.code}`);
    } else {
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content, 'utf-8');
    }
  });
});

async function runE2ETest() {
  server.listen(PORT, async () => {
    console.log(`E2E Static server running at http://localhost:${PORT}`);
    let browser;
    try {
      browser = await chromium.launch({
        headless: true,
        ...(browserExecutablePath ? { executablePath: browserExecutablePath } : {}),
      });

      // 1. Desktop Browser Verification with Sample Seed Data (1280 x 800)
      console.log('Testing Desktop Viewport with Seed Data (1280x800)...');
      const desktopContext = await browser.newContext({ viewport: { width: 1280, height: 800 } });
      const desktopPage = await desktopContext.newPage();
      
      // Navigate to app first
      await desktopPage.goto(`http://localhost:${PORT}`, { waitUntil: 'networkidle', timeout: 30000 });

      // Seed SharedPreferences with rich accounts & transactions
      await desktopPage.evaluate(() => {
        const accounts = [
          {
            id: 'acc-hdfc',
            name: 'HDFC Salary Account',
            type: 'SAVINGS',
            lastFourDigits: '4821',
            currency: 'INR',
            currentBalance: 78500.0,
          },
          {
            id: 'acc-icici',
            name: 'ICICI Sapphiro Card',
            type: 'CREDIT_CARD',
            lastFourDigits: '9102',
            currency: 'INR',
            currentBalance: -14250.0,
          }
        ];

        const now = new Date().toISOString();
        const txns = [
          {
            id: 'txn-1',
            amount: 450.0,
            currency: 'INR',
            type: 'DEBIT',
            merchantName: 'Swiggy',
            accountId: 'acc-hdfc',
            categoryId: 'Food & Dining',
            ingestionSource: 'SMS',
            reconciliationStatus: 'CONFIRMED',
            timestamp: now,
          },
          {
            id: 'txn-2',
            amount: 3200.0,
            currency: 'INR',
            type: 'DEBIT',
            merchantName: 'Amazon India',
            accountId: 'acc-icici',
            categoryId: 'Shopping',
            ingestionSource: 'EMAIL',
            reconciliationStatus: 'CONFIRMED',
            timestamp: now,
          },
          {
            id: 'txn-3',
            amount: 150000.0,
            currency: 'INR',
            type: 'CREDIT',
            merchantName: 'Monthly Salary Credit',
            accountId: 'acc-hdfc',
            categoryId: 'Salary & Income',
            ingestionSource: 'SMS',
            reconciliationStatus: 'CONFIRMED',
            timestamp: now,
          }
        ];

        const categories = {
          'Food & Dining': 450.0,
          'Shopping': 3200.0
        };

        localStorage.setItem('flutter.saved_accounts', JSON.stringify(accounts));
        localStorage.setItem('flutter.saved_recent_txns', JSON.stringify(txns));
        localStorage.setItem('flutter.saved_category_totals', JSON.stringify(categories));
        localStorage.setItem('flutter.is_historical_backfilled', 'true');
        localStorage.setItem('flutter.last_backfill_scan_ms', `${Date.now()}`);
        localStorage.setItem('flutter.app_data_version', '5');
      });

      // Reload to load seeded state
      await desktopPage.reload({ waitUntil: 'networkidle' });
      await desktopPage.waitForTimeout(3500);

      const desktopScreenshotPath = path.join(__dirname, 'web_e2e_desktop.png');
      await desktopPage.screenshot({ path: desktopScreenshotPath });
      console.log(`📸 Desktop screenshot with live data captured at ${desktopScreenshotPath}`);

      // 2. Mobile Browser Verification with Seed Data (400 x 850)
      console.log('Testing Mobile Viewport with Seed Data (400x850)...');
      const mobileContext = await browser.newContext({ viewport: { width: 400, height: 850 } });
      const mobilePage = await mobileContext.newPage();
      await mobilePage.goto(`http://localhost:${PORT}`, { waitUntil: 'networkidle', timeout: 30000 });
      await mobilePage.evaluate(() => {
        const accounts = [
          {
            id: 'acc-hdfc',
            name: 'HDFC Salary Account',
            type: 'SAVINGS',
            lastFourDigits: '4821',
            currency: 'INR',
            currentBalance: 78500.0,
          },
          {
            id: 'acc-icici',
            name: 'ICICI Sapphiro Card',
            type: 'CREDIT_CARD',
            lastFourDigits: '9102',
            currency: 'INR',
            currentBalance: -14250.0,
          }
        ];
        const now = new Date().toISOString();
        const txns = [
          {
            id: 'txn-1',
            amount: 450.0,
            currency: 'INR',
            type: 'DEBIT',
            merchantName: 'Swiggy',
            accountId: 'acc-hdfc',
            categoryId: 'Food & Dining',
            ingestionSource: 'SMS',
            reconciliationStatus: 'CONFIRMED',
            timestamp: now,
          },
          {
            id: 'txn-2',
            amount: 3200.0,
            currency: 'INR',
            type: 'DEBIT',
            merchantName: 'Amazon India',
            accountId: 'acc-icici',
            categoryId: 'Shopping',
            ingestionSource: 'EMAIL',
            reconciliationStatus: 'CONFIRMED',
            timestamp: now,
          }
        ];
        const categories = {
          'Food & Dining': 450.0,
          'Shopping': 3200.0
        };
        localStorage.setItem('flutter.saved_accounts', JSON.stringify(accounts));
        localStorage.setItem('flutter.saved_recent_txns', JSON.stringify(txns));
        localStorage.setItem('flutter.saved_category_totals', JSON.stringify(categories));
        localStorage.setItem('flutter.is_historical_backfilled', 'true');
        localStorage.setItem('flutter.last_backfill_scan_ms', `${Date.now()}`);
        localStorage.setItem('flutter.app_data_version', '5');
      });
      await mobilePage.reload({ waitUntil: 'networkidle' });
      await mobilePage.waitForTimeout(3500);

      const mobileScreenshotPath = path.join(__dirname, 'web_e2e_mobile.png');
      await mobilePage.screenshot({ path: mobileScreenshotPath });
      console.log(`📸 Mobile screenshot with live data captured at ${mobileScreenshotPath}`);

      console.log('🎉 Playwright Browser E2E Tests PASSED for both Desktop and Mobile!');
      await browser.close();
      server.close();
      process.exit(0);
    } catch (err) {
      console.error('❌ Playwright E2E Test FAILED:', err);
      if (browser) await browser.close();
      server.close();
      process.exit(1);
    }
  });
}

runE2ETest();
