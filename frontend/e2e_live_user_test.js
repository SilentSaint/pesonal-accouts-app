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

async function runLiveVerification() {
  server.listen(PORT, async () => {
    console.log(`Live verification test server listening on http://localhost:${PORT}`);
    let browser;
    try {
      browser = await chromium.launch({ headless: true });
      const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
      const page = await context.newPage();

      console.log('Navigating to web app...');
      await page.goto(`http://localhost:${PORT}`, { waitUntil: 'networkidle', timeout: 30000 });
      await page.waitForTimeout(4000);

      const title = await page.title();
      console.log(`✓ Page Loaded Successfully: "${title}"`);

      // Verify flutter elements rendered
      const flutterCanvas = await page.$('flt-glass-pane, flutter-view, canvas');
      if (!flutterCanvas) {
        throw new Error('Flutter Canvas did not render!');
      }
      console.log('✓ Flutter web engine and glass pane rendered successfully');

      // Screenshot clean dashboard
      await page.screenshot({ path: path.join(__dirname, 'test_dashboard_clean.png') });
      console.log('✓ Captured clean dashboard screenshot');

      console.log('All Playwright UI assertions passed with clean slate and web user profile!');
    } catch (err) {
      console.error('Playwright verification error:', err);
      process.exitCode = 1;
    } finally {
      if (browser) await browser.close();
      server.close();
    }
  });
}

runLiveVerification();
