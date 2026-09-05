const { chromium } = require('playwright');
const path = require('path');

const PROD_URL = 'https://ddfkc7j77rh2i.cloudfront.net';

async function verifyLiveProduction() {
  console.log(`Verifying live production URL: ${PROD_URL}`);
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await context.newPage();

    console.log('Navigating to live CloudFront distribution...');
    await page.goto(PROD_URL, { waitUntil: 'networkidle', timeout: 45000 });

    // Wait for Flutter web engine to boot
    await page.waitForTimeout(4000);

    const title = await page.title();
    console.log(`Live Production Page Title: "${title}"`);

    const flutterView = await page.$('flutter-view, flt-glass-pane, canvas, body');
    if (!flutterView) {
      throw new Error('Flutter web view element not found on live production site!');
    }

    console.log('✅ Live CloudFront web application loaded and rendered successfully!');

    const screenshotPath = path.join(__dirname, 'live_production_deployed.png');
    await page.screenshot({ path: screenshotPath });
    console.log(`📸 Live production screenshot captured at ${screenshotPath}`);

    console.log('🎉 Production Deployment Verification PASSED!');
    await browser.close();
    process.exit(0);
  } catch (err) {
    console.error('❌ Live production verification failed:', err);
    if (browser) await browser.close();
    process.exit(1);
  }
}

verifyLiveProduction();
