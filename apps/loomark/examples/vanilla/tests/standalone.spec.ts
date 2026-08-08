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
 * | local baseline | first visit with an empty repository | one complete archive establishes the active document identity |
 * | local durability | accepted edit then reload | the complete archive reopens with stable document identity and durable source |
 * | recovery | corrupt, unsupported, or unreadable record | storage remains unchanged and no editable document mounts |
 * | replacement failure | accepted edit after provider failure | applied source remains visible and reload restores the prior durable archive |
 */

test("first standalone visit stores a complete baseline archive", async ({ page }) => {
  await page.goto("/")

  await expect(page.locator("#loomark-root")).toBeVisible()
  await expect.poll(() => page.evaluate(() => localStorage.getItem("loomark.active-document-archive"))).not.toBeNull()
  const baseline = await page.evaluate(() => JSON.parse(
    localStorage.getItem("loomark.active-document-archive") ?? "{}",
  ) as { document_id?: string; portable_markdown?: string; history?: string })
  expect(baseline.document_id).toBeTruthy()
  expect(baseline.portable_markdown).toBe("")
  expect(baseline.history).toBeTruthy()
})

test("standalone edit replaces the archive and reload restores the durable source", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => page.evaluate(() => (
    JSON.parse(localStorage.getItem("loomark.active-document-archive") ?? "{}").document_id as string | undefined
  ))).toBeTruthy()
  const documentId = await page.evaluate(() => (
    JSON.parse(localStorage.getItem("loomark.active-document-archive") ?? "{}").document_id as string
  ))
  await page.locator("#loomark-input").fill("# Durable\n\nSaved locally\n")
  await expect.poll(() => page.evaluate(() => {
    const raw = localStorage.getItem("loomark.active-document-archive")
    return raw === null ? null : (JSON.parse(raw) as { portable_markdown?: string }).portable_markdown
  })).toBe("# Durable\n\nSaved locally\n")

  await page.reload()
  await expect(page.locator("#loomark-input")).toHaveValue("# Durable\n\nSaved locally\n")
  await expect.poll(() => page.evaluate(() => (
    JSON.parse(localStorage.getItem("loomark.active-document-archive") ?? "{}").document_id as string
  ))).toBe(documentId)
})

test("corrupt local archives mount a recovery view without an editor", async ({ page }) => {
  const corruptArchive = "not-json"
  await page.addInitScript(corruptArchive => {
    localStorage.setItem("loomark.active-document-archive", corruptArchive)
  }, corruptArchive)
  await page.goto("/")

  await expect(page.locator("#loomark-recovery-root")).toBeVisible()
  await expect(page.locator("#loomark-recovery-root")).toHaveAttribute(
    "data-loomark-recovery-category",
    "corrupt-archive",
  )
  await expect(page.locator("#loomark-input")).toHaveCount(0)
  await expect.poll(() => page.evaluate(() => (
    localStorage.getItem("loomark.active-document-archive")
  ))).toBe(corruptArchive)
})

test("unsupported local archives remain preserved behind recovery", async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem("loomark.active-document-archive", JSON.stringify({
      schema_version: "2",
      document_id: "doc",
      portable_markdown: "",
      history: "",
      extensions: {},
    }))
  })
  await page.goto("/")

  await expect(page.locator("#loomark-recovery-root")).toHaveAttribute(
    "data-loomark-recovery-category",
    "unsupported-archive",
  )
  await expect.poll(() => page.evaluate(() => localStorage.getItem("loomark.active-document-archive"))).toContain('"schema_version":"2"')
  await expect(page.locator("#loomark-input")).toHaveCount(0)
})

test("storage read failures mount a separate recovery view", async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(window, "localStorage", {
      configurable: true,
      get() {
        throw Object.assign(new Error("blocked"), { name: "UnknownError" })
      },
    })
  })
  await page.goto("/")

  await expect(page.locator("#loomark-recovery-root")).toHaveAttribute(
    "data-loomark-recovery-category",
    "storage-read-failed",
  )
  await expect(page.locator("#loomark-input")).toHaveCount(0)
})

test("a failed replacement keeps the applied source but reload restores the previous archive", async ({ page }) => {
  await page.goto("/")
  await page.locator("#loomark-input").fill("# Previous\n")
  await expect.poll(() => page.evaluate(() => (
    JSON.parse(localStorage.getItem("loomark.active-document-archive") ?? "{}").portable_markdown as string
  ))).toBe("# Previous\n")

  await page.evaluate(() => {
    const original = Storage.prototype.setItem
    Storage.prototype.setItem = function(key, value) {
      if (key === "loomark.active-document-archive") {
        throw Object.assign(new Error("full"), { name: "QuotaExceededError" })
      }
      original.call(this, key, value)
    }
  })
  await page.locator("#loomark-input").fill("# Applied\n")
  await expect(page.locator("#loomark-input")).toHaveValue("# Applied\n")
  await expect(page.locator("#loomark-error")).toContainText(
    "Changes are applied but not saved locally.",
  )

  await page.reload()
  await expect(page.locator("#loomark-input")).toHaveValue("# Previous\n")
})

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

test("mobile page frame drops desktop rails in a stacked split", async ({ page }) => {
  await page.goto("/")

  const raw = page.locator("#loomark-input")
  await expect(raw).toHaveCSS("border-left-width", "1px")
  await expect(raw).toHaveCSS("padding-left", "16px")

  await page.setViewportSize({ width: 640, height: 844 })
  await raw.fill("# Narrow\n")
  await page.locator("#loomark-split-toggle").click()

  const split = page.locator("#loomark-split")
  await expect(split).toHaveAttribute("data-orientation", "vertical")
  await expect(split.locator('[data-slot="resizable-handle"]')).toHaveAttribute(
    "aria-orientation",
    "horizontal",
  )

  const preview = page.locator("#loomark-preview")
  await expect(preview).toHaveAttribute("data-loomark-source", "# Narrow\n")
  for (const frame of [raw, preview]) {
    await expect(frame).toHaveCSS("border-left-width", "0px")
    await expect(frame).toHaveCSS("border-right-width", "0px")
    await expect(frame).toHaveCSS("padding-left", "12px")
    await expect(frame).toHaveCSS("padding-right", "12px")
    await expect(frame).toHaveCSS("width", "640px")
  }

  await page.locator("#loomark-mode-block").click()
  await expect(page.locator("#loomark-block")).toHaveCSS("padding-left", "12px")
  const blockFrame = page.locator("#loomark-block-frame")
  await expect(blockFrame).toHaveCSS("border-left-width", "0px")
  await expect(blockFrame).toHaveCSS("border-right-width", "0px")
  await expect(blockFrame).toHaveCSS("width", "640px")
  await expect(page.getByRole("toolbar", { name: "Block formatting" })).toHaveCSS(
    "padding-left",
    "12px",
  )
  await expect(page.locator("#loomark-root")).toHaveCount(1)
})
