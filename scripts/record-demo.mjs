// Record a demo GIF of the Mini-ML editor with live eval annotations.
// Usage: node scripts/record-demo.mjs
// Requires: vite dev server running on localhost, playwright installed

import { chromium } from '../examples/web/node_modules/playwright/index.mjs';
import { mkdirSync, existsSync, unlinkSync, readdirSync } from 'fs';
import { join } from 'path';

const FRAMES_DIR = '/tmp/canopy-demo-frames';
const VIEWPORT = { width: 800, height: 1200 }; // tall, we crop

// Clean up frames dir
if (existsSync(FRAMES_DIR)) {
  for (const f of readdirSync(FRAMES_DIR)) unlinkSync(join(FRAMES_DIR, f));
} else {
  mkdirSync(FRAMES_DIR, { recursive: true });
}

let frameNum = 0;
let clipRegion = null;

async function capture(page, delay = 0) {
  if (delay) await page.waitForTimeout(delay);
  const opts = { path: join(FRAMES_DIR, `frame-${String(frameNum++).padStart(4, '0')}.png`) };
  if (clipRegion) opts.clip = clipRegion;
  await page.screenshot(opts);
}

async function main() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: VIEWPORT });
  const page = await context.newPage();

  // Find running dev server
  let port = 5179;
  for (const p of [5173, 5174, 5175, 5176, 5177, 5178, 5179, 5180]) {
    try {
      const resp = await page.goto(`http://localhost:${p}/`, { timeout: 2000 });
      if (resp && resp.ok()) { port = p; break; }
    } catch { continue; }
  }

  await page.goto(`http://localhost:${port}/`);
  await page.waitForTimeout(1500);

  // Prepare: relabel, hide graphviz/errors, style output
  await page.evaluate(() => {
    const h = [...document.querySelectorAll('h3')].find(h => h.textContent.includes('Structure'));
    if (h) h.textContent = 'Formatted Output';
    const errH3 = [...document.querySelectorAll('h3')].find(h => h.textContent.includes('Errors'));
    if (errH3) { errH3.style.display = 'none'; }
    document.getElementById('error-output')?.style.setProperty('display', 'none');
    // Hide graphviz panel
    document.querySelectorAll('.panel').forEach(p => {
      if (p.textContent.includes('AST Visualization')) p.style.display = 'none';
    });
    // Hide the "AST Structure" h2
    const structH2 = [...document.querySelectorAll('h2')].find(h => h.textContent.includes('Structure'));
    if (structH2) structH2.style.display = 'none';
    // Style output
    const output = document.getElementById('ast-output');
    if (output) { output.style.fontSize = '15px'; output.style.lineHeight = '1.6'; }
  });

  // Scroll so example buttons are at top
  await page.evaluate(() => {
    const btn = document.querySelector('.example-btn');
    if (btn) btn.scrollIntoView({ block: 'start' });
    window.scrollBy(0, -15);
  });
  await page.waitForTimeout(300);

  // Compute crop region: from example buttons to bottom of ast-output
  const bounds = await page.evaluate(() => {
    const btn = document.querySelector('.example-btn');
    const output = document.getElementById('ast-output');
    return {
      btnTop: btn ? btn.getBoundingClientRect().top : 0,
      outBottom: output ? output.getBoundingClientRect().bottom : 600,
    };
  });

  clipRegion = {
    x: 20,
    y: Math.max(0, bounds.btnTop - 15),
    width: VIEWPORT.width - 40,
    height: Math.min(bounds.outBottom - bounds.btnTop + 50, 500),
  };

  // Clear the editor
  const editor = page.locator('#editor');
  await editor.click();
  await page.keyboard.press('Control+a');
  await page.waitForTimeout(200);
  await page.keyboard.press('Backspace');
  await page.waitForTimeout(600);

  // Recalculate clip after clearing (output area changes)
  const b2 = await page.evaluate(() => {
    const btn = document.querySelector('.example-btn');
    const output = document.getElementById('ast-output');
    return {
      btnTop: btn ? btn.getBoundingClientRect().top : 0,
      outBottom: output ? output.getBoundingClientRect().bottom : 600,
    };
  });
  clipRegion = {
    x: 20,
    y: Math.max(0, b2.btnTop - 15),
    width: VIEWPORT.width - 40,
    height: Math.min(b2.outBottom - b2.btnTop + 50, 480),
  };

  // Hold on empty state
  await capture(page);
  await capture(page, 300);

  // Type first definition
  const line1 = 'let double = \\x. x + x';
  for (const char of line1) {
    await editor.pressSequentially(char, { delay: 0 });
    await capture(page, 60);
  }
  await capture(page, 500);
  await capture(page, 400);

  // Type second definition
  await page.keyboard.press('Enter');
  await capture(page, 200);
  const line2 = 'let result = double 5';
  for (const char of line2) {
    await editor.pressSequentially(char, { delay: 0 });
    await capture(page, 60);
  }
  await capture(page, 500);
  await capture(page, 400);

  // Type body expression
  await page.keyboard.press('Enter');
  await capture(page, 200);
  const line3 = 'result';
  for (const char of line3) {
    await editor.pressSequentially(char, { delay: 0 });
    await capture(page, 80);
  }
  await capture(page, 600);
  await capture(page, 600);
  await capture(page, 600);

  // Edit: change "5" to "7"
  await page.keyboard.press('ArrowUp');
  await capture(page, 100);
  await page.keyboard.press('End');
  await capture(page, 100);
  await page.keyboard.press('Backspace');
  await capture(page, 300);
  await editor.pressSequentially('7', { delay: 0 });
  await capture(page, 300);
  await capture(page, 600);
  await capture(page, 600);
  await capture(page, 600);
  await capture(page, 600);

  await browser.close();
  console.log(`Captured ${frameNum} frames to ${FRAMES_DIR}`);
}

main().catch(console.error);
