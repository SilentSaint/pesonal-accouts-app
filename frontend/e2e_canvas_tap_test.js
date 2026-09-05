const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const WEB_DIR = path.join(__dirname, 'build/web');
const PORT = 8098;

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

async function runTapTest() {
  server.listen(PORT, async () => {
    let browser;
    try {
      browser = await chromium.launch({ headless: true });
      const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
      const page = await context.newPage();

      console.log('🚀 Loading application...');
      await page.goto(`http://localhost:${PORT}`, { waitUntil: 'networkidle', timeout: 30000 });
      await page.waitForTimeout(3000);

      // Locate the flutter-view element
      const flutterView = page.locator('flutter-view, canvas, body').first();

      // Click on FAB "+ Add Transaction" (approx bottom right of 1280x800: x=1150, y=750)
      console.log('👉 Tapping Floating Action Button via Flutter View...');
      await flutterView.click({ position: { x: 1150, y: 750 } });
      await page.waitForTimeout(1000);

      await page.screenshot({ path: path.join(__dirname, 'playwright_fab_dialog.png') });
      console.log('📸 FAB dialog screenshot captured!');

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

runTapTest();
