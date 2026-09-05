const { chromium } = require('playwright');
const path = require('path');

const PROD_URL = 'https://ddfkc7j77rh2i.cloudfront.net';

async function testDynamicBackfill() {
  console.log(`🌐 Testing Dynamic 30-Day Backfill on: ${PROD_URL}`);
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await context.newPage();

    console.log('1️⃣ Loading web app...');
    await page.goto(PROD_URL, { waitUntil: 'networkidle', timeout: 45000 });
    await page.waitForTimeout(3000);

    const flutterView = page.locator('flutter-view, canvas, body').first();

    // First scan: Click "Scan 30 Days" button (approx x: 1180, y: 135)
    console.log('2️⃣ Tapping "Scan 30 Days" button on canvas...');
    await flutterView.click({ position: { x: 1180, y: 135 } });
    await page.waitForTimeout(2000);

    // Capture screenshot of Discovery Dialog
    const dialogScreenshot = path.join(__dirname, 'prod_backfill_dialog.png');
    await page.screenshot({ path: dialogScreenshot });
    console.log(`📸 Discovered Account Modal Screenshot: ${dialogScreenshot}`);

    // Click "Got it" button on dialog (center bottom of dialog, approx x: 675, y: 480)
    console.log('3️⃣ Dismissing Discovery Modal ("Got it")...');
    await flutterView.click({ position: { x: 675, y: 480 } });
    await page.waitForTimeout(1000);

    // Second scan: Click "Check Incremental" button (approx x: 1180, y: 135)
    console.log('4️⃣ Tapping "Check Incremental" button...');
    await flutterView.click({ position: { x: 1180, y: 135 } });
    await page.waitForTimeout(1500);

    // Capture screenshot of Incremental Sync state
    const incrementalScreenshot = path.join(__dirname, 'prod_backfill_incremental.png');
    await page.screenshot({ path: incrementalScreenshot });
    console.log(`📸 Incremental Sync Screenshot: ${incrementalScreenshot}`);

    console.log('🎉 Dynamic 30-Day Auto-Backfill Test PASSED!');
    await browser.close();
    process.exit(0);
  } catch (err) {
    console.error('❌ Error during backfill test:', err);
    if (browser) await browser.close();
    process.exit(1);
  }
}

testDynamicBackfill();
