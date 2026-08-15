import { expect, test, type Locator } from "@playwright/test"

async function replaceRawValue(input: Locator, value: string): Promise<void> {
  await input.evaluate((element, nextValue) => {
    const textarea = element as HTMLTextAreaElement
    const currentLength = textarea.value.length
    textarea.setSelectionRange(0, currentLength, "forward")
    textarea.dispatchEvent(new InputEvent("beforeinput", {
      bubbles: true,
      cancelable: true,
      composed: true,
      data: nextValue,
      inputType: "insertText",
    }))
    textarea.value = nextValue
    textarea.setSelectionRange(nextValue.length, nextValue.length)
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: nextValue,
      inputType: "insertText",
    }))
  }, value)
  await input.page().waitForTimeout(100)
}

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

test("standalone page completes and terminates the Warren Worker capability smoke", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => page.evaluate(() => (
    document.documentElement.dataset.loomarkWarrenWorkerCapability
  ))).toBe("complete")
})

test("standalone projection Worker passes Gate 0C parity, restart, timeout, and bounds", async ({ page }) => {
  await page.goto("/?projection-worker-gate=1")
  await expect.poll(() => page.evaluate(() => (
    document.documentElement.dataset.loomarkProjectionWorkerGate
  )), { timeout: 30_000 }).toBe("complete")
  const report = await page.evaluate(() => JSON.parse(
    document.documentElement.dataset.loomarkProjectionWorkerReport ?? "{}",
  ) as {
    parity?: boolean
    malformed?: string
    timeout?: string
    startup_failure?: string
    termination?: string
    same_epoch_stale?: string
    restart_generation?: number
    stale_rejected?: boolean
    bounded?: boolean
    overflow_recovered?: boolean
    large_payload_recovered?: boolean
    latest_source?: string
    low_count_delays?: boolean
    high_water_count?: number
    high_water_encoded_bytes?: number
    high_water_source_effect_bytes?: number
    pending_count_after_catchup?: number
    retained_seed_count_after_catchup?: number
    pending_source_effect_bytes_after_catchup?: number
    retention_control_bytes?: number
    superseded_count?: number
    collectibility_evidence?: string
    max_long_task_ms?: number
    max_long_task_phase?: string
    in_process_max_slice_ms?: number
    worker_max_long_task_ms?: number
    worker_max_long_task_phase?: string
    promotion_recommended?: boolean
    promotion_rejection?: string
  })
  expect(report.parity).toBe(true)
  expect(report.malformed).toBe("decode-failed")
  expect(report.timeout).toBe("timeout")
  expect(report.startup_failure).toBe("unavailable")
  expect(report.termination).toBe("terminated")
  expect(report.same_epoch_stale).toBe("stale")
  expect(report.restart_generation).toBeGreaterThan(1)
  expect(report.stale_rejected).toBe(true)
  expect(report.bounded).toBe(true)
  expect(report.overflow_recovered).toBe(true)
  expect(report.large_payload_recovered).toBe(true)
  expect(report.low_count_delays).toBe(true)
  expect(report.latest_source).toBe("# Latest 69\n")
  expect(report.high_water_count).toBeLessThanOrEqual(64)
  expect(report.high_water_encoded_bytes).toBeLessThanOrEqual(1_048_576)
  expect(report.high_water_source_effect_bytes).toBeLessThanOrEqual(1_048_576)
  expect(report.pending_count_after_catchup).toBe(0)
  expect(report.retained_seed_count_after_catchup).toBe(0)
  expect(report.pending_source_effect_bytes_after_catchup).toBe(0)
  expect(report.collectibility_evidence).toBe("collectibility-unavailable")
  expect(report.retention_control_bytes).toBeGreaterThan(0)
  expect(report.superseded_count).toBeGreaterThan(0)
  expect(Number.isFinite(report.max_long_task_ms)).toBe(true)
  expect(Number.isFinite(report.in_process_max_slice_ms)).toBe(true)
  expect(Number.isFinite(report.worker_max_long_task_ms)).toBe(true)
  expect(report.max_long_task_ms).toBeGreaterThanOrEqual(
    report.worker_max_long_task_ms ?? Number.POSITIVE_INFINITY,
  )
  expect(report.promotion_recommended).toBe(false)
  expect(report.promotion_rejection).toBe("release-browser-placement-evidence-required")
})

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

