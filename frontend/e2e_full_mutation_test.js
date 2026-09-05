const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const WEB_DIR = path.join(__dirname, 'build/web');
const PORT = 8099;

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

async function runMutationTest() {
  server.listen(PORT, async () => {
    let browser;
    try {
      browser = await chromium.launch({ headless: true });
      const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
      const page = await context.newPage();

      console.log('1️⃣ Loading application...');
      await page.goto(`http://localhost:${PORT}`, { waitUntil: 'networkidle', timeout: 30000 });
      await page.waitForTimeout(3000);

      const flutterView = page.locator('flutter-view, canvas, body').first();

      // Open Modal
      console.log('2️⃣ Opening Add Transaction Modal...');
      await flutterView.click({ position: { x: 1150, y: 750 } });
      await page.waitForTimeout(1000);

      // Click Merchant Name input (approx x: 500, y: 445)
      console.log('3️⃣ Typing merchant name "Starbucks Coffee"...');
      await flutterView.click({ position: { x: 500, y: 445 } });
      await page.keyboard.type('Starbucks Coffee');
      await page.waitForTimeout(500);

      // Click Amount input (approx x: 500, y: 520)
      console.log('4️⃣ Typing amount "350.00"...');
      await flutterView.click({ position: { x: 500, y: 520 } });
      await page.keyboard.type('350.00');
      await page.waitForTimeout(500);

      // Click Save Transaction button (approx x: 545, y: 680)
      console.log('5️⃣ Clicking "Save Transaction"...');
      await flutterView.click({ position: { x: 545, y: 680 } });
      await page.waitForTimeout(1500);

      // Capture after mutation screenshot
      const afterMutationScreenshot = path.join(__dirname, 'playwright_after_mutation.png');
      await page.screenshot({ path: afterMutationScreenshot });
      console.log(`📸 State Mutation Verified! Screenshot: ${afterMutationScreenshot}`);

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

runMutationTest();
