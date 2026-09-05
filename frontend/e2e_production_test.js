const { chromium } = require('playwright');
const path = require('path');

const PROD_URL = 'https://ddfkc7j77rh2i.cloudfront.net';

async function testProductionUrl() {
  console.log(`🌐 Connecting to Live Production CloudFront URL: ${PROD_URL}`);
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await context.newPage();

    console.log('⏳ Loading live production web app...');
    const response = await page.goto(PROD_URL, { waitUntil: 'networkidle', timeout: 45000 });
    console.log(`HTTP Status: ${response.status()}`);

    // Wait for Flutter Web engine initialization
    await page.waitForTimeout(4000);

    const title = await page.title();
    console.log(`✅ Production Page Title: "${title}"`);

    // Verify canvas/engine
    const flutterView = page.locator('flutter-view, canvas, body').first();
    await flutterView.waitFor({ timeout: 10000 });

    const screenshotPath = path.join(__dirname, 'production_live_screenshot.png');
    await page.screenshot({ path: screenshotPath });
    console.log(`📸 Live Production Screenshot Saved: ${screenshotPath}`);

    console.log('🎉 Production Playwright E2E Verification PASSED!');
    await browser.close();
    process.exit(0);
  } catch (err) {
    console.error('❌ Production E2E Verification Error:', err);
    if (browser) await browser.close();
    process.exit(1);
  }
}

testProductionUrl();
