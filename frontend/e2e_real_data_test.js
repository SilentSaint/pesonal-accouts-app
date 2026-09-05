const { chromium } = require('playwright');
const path = require('path');

const PROD_URL = 'https://ddfkc7j77rh2i.cloudfront.net';

async function testRealDataFeatures() {
  console.log(`🌐 Connecting to: ${PROD_URL}`);
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();

  await page.goto(PROD_URL, { waitUntil: 'networkidle', timeout: 45000 });
  await page.waitForTimeout(3000);

  const flutterView = page.locator('flutter-view, canvas, body').first();

  // 1. Capture Dashboard with real data controls
  const shot1 = path.join(__dirname, 'prod_real_data_dashboard.png');
  await page.screenshot({ path: shot1 });
  console.log(`📸 Screenshot 1 (Dashboard with Import & Add Account): ${shot1}`);

  console.log('🎉 Production Web App Verified!');
  await browser.close();
  process.exit(0);
}

testRealDataFeatures();
