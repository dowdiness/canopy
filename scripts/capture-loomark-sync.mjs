// Capture the real built editor, without injecting styles or recreating its UI.
// Run after building Loomark and serving apps/loomark/dist:
// node scripts/capture-loomark-sync.mjs http://localhost:8080
// PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH optionally selects an installed Chromium.
import { chromium } from "../apps/loomark/examples/vanilla/node_modules/playwright/index.mjs"
import { mkdir } from "node:fs/promises"
import { fileURLToPath } from "node:url"

const output = fileURLToPath(new URL("../apps/loomark/public/about/screens/", import.meta.url))
await mkdir(output, { recursive: true })
const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
})
try {
  for (const colorScheme of ["light", "dark"]) {
    for (const [device, width, height] of [["computer", 960, 600], ["phone", 390, 700]]) {
      const context = await browser.newContext({
        viewport: { width, height },
        deviceScaleFactor: 2,
        isMobile: device === "phone",
        hasTouch: device === "phone",
        colorScheme,
        reducedMotion: "reduce",
      })
      try {
        const page = await context.newPage()
        await page.goto(process.argv[2] ?? "http://localhost:8080")
        const editor = page.getByRole("textbox", { name: "Text", exact: true })
        for (const [state, text] of [
          ["before", "# Sunday lunch\n\nLunch at one."],
          ["after", "# Sunday lunch\n\nLunch at one. Bring the flowers."],
        ]) {
          await editor.fill(text)
          await page.evaluate(() => document.fonts.ready)
          await page.getByText("Saved on this device", { exact: true }).waitFor()
          // Let the actual save indicator and caret finish settling.
          await page.waitForTimeout(800)
          if (await editor.inputValue() !== text) throw new Error("Editor content changed during capture")
          await page.screenshot({ path: `${output}${device}-${colorScheme}-${state}.png` })
        }
      } finally {
        await context.close()
      }
    }
  }
} finally {
  await browser.close()
}
