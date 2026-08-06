import { expect, test } from "@playwright/test"

/**
 * #1176 standalone production boundary matrix:
 *
 * | boundary | case | required observation |
 * | production boot | clean Warren static output | exactly one visible Loomark root mounts into the declared host |
 * | production isolation | first load and ordinary interaction | private driver DOM and JavaScript exports are absent |
 * | canonical editing | Raw, Block, Preview, and split Preview | every accepted edit converges on one canonical source |
 * | root ownership | mode, document, and viewport changes | state changes inside the existing root without a second mount |
 * | responsive shell | desktop and narrow viewport | editor chrome remains usable and split Preview stacks when required |
 * | release output | clean rebuild and ordinary static server | page, release JavaScript, and declared public assets load without dev inputs |
 * | page lifetime | reload or close | the page ends ownership without claiming unmount or host reuse |
 */

test("production output boots one instrumentation-free Loomark root", async ({ page }) => {
  const consoleErrors: string[] = []
  const pageErrors: string[] = []
  page.on("console", message => {
    if (message.type() === "error") consoleErrors.push(message.text())
  })
  page.on("pageerror", error => pageErrors.push(error.message))

  await page.goto("/")

  await expect(page.locator("#loomark-root")).toBeVisible()
  await expect(page.locator("#loomark-root")).toHaveCount(1)
  await expect(page.locator("#loomark-driver-target")).toHaveCount(0)
  await expect(page.locator("#loomark-event-target")).toHaveCount(0)
  await expect(page.locator("#loomark-root")).toHaveAttribute(
    "aria-label",
    "Loomark Markdown Editor",
  )

  await page.reload()
  await expect(page.locator("#loomark-root")).toBeVisible()
  await expect(page.locator("#loomark-root")).toHaveCount(1)
  await expect(page.locator("#loomark-driver-target")).toHaveCount(0)
  expect(consoleErrors).toEqual([])
  expect(pageErrors).toEqual([])
})

test("Raw, Block, and Preview editing stays inside the original production root", async ({ page }) => {
  await page.goto("/")
  const root = page.locator("#loomark-root")
  await expect(root).toBeVisible()
  await root.evaluate(element => element.setAttribute("data-mount-probe", "original"))

  await page.locator("#loomark-input").fill("# Before\n\nBody\n")
  await page.locator("#loomark-mode-block").click()
  await expect(page.locator("#loomark-block-input")).toHaveValue("Before")
  await page.locator("#loomark-block-input").fill("After")
  await expect(page.locator("#loomark-block")).toHaveAttribute(
    "data-loomark-source",
    "# After\n\nBody\n",
  )

  await page.locator("#loomark-mode-preview").click()
  await expect(page.locator('#loomark-preview h1[data-slot="typography-h1"]')).toHaveText(
    "After",
  )
  await expect(page.locator("#loomark-preview p")).toHaveText("Body")
  await expect(root).toHaveAttribute("data-mount-probe", "original")
  await expect(root).toHaveCount(1)
})

test("narrow standalone editing keeps one document in a stacked split", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/")
  await page.locator("#loomark-input").fill("# Narrow\n")
  await page.locator("#loomark-split-toggle").click()

  const split = page.locator("#loomark-split")
  await expect(split).toHaveAttribute("data-orientation", "vertical")
  await expect(split.locator('[data-slot="resizable-handle"]')).toHaveAttribute(
    "aria-orientation",
    "horizontal",
  )
  await expect(page.locator("#loomark-preview")).toHaveAttribute(
    "data-loomark-source",
    "# Narrow\n",
  )
  await expect(page.locator("#loomark-root")).toHaveCount(1)
})