test("standalone IME commits one non-BMP final value and ignores cancellation", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => page.evaluate(() => (
    JSON.parse(localStorage.getItem("loomark.active-document-archive") ?? "{}").portable_markdown as string | undefined
  ))).toBe("")
  const input = page.locator("#loomark-input")
  await input.focus()
  await input.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.setSelectionRange(0, 0)
  })
  const session = await page.context().newCDPSession(page)

  await session.send("Input.imeSetComposition", {
    text: "😀",
    selectionStart: 2,
    selectionEnd: 2,
  })
  await expect(input).toHaveValue("😀")
  expect(await page.evaluate(() => (
    JSON.parse(localStorage.getItem("loomark.active-document-archive") ?? "{}").portable_markdown as string
  ))).toBe("")

  await session.send("Input.insertText", { text: "👨‍👩‍👧‍👦" })

  await expect.poll(() => page.evaluate(() => (
    JSON.parse(localStorage.getItem("loomark.active-document-archive") ?? "{}").portable_markdown as string
  ))).toBe("👨‍👩‍👧‍👦")
  await expect(input).toHaveValue("👨‍👩‍👧‍👦")
  await expect(input).toBeFocused()
  await expect.poll(() => input.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    return [textarea.selectionStart, textarea.selectionEnd]
  })).toEqual([11, 11])

  await session.send("Input.imeSetComposition", {
    text: "取消",
    selectionStart: 2,
    selectionEnd: 2,
  })
  await session.send("Input.imeSetComposition", {
    text: "",
    selectionStart: 0,
    selectionEnd: 0,
  })

  expect(await page.evaluate(() => (
    JSON.parse(localStorage.getItem("loomark.active-document-archive") ?? "{}").portable_markdown as string
  ))).toBe("👨‍👩‍👧‍👦")
  await expect(input).toHaveValue("👨‍👩‍👧‍👦")
})

test("standalone edit replaces the archive and reload restores the durable source", async ({ page }) => {
  await page.goto("/")
  await expect.poll(() => page.evaluate(() => (
    JSON.parse(localStorage.getItem("loomark.active-document-archive") ?? "{}").document_id as string | undefined
  ))).toBeTruthy()
  const documentId = await page.evaluate(() => (
    JSON.parse(localStorage.getItem("loomark.active-document-archive") ?? "{}").document_id as string
  ))
  await replaceRawValue(page.locator("#loomark-input"), "# Durable\n\nSaved locally\n")
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
  await replaceRawValue(page.locator("#loomark-input"), "# Previous\n")
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
  await replaceRawValue(page.locator("#loomark-input"), "# Applied\n")
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
  await expect(root).toHaveAttribute(
    "data-loomark-projection-placement",
    "synchronous",
  )
  await root.evaluate(element => element.setAttribute("data-mount-probe", "original"))

  await replaceRawValue(page.locator("#loomark-input"), "# Before\n\nBody\n")
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

for (const placement of ["worker", "in-process", "synchronous"] as const) {
  test(`${placement} comparison placement preserves canonical Preview`, async ({ page }) => {
    await page.goto(`/?projection-placement=${placement}`)
    const root = page.locator("#loomark-root")
    await expect(root).toHaveAttribute("data-loomark-projection-placement", placement)
    await replaceRawValue(page.locator("#loomark-input"), "# Placement\n\nBody\n")
    await page.locator("#loomark-mode-preview").click()
    await expect(page.locator('#loomark-preview h1[data-slot="typography-h1"]')).toHaveText(
      "Placement",
    )
    await expect(page.locator("#loomark-preview p")).toHaveText("Body")
    await expect(page.locator("#loomark-preview")).toHaveAttribute(
      "data-loomark-source",
      "# Placement\n\nBody\n",
    )
  })
}

test("projection trace is absent by default and records only after explicit opt-in", async ({
  page,
}) => {
  await page.goto("/")
  await expect(page.locator("#loomark-projection-trace-dump")).toHaveCount(0)
  await expect(page.locator("html")).not.toHaveAttribute(
    "data-loomark-projection-trace",
    /.+/,
  )

  await page.goto("/?projection-benchmark=1")
  await replaceRawValue(page.locator("#loomark-input"), "# Trace\n\nBody\n")
  await page.locator("#loomark-mode-preview").click()
  await expect(page.locator("#loomark-preview p")).toHaveText("Body")
  await page.locator("#loomark-projection-trace-dump").dispatchEvent("click")
  const trace = await page.locator("html").getAttribute("data-loomark-projection-trace")
  expect(trace).not.toBeNull()
  const report = JSON.parse(trace ?? "{}") as {
    enabled?: boolean
    count?: number
    dropped_count?: number
    overflowed?: boolean
    contract_violated?: boolean
  }
  expect(report.enabled).toBe(true)
  expect(report.count).toBeGreaterThan(0)
  expect(report.dropped_count).toBe(0)
  expect(report.overflowed).toBe(false)
  expect(report.contract_violated).toBe(false)
})

test("ordinary consecutive Block input preserves both characters and the caret", async ({ page }) => {
  await page.goto("/")
  await replaceRawValue(page.locator("#loomark-input"), "x")
  await page.locator("#loomark-mode-block").click()

  const input = page.locator("#loomark-block-input")
  const block = page.locator("#loomark-block")
  await expect(input).toHaveValue("x")

  await input.selectText()
  await input.pressSequentially("a")
  await expect(block).toHaveAttribute("data-loomark-source", "a")
  await expect(input).toHaveValue("a")
  await expect
    .poll(() => input.evaluate(element => ({
      start: (element as HTMLTextAreaElement).selectionStart,
      end: (element as HTMLTextAreaElement).selectionEnd,
    })))
    .toEqual({ start: 1, end: 1 })

  await input.pressSequentially("b")
  await expect(block).toHaveAttribute("data-loomark-source", "ab")
  await expect(input).toHaveValue("ab")
  await expect
    .poll(() => input.evaluate(element => ({
      start: (element as HTMLTextAreaElement).selectionStart,
      end: (element as HTMLTextAreaElement).selectionEnd,
    })))
    .toEqual({ start: 2, end: 2 })
  await expect(page.locator("#loomark-error")).toHaveCount(0)
})

test("Block input preserves the latest value when two events arrive before redraw", async ({ page }) => {
  await page.goto("/")
  await replaceRawValue(page.locator("#loomark-input"), "x")
  await page.locator("#loomark-mode-block").click()
  const input = page.locator("#loomark-block-input")
  const block = page.locator("#loomark-block")
  await expect(input).toHaveValue("x")

  await input.evaluate(element => {
    const textarea = element as HTMLTextAreaElement
    textarea.value = "a"
    textarea.setSelectionRange(1, 1)
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: "a",
      inputType: "insertText",
    }))

    textarea.value = "ab"
    textarea.setSelectionRange(2, 2)
    textarea.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      composed: true,
      data: "b",
      inputType: "insertText",
    }))
  })

  await expect(block).toHaveAttribute("data-loomark-source", "ab")
  await expect(input).toHaveValue("ab")
  await expect
    .poll(() => input.evaluate(element => ({
      start: (element as HTMLTextAreaElement).selectionStart,
      end: (element as HTMLTextAreaElement).selectionEnd,
    })))
    .toEqual({ start: 2, end: 2 })
  await expect(page.locator("#loomark-error")).toHaveCount(0)
})

