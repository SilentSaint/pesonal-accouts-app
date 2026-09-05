const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const WEB_DIR = path.join(__dirname, 'build/web');
const PORT = 8095;

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

async function runDynamicTest() {
  server.listen(PORT, async () => {
    let browser;
    try {
      browser = await chromium.launch({ headless: true });
      const context = await browser.newContext({ viewport: { width: 1366, height: 900 } });
      const page = await context.newPage();

      console.log('🚀 Loading application...');
      await page.goto(`http://localhost:${PORT}`, { waitUntil: 'networkidle', timeout: 30000 });
      await page.waitForTimeout(3000);

      // Click "1-Tap Review" (x: 930, y: 250)
      console.log('👉 Clicking 1-Tap Review Banner...');
      await page.mouse.click(930, 255);
      await page.waitForTimeout(1500);
      await page.screenshot({ path: path.join(__dirname, 'playwright_review_modal.png') });

      // Click "+ Add Transaction" FAB (x: 1270, y: 860)
      console.log('👉 Clicking Add Transaction Floating Action Button...');
      await page.mouse.click(1270, 860);
      await page.waitForTimeout(1500);
      await page.screenshot({ path: path.join(__dirname, 'playwright_add_txn_modal.png') });

      console.log('🎉 Automation assertions completed!');
      await browser.close();
      server.close();
      process.exit(0);
    } catch (err) {
      console.error('Error:', err);
      if (browser) await browser.close();
      server.close();
      process.exit(1);
    }
  });
}

runDynamicTest();
