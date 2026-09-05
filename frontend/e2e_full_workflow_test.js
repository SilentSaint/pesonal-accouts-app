const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const WEB_DIR = path.join(__dirname, 'build/web');
const PORT = 8092;

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

async function runAutomation() {
  server.listen(PORT, async () => {
    console.log(`🌐 Playwright Automation Server running on http://localhost:${PORT}`);
    let browser;
    try {
      browser = await chromium.launch({ headless: true });
      const context = await browser.newContext({ viewport: { width: 1366, height: 900 } });
      const page = await context.newPage();

      console.log('1️⃣ Navigating to Production Web Application...');
      await page.goto(`http://localhost:${PORT}`, { waitUntil: 'networkidle', timeout: 30000 });
      await page.waitForTimeout(3500);

      const title = await page.title();
      console.log(`✅ App Loaded! Title: "${title}"`);

      // 1. Capture Initial Dashboard Screenshot
      const screenshot1 = path.join(__dirname, 'playwright_step1_dashboard.png');
      await page.screenshot({ path: screenshot1 });
      console.log(`📸 Step 1 Screenshot: ${screenshot1}`);

      // 2. Perform Click on 30-Day Auto Backfill
      console.log('2️⃣ Triggering 30-Day Automated Backfill...');
      await page.mouse.click(1250, 140); // Approximate position of "Scan 30 Days" button
      await page.waitForTimeout(2500);

      const screenshot2 = path.join(__dirname, 'playwright_step2_backfilled.png');
      await page.screenshot({ path: screenshot2 });
      console.log(`📸 Step 2 Screenshot (After Backfill): ${screenshot2}`);

      // 3. Open Peer Debt Ledger
      console.log('3️⃣ Navigating to Peer Debt & Lending Ledger...');
      await page.mouse.click(1040, 36); // Peer Debt icon in AppBar
      await page.waitForTimeout(1500);

      const screenshot3 = path.join(__dirname, 'playwright_step3_peer_debt.png');
      await page.screenshot({ path: screenshot3 });
      console.log(`📸 Step 3 Screenshot (Peer Debt Screen): ${screenshot3}`);

      // 4. Open Card EMI Screen
      console.log('4️⃣ Navigating to Credit Card EMI Schedules...');
      await page.mouse.click(1125, 36); // Card EMI icon
      await page.waitForTimeout(1500);

      const screenshot4 = path.join(__dirname, 'playwright_step4_card_emi.png');
      await page.screenshot({ path: screenshot4 });
      console.log(`📸 Step 4 Screenshot (Card EMI Screen): ${screenshot4}`);

      // 5. Open Monthly Budgets & Alerts Screen
      console.log('5️⃣ Navigating to Monthly Category Budgets...');
      await page.mouse.click(1210, 36); // Budget Screen icon
      await page.waitForTimeout(1500);

      const screenshot5 = path.join(__dirname, 'playwright_step5_budgets.png');
      await page.screenshot({ path: screenshot5 });
      console.log(`📸 Step 5 Screenshot (Budget Screen): ${screenshot5}`);

      // 6. Open Analytics & AI Insights Screen
      console.log('6️⃣ Navigating to Financial Analytics & AI Insights...');
      await page.mouse.click(1250, 36); // Analytics icon
      await page.waitForTimeout(1500);

      const screenshot6 = path.join(__dirname, 'playwright_step6_analytics.png');
      await page.screenshot({ path: screenshot6 });
      console.log(`📸 Step 6 Screenshot (Analytics Screen): ${screenshot6}`);

      // 7. Lock Application with Security Lock
      console.log('7️⃣ Triggering Security Lock...');
      await page.mouse.click(1335, 36); // Lock icon
      await page.waitForTimeout(1500);

      const screenshot7 = path.join(__dirname, 'playwright_step7_locked.png');
      await page.screenshot({ path: screenshot7 });
      console.log(`📸 Step 7 Screenshot (Biometric & PIN Lock Screen): ${screenshot7}`);

      console.log('✨ All 7 E2E Playwright Automation Steps Completed Successfully!');
      await browser.close();
      server.close();
      process.exit(0);
    } catch (err) {
      console.error('❌ Automation Error:', err);
      if (browser) await browser.close();
      server.close();
      process.exit(1);
    }
  });
}

runAutomation();