test("Preview wraps long unbreakable content inside the reading frame", async ({ page }) => {
  await page.goto("/")
  const longUrl = `https://example.com/${`a`.repeat(200)}`
  const source =
    `# Long content\n\nVisit ${longUrl} and read this paragraph.\n\nInline code: \`${`x`.repeat(150)}\`\n`
  await replaceRawValue(page.locator("#loomark-input"), source)
  await page.locator("#loomark-mode-preview").click()
  const preview = page.locator("#loomark-preview")
  await expect(preview).toHaveAttribute("data-loomark-source", source)
  // Long URLs and inline code wrap inside the reading frame instead of
  // stretching the Preview pane into a horizontal scroll.
  await expect
    .poll(async () => preview.evaluate(el => el.scrollWidth > el.clientWidth))
    .toBe(false)
  await expect
    .poll(() =>
      page.evaluate(
        () => document.documentElement.scrollWidth > window.innerWidth,
      ),
    )
    .toBe(false)
})

test("frames stay borderless and only the split divider separates panes", async ({ page }) => {
  await page.goto("/")

  const raw = page.locator("#loomark-input")
  // Raw keeps RUI's transparent control border; no side rail is drawn.
  await expect(raw).toHaveCSS("border-left-color", "rgba(0, 0, 0, 0)")
  await expect(raw).toHaveCSS("border-right-color", "rgba(0, 0, 0, 0)")
  await expect(raw).toHaveCSS("padding-left", "16px")

  await page.setViewportSize({ width: 640, height: 844 })
  await replaceRawValue(raw, "# Narrow\n")
  await page.locator("#loomark-split-toggle").click()

  const split = page.locator("#loomark-split")
  await expect(split).toHaveAttribute("data-orientation", "vertical")
  await expect(split.locator('[data-slot="resizable-handle"]')).toHaveAttribute(
    "aria-orientation",
    "horizontal",
  )
  // The resizable handle line is the only divider between the panes.
  await expect(
    split.locator('[data-slot="resizable-handle-line"]'),
  ).toBeVisible()

  const preview = page.locator("#loomark-preview")
  await expect(preview).toHaveAttribute("data-loomark-source", "# Narrow\n")
  // Raw keeps RUI's transparent control border (1px, no visible rail);
  // Preview carries no side border at all. Neither frame draws a rail.
  await expect(raw).toHaveCSS("border-left-color", "rgba(0, 0, 0, 0)")
  await expect(raw).toHaveCSS("border-right-color", "rgba(0, 0, 0, 0)")
  await expect(preview).toHaveCSS("border-left-width", "0px")
  await expect(preview).toHaveCSS("border-right-width", "0px")
  for (const frame of [raw, preview]) {
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
