const { chromium } = require('playwright');
const path = require('path');

const PROD_URL = 'https://ddfkc7j77rh2i.cloudfront.net';

async function testTargetedClick() {
  console.log(`🌐 Connecting to: ${PROD_URL}`);
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();

  await page.goto(PROD_URL, { waitUntil: 'networkidle', timeout: 45000 });
  await page.waitForTimeout(3000);

  const flutterView = page.locator('flutter-view, canvas, body').first();

  // "Scan 30 Days" button position (approx x: 930, y: 138)
  console.log('👉 Clicking Scan 30 Days button at x: 930, y: 138...');
  await flutterView.click({ position: { x: 930, y: 138 } });
  await page.waitForTimeout(2000);

  const shot1 = path.join(__dirname, 'prod_dialog_opened.png');
  await page.screenshot({ path: shot1 });
  console.log(`📸 Screenshot 1: ${shot1}`);

  // Click "Got it" button (center bottom of dialog, approx x: 675, y: 480)
  console.log('👉 Clicking "Got it" button...');
  await flutterView.click({ position: { x: 675, y: 480 } });
  await page.waitForTimeout(1000);

  const shot2 = path.join(__dirname, 'prod_after_dismiss.png');
  await page.screenshot({ path: shot2 });
  console.log(`📸 Screenshot 2: ${shot2}`);

  // Click "Check Incremental" button (approx x: 930, y: 138)
  console.log('👉 Clicking "Check Incremental" button...');
  await flutterView.click({ position: { x: 930, y: 138 } });
  await page.waitForTimeout(1000);

  const shot3 = path.join(__dirname, 'prod_incremental_snack.png');
  await page.screenshot({ path: shot3 });
  console.log(`📸 Screenshot 3: ${shot3}`);

  await browser.close();
  process.exit(0);
}

testTargetedClick();
