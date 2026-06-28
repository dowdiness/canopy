import { chromium } from 'playwright';
(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await page.goto('http://localhost:5173/json.html', { waitUntil: 'networkidle' });
  await page.waitForTimeout(2000);
  const widgetCount = await page.evaluate(() => document.querySelectorAll('.widget-btn').length);
  console.log('Widget buttons found:', widgetCount);
  const text = await page.evaluate(() => document.getElementById('json-input')?.textContent?.substring(0, 50) ?? 'NO_INPUT');
  console.log('Editor text:', text);
  const overlayExists = await page.evaluate(() => !!document.querySelector('.decoration-overlay'));
  console.log('Overlay exists:', overlayExists);
  // Also count container nodes to verify widget generation
  const containerCount = await page.evaluate(() => {
    const el = document.getElementById('json-input');
    const t = el?.textContent ?? '';
    return (t.match(/[\[{]/g) || []).length;
  });
  console.log('Opening brackets in text:', containerCount);
  await browser.close();
})();
