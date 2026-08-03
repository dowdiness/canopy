import { expect, test, type Browser, type BrowserContext, type Page } from "@playwright/test"

/**
 * #1075 behavioral boundary matrix (each row gets a fresh BrowserContext,
 * page, and connected mount container; no case clears/reuses/remounts it):
 *
 * | syntax/operation | source shape | result |
 * | paragraph/ATX/Setext block edit | LF/CRLF/CR/EOF, multiline | payload excludes markers; canonical source + Preview converge |
 * | exact text / split / merge | supported top-level blocks | atomic commit + deterministic focus/selection |
 * | projection | full/incremental/fresh | payload, SourceMap ranges, and identity stay attached |
 * | unsupported containers | quote/thematic/list | reject atomically; neighbors/ranges/focus unchanged |
 * | tight list / fenced code | unordered, ordered `)`, tilde fence, mixed CRLF | typed payload controls preserve markers, delimiters, and line endings |
 * | semantic Preview | heading, paragraph, fenced code, list fallback | RUI-aligned read-only semantic DOM without invented list containers |
 * | production chrome | Raw/Block/Preview, desktop/narrow | one labelled region, tablist, selected panel, and keyboard navigation |
 * | example presets | Hello/Blog/List/Code from any mode | replace canonical source without changing the selected mode |
 * | Block formatting | focused paragraph/heading/list item | typed heading/list/delete requests update source and restore a valid target |
 * | interactive chrome | normal, focus, error | only application controls are visible; Preview owns focus; errors appear on demand |
 * | Raw <-> Block <-> Preview | new/same source | one canonical source, no marker leakage |
 * | ownership | fresh page/container | termination only; no cleanup claim |
 */

const moduleUrl = new URL(
  "../../../../_build/js/release/build/dowdiness/loomark/internal/dev_host/dev_host.js",
  import.meta.url,
).href
const pageUrl = new URL("../index.html", import.meta.url).href

type Host = {
  context: BrowserContext
  page: Page
  mountResult: string
}

async function mountPage(context: BrowserContext, source: string): Promise<Omit<Host, "context">> {
  const page = await context.newPage()
  await page.goto(pageUrl)
  const mountResult = await page.evaluate(
    ({ moduleUrl, source }) =>
      import(moduleUrl).then(module => module.mount_dev_host("app", source)),
    { moduleUrl, source },
  )
  await expect(page.locator("#loomark-root")).toBeVisible()
  await expect.poll(async () => (await snapshot(page)).control_ready).toBe(true)
  return { page, mountResult }
}

async function mountHost(browser: Browser, source: string): Promise<Host> {
  const context = await browser.newContext()
  return { context, ...await mountPage(context, source) }
}

async function snapshot(page: Page): Promise<Record<string, unknown>> {
  const raw = await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_snapshot()), moduleUrl)
  return JSON.parse(raw) as Record<string, unknown>
}

async function requestSource(page: Page, source: string): Promise<void> {
  await page.evaluate(
    ({ moduleUrl, source }) =>
      import(moduleUrl).then(module => module.dev_host_request_source(source)),
    { moduleUrl, source },
  )
}

async function rawInput(page: Page, source: string): Promise<void> {
  await page.evaluate(source => {
    const target = document.getElementById("loomark-driver-target")
    target?.dispatchEvent(new CustomEvent("loomark-driver", { detail: `raw-input|${source}` }))
  }, source)
}

async function selectPreview(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_select_preview()), moduleUrl)
}

async function expectPreviewSource(page: Page, source: string): Promise<void> {
  await expect(page.locator("#loomark-preview")).toHaveAttribute("data-loomark-source", source)
}

async function selectBlock(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_select_block()), moduleUrl)
}

async function selectRaw(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_select_raw()), moduleUrl)
}

async function restoreSnapshot(page: Page, version: number, source: string, mode: "raw" | "block" | "preview"): Promise<void> {
  await page.evaluate(
    ({ moduleUrl, version, source, mode }) =>
      import(moduleUrl).then(module => module.dev_host_restore_snapshot(version, source, mode)),
    { moduleUrl, version, source, mode },
  )
}

async function forceEditorFailure(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_force_editor_failure()), moduleUrl)
}

async function focusPreview(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_focus_preview()), moduleUrl)
}

async function focusRaw(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_focus_raw()), moduleUrl)
}

async function focusBlock(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_focus_block()), moduleUrl)
}

async function probeStaleBlockSelection(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_probe_stale_block_selection()), moduleUrl)
}

async function probeDeletedBlockSelection(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_probe_deleted_block_selection()), moduleUrl)
}

async function focusRawThenSelectPreview(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => {
      module.dev_host_focus_raw()
      module.dev_host_select_preview()
    }), moduleUrl)
}

async function captureFocus(page: Page): Promise<string> {
  return page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_capture_focus()), moduleUrl)
}

async function restoreFocus(page: Page, token: string): Promise<void> {
  await page.evaluate(
    ({ moduleUrl, token }) =>
      import(moduleUrl).then(module => module.dev_host_restore_focus(token)),
    { moduleUrl, token },
  )
}

async function writeSelection(page: Page, start: number, end: number): Promise<void> {
  await page.evaluate(
    ({ moduleUrl, start, end }) =>
      import(moduleUrl).then(module => module.dev_host_write_selection(start, end)),
    { moduleUrl, start, end },
  )
}

async function writeSelectionFailure(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_write_selection_failure()), moduleUrl)
}

async function measurePreview(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_measure_preview()), moduleUrl)
}

async function measureFailure(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_measure_failure()), moduleUrl)
}

async function stopListening(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_stop_listening()), moduleUrl)
}

async function failHost(page: Page, message: string): Promise<void> {
  await page.evaluate(
    ({ moduleUrl, message }) =>
      import(moduleUrl).then(module => module.dev_host_fail(message)),
    { moduleUrl, message },
  )
}

test("Raw input preserves canonical source and Preview follows a committed edit", async ({ browser }) => {
  const host = await mountHost(browser, "before\r\n")
  try {
    await host.page.evaluate(moduleUrl =>
      import(moduleUrl).then(module => module.dev_host_select_raw()), moduleUrl)
    await host.page.evaluate(
      ({ moduleUrl }) =>
        import(moduleUrl).then(module => module.dev_host_request_source("after\r\n")),
      { moduleUrl },
    )
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("after\r\n")
    await expect(host.page.locator("#loomark-input")).toHaveValue("after\n")
    await selectPreview(host.page)
    await expect(host.page.locator("#loomark-input")).toHaveCount(0)
    await expectPreviewSource(host.page, "after\r\n")
  } finally {
    await host.context.close()
  }
})

test("Preview renders supported blocks as RUI-aligned semantic HTML", async ({ browser }) => {
  const source = "# Semantic title\n\nReadable body.\n\n~~~moonbit\nlet answer = 42\n~~~\n\n- one\n- two\n"
  const host = await mountHost(browser, source)
  try {
    await expect(host.page.locator("#loomark-root")).toHaveAttribute("data-rui-theme", "")
    await expect(host.page.locator('#loomark-toolbar button[role="tab"]')).toHaveCount(3)
    await expect(host.page.locator("#loomark-mode-raw")).toHaveAttribute("aria-selected", "true")
    await selectPreview(host.page)
    await expect(host.page.locator("#loomark-mode-raw")).toHaveAttribute("aria-selected", "false")
    await expect(host.page.locator("#loomark-mode-preview")).toHaveAttribute("aria-selected", "true")
    const preview = host.page.locator("#loomark-preview")
    await expect(preview).toHaveAttribute("data-loomark-source", source)
    await expect(preview.locator("[data-loomark-preview-notice]")).toContainText(
      "supported top-level blocks",
    )
    await expect(preview.locator('h1[data-slot="typography-h1"]')).toHaveText("Semantic title")
    await expect(preview.locator('p[data-slot="typography-p"]')).toHaveText("Readable body.")
    await expect(preview.locator('pre code[data-loomark-code-info="moonbit"]')).toHaveText(
      "let answer = 42",
    )
    await expect(preview.locator("ul, ol")).toHaveCount(0)
    const rawListItems = preview.locator('[data-loomark-preview-raw-list-item="unordered"]')
    await expect(rawListItems).toHaveCount(2)
    await expect(rawListItems.nth(0)).toContainText("- one")
    await expect(rawListItems.nth(1)).toContainText("- two")
    await expect(preview.locator("textarea, input, button")).toHaveCount(0)
  } finally {
    await host.context.close()
  }
})

test("production chrome exposes one accessible editor view at a time", async ({ browser }) => {
  const host = await mountHost(browser, "# Accessible editor\n")
  try {
    const region = host.page.getByRole("region", { name: "Loomark Markdown Editor" })
    await expect(region).toBeVisible()
    const tabs = region.getByRole("tablist", { name: "Editor view" })
    await expect(tabs.getByRole("tab")).toHaveCount(3)
    await expect(tabs.locator("svg")).toHaveCount(3)
    const blockTab = tabs.getByRole("tab", { name: "Block view" })
    const rawTab = tabs.getByRole("tab", { name: "Raw Markdown" })
    const previewTab = tabs.getByRole("tab", { name: "Preview" })
    await expect(rawTab).toHaveAttribute("aria-selected", "true")
    await expect(rawTab).not.toHaveAttribute("aria-controls")
    await expect(blockTab).not.toHaveAttribute("aria-controls")
    await expect(previewTab).not.toHaveAttribute("aria-controls")
    await expect(region.getByRole("tabpanel", { name: "Raw Markdown" })).toBeVisible()

    await rawTab.focus()
    await rawTab.press("ArrowRight")
    await expect(previewTab).toBeFocused()
    await expect(previewTab).toHaveAttribute("aria-selected", "true")
    await expect(region.getByRole("tabpanel", { name: "Preview" })).toBeVisible()
    await expect.poll(async () => (await snapshot(host.page)).mode).toBe("preview")
    await expect(blockTab).toHaveAttribute("aria-selected", "false")
  } finally {
    await host.context.close()
  }
})

test("example presets replace canonical source without changing the selected mode", async ({ browser }) => {
  const host = await mountHost(browser, "initial\n")
  try {
    await selectPreview(host.page)
    const examples = host.page.getByRole("toolbar", { name: "Example documents" })
    const presets = [
      {
        name: "Apply Hello example",
        source: "# Hello World\n\nWelcome to the Canopy Markdown editor.\n\nThis editor has three modes: raw, block, and preview.\n",
      },
      {
        name: "Apply Blog example",
        source: "# Getting Started\n\nCanopy is an incremental projectional editor.\n\n## Features\n\nThe editor supports real-time collaboration via CRDT.\n\nEvery keystroke is incrementally parsed and projected into a structured view.",
      },
      {
        name: "Apply List example",
        source: "# Shopping List\n\nThings to pick up:\n\n- Apples\n- Bread\n- Coffee\n- Dark chocolate",
      },
      {
        name: "Apply Code example",
        source: "# README\n\nA minimal example project.\n\n## Install\n\n```bash\nnpm install\n```\n\n## Usage\n\n- Run the dev server\n- Open the browser\n- Start editing",
      },
    ]

    for (const preset of presets) {
      await examples.getByRole("button", { name: preset.name }).click()
      await expect.poll(async () => (await snapshot(host.page)).source).toBe(preset.source)
      await expect.poll(async () => (await snapshot(host.page)).mode).toBe("preview")
      await expectPreviewSource(host.page, preset.source)
    }
  } finally {
    await host.context.close()
  }
})

test("production chrome keeps its controls inside a narrow viewport", async ({ browser }) => {
  const host = await mountHost(browser, "# Narrow editor\n")
  try {
    await host.page.setViewportSize({ width: 360, height: 720 })
    const region = host.page.getByRole("region", { name: "Loomark Markdown Editor" })
    await expect(region.getByRole("toolbar", { name: "Example documents" })).toBeVisible()
    await expect(region.getByRole("tablist", { name: "Editor view" })).toBeVisible()
    expect(await host.page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360)
    const frame = await host.page.locator("#loomark-editor-frame").boundingBox()
    expect(frame).not.toBeNull()
    expect(frame!.x).toBeGreaterThanOrEqual(0)
    expect(frame!.x + frame!.width).toBeLessThanOrEqual(360)
  } finally {
    await host.context.close()
  }
})

test("interactive chrome hides driver controls and focuses the Preview surface", async ({ browser }) => {
  const host = await mountHost(browser, "# Focusable preview\n")
  try {
    await expect(host.page.getByRole("toolbar", { name: "Example documents" }).getByRole("button")).toHaveCount(4)
    await expect(host.page.getByRole("tablist", { name: "Editor view" }).getByRole("tab")).toHaveCount(3)
    await expect(host.page.locator("#loomark-event-target")).toBeHidden()
    await expect(host.page.locator("#loomark-focus-target")).toHaveCount(0)
    await expect(host.page.locator("#loomark-mode")).toHaveCount(0)
    await selectPreview(host.page)
    const preview = host.page.locator("#loomark-preview")
    await expect(preview).toHaveAttribute("tabindex", "0")
    await expect(preview).toHaveAttribute("aria-label", "Markdown preview")
    await host.page.locator("#loomark-mode-preview").focus()
    await focusPreview(host.page)
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe(
      "loomark-preview",
    )
  } finally {
    await host.context.close()
  }
})

test("application status stays quiet until an error needs attention", async ({ browser }) => {
  const host = await mountHost(browser, "stable\n")
  try {
    await expect(host.page.locator("#loomark-error")).toHaveCount(0)
    await failHost(host.page, "fatal test")
    const error = host.page.locator("#loomark-error")
    await expect(error).toHaveText("error: fatal test")
    await expect(error).toHaveAttribute("role", "alert")
    await expect(error).toHaveAttribute("data-slot", "alert")
  } finally {
    await host.context.close()
  }
})

test("Block toolbar toggles a focused paragraph and heading through typed edits", async ({ browser }) => {
  const host = await mountHost(browser, "Title\n\nBody\n")
  try {
    await selectBlock(host.page)
    const toolbar = host.page.getByRole("toolbar", { name: "Block formatting" })
    const heading2 = toolbar.getByRole("button", { name: "Heading 2, Ctrl+2" })
    await expect(heading2).toBeDisabled()

    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await expect(heading2).toBeEnabled()
    await expect(heading2).toHaveAttribute("aria-pressed", "false")
    await heading2.click()
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("## Title\n\nBody\n")
    await expect(heading2).toHaveAttribute("aria-pressed", "true")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe(
      "loomark-block-input",
    )

    await heading2.click()
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Title\n\nBody\n")
    await expect(heading2).toHaveAttribute("aria-pressed", "false")
  } finally {
    await host.context.close()
  }
})

test("Block toolbar toggles a focused paragraph and list item through typed edits", async ({ browser }) => {
  const host = await mountHost(browser, "Item\n\nTail\n")
  try {
    await selectBlock(host.page)
    const toolbar = host.page.getByRole("toolbar", { name: "Block formatting" })
    const toggleList = toolbar.getByRole("button", { name: "Toggle list, Ctrl+Shift+L" })
    await expect(toggleList).toBeDisabled()

    await host.page.locator("#loomark-block-input").focus()
    await expect(toggleList).toBeEnabled()
    await expect(toggleList).toHaveAttribute("aria-pressed", "false")
    await toggleList.click()
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("- Item\n\nTail\n")
    await expect(toggleList).toHaveAttribute("aria-pressed", "true")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe(
      "loomark-block-input",
    )

    await toggleList.click()
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Item\n\nTail\n")
    await expect(toggleList).toHaveAttribute("aria-pressed", "false")
  } finally {
    await host.context.close()
  }
})

test("Block toolbar deletes the active block and focuses the surviving typed target", async ({ browser }) => {
  const host = await mountHost(browser, "First\n\nSecond\n")
  try {
    await selectBlock(host.page)
    const toolbar = host.page.getByRole("toolbar", { name: "Block formatting" })
    const deleteBlock = toolbar.getByRole("button", { name: "Delete selected block" })
    await expect(deleteBlock).toBeDisabled()

    await host.page.locator("#loomark-block-input").focus()
    await expect(deleteBlock).toBeEnabled()
    await deleteBlock.click()
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("\nSecond\n")
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Second")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe(
      "loomark-block-input",
    )
  } finally {
    await host.context.close()
  }
})

test("Block toolbar enables only edits accepted for the active typed block", async ({ browser }) => {
  const host = await mountHost(browser, "```moonbit\nvalue\n```\n")
  try {
    await selectBlock(host.page)
    const toolbar = host.page.getByRole("toolbar", { name: "Block formatting" })
    const input = host.page.locator("#loomark-block-input")
    await input.focus()

    await expect(toolbar.getByRole("button", { name: "Heading 2, Ctrl+2" })).toBeDisabled()
    await expect(toolbar.getByRole("button", { name: "Toggle list, Ctrl+Shift+L" })).toBeDisabled()
    await expect(toolbar.getByRole("button", { name: "Delete selected block" })).toBeEnabled()
    await input.press("Control+2")
    await input.press("Control+Shift+L")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("```moonbit\nvalue\n```\n")
    await expect.poll(async () => (await snapshot(host.page)).error_count).toBe(0)
  } finally {
    await host.context.close()
  }
})

test("Block formatting shortcuts dispatch the same typed edits", async ({ browser }) => {
  const host = await mountHost(browser, "Title\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()

    await input.press("Control+2")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("## Title\n")
    await input.press("Control+2")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Title\n")
    await input.press("Control+Shift+L")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("- Title\n")

    await input.dispatchEvent("keydown", {
      key: "2",
      ctrlKey: true,
      isComposing: true,
    })
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("- Title\n")
  } finally {
    await host.context.close()
  }
})

test("Block mode edits a heading payload without leaking its marker", async ({ browser }) => {
  const host = await mountHost(browser, "# Title\n")
  try {
    await selectBlock(host.page)
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Title")
    await expect(host.page.locator("#loomark-block-input")).toHaveAttribute(
      "data-loomark-block-kind",
      "heading",
    )
    await host.page.locator("#loomark-block-input").fill("Retitled")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("# Retitled\n")
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "# Retitled\n")
  } finally {
    await host.context.close()
  }
})

test("Block mode edits a paragraph payload while preserving CRLF source", async ({ browser }) => {
  const host = await mountHost(browser, "Body\r\n")
  try {
    await selectBlock(host.page)
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Body")
    await expect(host.page.locator("#loomark-block-input")).toHaveAttribute(
      "data-loomark-block-kind",
      "paragraph",
    )
    await host.page.locator("#loomark-block-input").fill("Changed")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Changed\r\n")
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "Changed\r\n")
  } finally {
    await host.context.close()
  }
})

test("Block mode edits ordered/unordered lists and fenced code in one mixed document", async ({ browser }) => {
  const source = "- one\r\n\r\n7) two\r\n~~~moonbit\r\nold\r\n~~~\r\n"
  const host = await mountHost(browser, source)
  try {
    await selectBlock(host.page)
    await expect(host.page.locator('[data-loomark-block-kind="unordered-list-item"]')).toHaveCount(1)
    await expect(host.page.locator('[data-loomark-block-kind="ordered-list-item"]')).toHaveCount(1)
    await expect(host.page.locator('[data-loomark-block-kind="code"]')).toHaveCount(1)
    await expect(host.page.locator('[data-loomark-block-kind="unordered-list-item"]')).toHaveValue("one")
    await expect(host.page.locator('[data-loomark-block-kind="ordered-list-item"]')).toHaveValue("two")
    await expect(host.page.locator('[data-loomark-block-kind="code"]')).toHaveValue("old")

    await host.page.locator('[data-loomark-block-kind="unordered-list-item"]').fill("ONE")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(
      "- ONE\r\n\r\n7) two\r\n~~~moonbit\r\nold\r\n~~~\r\n",
    )
    await host.page.locator('[data-loomark-block-kind="ordered-list-item"]').fill("TWO")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(
      "- ONE\r\n\r\n7) TWO\r\n~~~moonbit\r\nold\r\n~~~\r\n",
    )
    await host.page.locator('[data-loomark-block-kind="code"]').fill("new")
    const committed = "- ONE\r\n\r\n7) TWO\r\n~~~moonbit\r\nnew\r\n~~~\r\n"
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(committed)

    await selectRaw(host.page)
    await expect(host.page.locator("#loomark-input")).toHaveValue(committed.replaceAll("\r\n", "\n"))
    await selectPreview(host.page)
    await expectPreviewSource(host.page, committed)
    await selectBlock(host.page)
    await expect(host.page.locator("#loomark-block")).toHaveAttribute("data-loomark-source", committed)
  } finally {
    await host.context.close()
  }
})

test("clearing the only Block keeps an empty control editable", async ({ browser }) => {
  const host = await mountHost(browser, "Hello\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.fill("")
    await expect(input).toHaveValue("")
    await expect(host.page.locator("[data-loomark-block-id]")).toHaveCount(1)
    await host.page.keyboard.type("Again")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Again\n")
  } finally {
    await host.context.close()
  }
})

test("Block mode edits a Setext heading payload without replacing its underline", async ({ browser }) => {
  const host = await mountHost(browser, "Title\n---\n")
  try {
    await selectBlock(host.page)
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Title")
    await expect(host.page.locator("#loomark-block-input")).toHaveAttribute(
      "data-loomark-block-kind",
      "heading",
    )
    await host.page.locator("#loomark-block-input").fill("Renamed")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Renamed\n---\n")
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "Renamed\n---\n")
  } finally {
    await host.context.close()
  }
})

test("Block mode preserves CR Setext equals markers and multiline payloads", async ({ browser }) => {
  const host = await mountHost(browser, "Foo\rbar\r=\r")
  try {
    await selectBlock(host.page)
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Foo\nbar")
    await expect(host.page.locator("#loomark-block-input")).toHaveAttribute(
      "data-loomark-block-kind",
      "heading",
    )
    await host.page.locator("#loomark-block-input").fill("Renamed")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Renamed\r=\r")
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "Renamed\r=\r")
  } finally {
    await host.context.close()
  }
})

test("Block mode preserves untouched CR separators during a partial multiline edit", async ({ browser }) => {
  const host = await mountHost(browser, "Foo\rbar")
  try {
    await selectBlock(host.page)
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Foo\nbar")
    await host.page.locator("#loomark-block-input").fill("Foo\nChanged")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Foo\rChanged")
  } finally {
    await host.context.close()
  }
})

test("Block mode preserves untouched CRLF separators during a partial multiline edit", async ({ browser }) => {
  const host = await mountHost(browser, "Foo\r\nbar\r\nbaz")
  try {
    await selectBlock(host.page)
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Foo\nbar\nbaz")
    await host.page.locator("#loomark-block-input").fill("Foo\nbar\nChanged")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Foo\r\nbar\r\nChanged")
  } finally {
    await host.context.close()
  }
})

test("Rapid Block typing preserves a mid-text UTF-16 caret across CRLF normalization", async ({ browser }) => {
  const host = await mountHost(browser, "A😀B\r\nC")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(3, 3)
    })
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.value = "A😀XB\nC"
      textarea.setSelectionRange(4, 4)
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        data: "X",
        inputType: "insertText",
      }))
      textarea.value = "A😀XYB\nC"
      textarea.setSelectionRange(5, 5)
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        data: "Y",
        inputType: "insertText",
      }))
    })
    // The first frame drains the LIFO AfterRender selection callbacks. A stale
    // callback used to enqueue a rejection render, so the second frame exposes
    // the focus loss instead of letting pre-render focus satisfy the assertion.
    await host.page.evaluate(() => new Promise<void>(resolve => {
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
    }))
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("A😀XYB\r\nC")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-block-input")
    await expect.poll(() => host.page.evaluate(() => {
      const textarea = document.activeElement as HTMLTextAreaElement | null
      return textarea === null ? "missing" : `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("5:5")
    expect(await snapshot(host.page)).toMatchObject({
      error_code: null,
      error_count: 0,
    })
  } finally {
    await host.context.close()
  }
})

test("a superseded Block caret restore yields to a same-frame deletion", async ({ browser }) => {
  const host = await mountHost(browser, "A")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.value = "AB"
      textarea.setSelectionRange(2, 2)
      textarea.dispatchEvent(new InputEvent("input", { bubbles: true, data: "B" }))
      textarea.value = "A"
      textarea.setSelectionRange(1, 1)
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        inputType: "deleteContentBackward",
      }))
    })
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("A")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe(
      "loomark-block-input",
    )
    await expect.poll(() => host.page.evaluate(() => {
      const textarea = document.activeElement as HTMLTextAreaElement | null
      return textarea === null ? "missing" : `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("1:1")
    await expect.poll(async () => (await snapshot(host.page)).error).toBeNull()
  } finally {
    await host.context.close()
  }
})

test("Block mode preserves an ATX marker at EOF", async ({ browser }) => {
  const host = await mountHost(browser, "# Title")
  try {
    await selectBlock(host.page)
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Title")
    await host.page.locator("#loomark-block-input").fill("Retitled")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("# Retitled")
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "# Retitled")
  } finally {
    await host.context.close()
  }
})

test("Block input editor failure preserves its committed payload atomically", async ({ browser }) => {
  const host = await mountHost(browser, "Stable\n")
  try {
    await selectBlock(host.page)
    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)
    await host.page.locator("#loomark-block-input").fill("Rejected")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-commit-failed")
    expect(await snapshot(host.page)).toMatchObject({
      source: "Stable\n",
      source_revision: 0,
      committed_change_count: 0,
      editor_failure_armed: false,
    })
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Stable")
  } finally {
    await host.context.close()
  }
})

test("Block split rejects a non-collapsed selection without changing source", async ({ browser }) => {
  const host = await mountHost(browser, "Hello\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(0, 2)
    })
    await host.page.locator("[data-loomark-block-split]").first().click()
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("block-selection-rejected")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Hello\n")
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Hello")
  } finally {
    await host.context.close()
  }
})

test("Block split at the start creates and focuses an empty previous block", async ({ browser }) => {
  const host = await mountHost(browser, "Hello\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(0, 0)
    })
    await host.page.locator("[data-loomark-block-split]").click()
    await expect(host.page.locator("[data-loomark-block-id]")).toHaveCount(2)
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("")
    await expect(host.page.locator("#loomark-block-input-1")).toHaveValue("Hello")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-block-input")
    await expect.poll(() => host.page.evaluate(() => {
      const textarea = document.activeElement as HTMLTextAreaElement | null
      return textarea === null ? "missing" : `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("0:0")
    await host.page.keyboard.type("Before")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Before\n\nHello\n")
  } finally {
    await host.context.close()
  }
})

test("Block split and merge use typed structural edits and deterministic selection", async ({ browser }) => {
  const host = await mountHost(browser, "Hello\n\nWorld\n")
  try {
    await selectBlock(host.page)
    const firstInput = host.page.locator("#loomark-block-input")
    await firstInput.focus()
    await firstInput.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(2, 2)
    })
    await host.page.locator("[data-loomark-block-split]").first().click()
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("He\n\nllo\n\nWorld\n")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-block-input-1")
    await expect.poll(() => host.page.evaluate(() => {
      const textarea = document.activeElement as HTMLTextAreaElement | null
      return textarea === null ? "missing" : `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("0:0")
    const splitFirstKey = await host.page.locator("#loomark-block-input").getAttribute("data-loomark-block-id")
    const secondKey = await host.page.locator("#loomark-block-input-1").getAttribute("data-loomark-block-id")
    expect(splitFirstKey).not.toBe(secondKey)
    await expect.poll(async () => (await snapshot(host.page)).selection).toBe(`block|${secondKey}|0`)
    await expect(host.page.locator('[data-loomark-block-kind="paragraph"]')).toHaveCount(3)

    await host.page.locator("[data-loomark-block-merge]").nth(1).click()
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Hello\n\nWorld\n")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-block-input")
    await expect.poll(() => host.page.evaluate(() => {
      const textarea = document.activeElement as HTMLTextAreaElement | null
      return textarea === null ? "missing" : `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("2:2")
    const mergedKey = await host.page.locator("#loomark-block-input").getAttribute("data-loomark-block-id")
    await expect.poll(async () => (await snapshot(host.page)).selection).toBe(`block|${mergedKey}|2`)
  } finally {
    await host.context.close()
  }
})

test("typing after an end split does not leak the empty-block placeholder", async ({ browser }) => {
  const host = await mountHost(browser, "Hello\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(textarea.value.length, textarea.value.length)
    })
    await host.page.locator("[data-loomark-block-split]").click()
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-block-input-1")
    await expect(host.page.locator("#loomark-block-input-1")).toHaveValue("")
    await host.page.keyboard.type("X")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Hello\n\nX\n")
    await selectRaw(host.page)
    await expect(host.page.locator("#loomark-input")).toHaveValue("Hello\n\nX\n")
  } finally {
    await host.context.close()
  }
})

test("Block structural focus rejects stale and deleted targets after render", async ({ browser }) => {
  const host = await mountHost(browser, "Hello\n")
  try {
    await selectBlock(host.page)
    await probeStaleBlockSelection(host.page)
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("replacement\n")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("block-selection-rejected")
    await expect.poll(async () => (await snapshot(host.page)).error).toBe("block selection is stale")

    await probeDeletedBlockSelection(host.page)
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("block-selection-rejected")
    await expect.poll(async () => (await snapshot(host.page)).error).toBe("block selection target is unavailable")
    await expect(host.page.locator("[data-loomark-block-id]")).toHaveCount(0)
  } finally {
    await host.context.close()
  }
})

test("Block focus targets the typed first block and rejects stale mode restores", async ({ browser }) => {
  const host = await mountHost(browser, "# Focus\n")
  try {
    await selectBlock(host.page)
    await focusBlock(host.page)
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-block-input")
    const token = await captureFocus(host.page)
    expect(token).toMatch(/^v1\|block\|0$/)
    await selectPreview(host.page)
    await restoreFocus(host.page, token)
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("focus-mode-inapplicable")
  } finally {
    await host.context.close()
  }
})

test("Block mode omits unsupported containers without shifting direct block neighbors", async ({ browser }) => {
  const host = await mountHost(browser, "- listed\n  - nested\n\n> quoted\n\n---\n\n# Direct\n")
  try {
    await selectBlock(host.page)
    await expect(host.page.locator("[data-loomark-block-kind]")).toHaveCount(1)
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Direct")
    await expect(host.page.locator("#loomark-block")).toHaveAttribute(
      "data-loomark-source",
      "- listed\n  - nested\n\n> quoted\n\n---\n\n# Direct\n",
    )
  } finally {
    await host.context.close()
  }
})

test("Raw textarea input uses the atomic editor transaction and mode toolbar", async ({ browser }) => {
  const host = await mountHost(browser, "before\n")
  try {
    await selectRaw(host.page)
    await expect(host.page.locator("#loomark-input")).toHaveCount(1)
    await expect(host.page.locator("#loomark-input")).toHaveAttribute("data-slot", "textarea")
    await expect(host.page.locator("#loomark-input")).toHaveAttribute(
      "aria-label",
      "Raw Markdown source",
    )
    await host.page.locator("#loomark-input").fill("edited\nsource")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("edited\nsource")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(1)
    await selectPreview(host.page)
    await expect(host.page.locator("#loomark-input")).toHaveCount(0)
    await expect(host.page.locator("#loomark-mode-preview")).toHaveAttribute(
      "aria-selected",
      "true",
    )
    await expectPreviewSource(host.page, "edited\nsource")
    await rawInput(host.page, "must-not-commit\n")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("mode-inapplicable")
    expect(await snapshot(host.page)).toMatchObject({
      source: "edited\nsource",
      committed_change_count: 1,
    })
  } finally {
    await host.context.close()
  }
})

test("Raw textarea editor failure preserves committed state and consumes the arm", async ({ browser }) => {
  const host = await mountHost(browser, "before\n")
  try {
    await selectRaw(host.page)
    await expect(host.page.locator("#loomark-input")).toHaveValue("before\n")
    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)
    const before = await snapshot(host.page)

    await host.page.locator("#loomark-input").evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.value = "failed edit\n"
      textarea.dispatchEvent(new Event("input", { bubbles: true }))
    })
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-commit-failed")
    expect(await snapshot(host.page)).toMatchObject({
      source: before.source,
      mode: before.mode,
      source_revision: before.source_revision,
      committed_change_count: before.committed_change_count,
      error_count: (before.error_count as number) + 1,
      error_operation: "editor-dispatch",
      editor_failure_armed: false,
    })
    await expect(host.page.locator("#loomark-input")).toHaveValue("before\n")
  } finally {
    await host.context.close()
  }
})

test("Raw textarea editor failure can be retried and reflected in Preview", async ({ browser }) => {
  const host = await mountHost(browser, "before\n")
  try {
    await selectRaw(host.page)
    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)
    await host.page.locator("#loomark-input").evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.value = "failed edit\n"
      textarea.dispatchEvent(new Event("input", { bubbles: true }))
    })
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-commit-failed")
    await expect(host.page.locator("#loomark-input")).toHaveValue("before\n")

    await host.page.locator("#loomark-input").fill("retried edit\n")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("retried edit\n")
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "retried edit\n")
  } finally {
    await host.context.close()
  }
})

test("Raw typed input preserves LF, CRLF, CR, EOF, and empty EOF sources", async ({ browser }) => {
  const host = await mountHost(browser, "seed\n")
  try {
    await selectRaw(host.page)
    for (const source of ["line\n", "line\r\n", "line\r", "line", ""]) {
      await rawInput(host.page, source)
      await expect.poll(async () => (await snapshot(host.page)).source).toBe(source)
    }
  } finally {
    await host.context.close()
  }
})

test("canonical source keeps LF, CRLF, CR, and EOF bytes and collapses same-source commits", async ({ browser }) => {
  const host = await mountHost(browser, "same\n")
  try {
    await requestSource(host.page, "same\n")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(0)
    await requestSource(host.page, "cr\r")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("cr\r")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(1)
    await requestSource(host.page, "eof")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("eof")
    await requestSource(host.page, "crlf\r\n")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("crlf\r\n")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(3)
  } finally {
    await host.context.close()
  }
})

test("valid snapshot restore commits source and mode atomically while unknown versions do nothing", async ({ browser }) => {
  const host = await mountHost(browser, "old\r\n")
  try {
    await restoreSnapshot(host.page, 1, "new\r\n", "preview")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("new\r\n")
    await expect.poll(async () => (await snapshot(host.page)).mode).toBe("preview")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(1)
    await expect(host.page.locator("#loomark-input")).toHaveCount(0)
    await expectPreviewSource(host.page, "new\r\n")
    const committed = await snapshot(host.page)

    await restoreSnapshot(host.page, 99, "must-not-commit\n", "raw")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("unsupported-snapshot-version")
    expect(await snapshot(host.page)).toMatchObject({
      source: committed.source,
      mode: committed.mode,
      committed_change_count: committed.committed_change_count,
      error_count: 1,
    })
  } finally {
    await host.context.close()
  }
})

test("editor failure preserves committed source and reports one categorized error", async ({ browser }) => {
  const host = await mountHost(browser, "stable\n")
  try {
    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)
    const before = await snapshot(host.page)
    await restoreSnapshot(host.page, 1, "proposed\r\n", "preview")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-commit-failed")
    expect(await snapshot(host.page)).toMatchObject({
      source: before.source,
      mode: before.mode,
      source_revision: before.source_revision,
      committed_change_count: before.committed_change_count,
      error_count: (before.error_count as number) + 1,
      editor_failure_armed: false,
    })
  } finally {
    await host.context.close()
  }
})

test("logical focus accepts compatible controls and rejects malformed, stale, and mode-inapplicable tokens", async ({ browser }) => {
  const host = await mountHost(browser, "focus\n")
  try {
    await focusRaw(host.page)
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-input")
    const token = await captureFocus(host.page)
    expect(token).toMatch(/^v1\|raw\|0$/)
    await dispatchDriverEvent(host.page, "unrelated")
    await expect.poll(async () => (await snapshot(host.page)).event_count).toBe(1)
    expect(await captureFocus(host.page)).toBe(token)

    await selectPreview(host.page)
    await host.page.locator("#loomark-mode-preview").focus()
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-mode-preview")
    await restoreFocus(host.page, token)
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("focus-mode-inapplicable")
    expect(await host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-mode-preview")
    await restoreFocus(host.page, "v1|raw|99")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("stale-focus")
    expect(await host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-mode-preview")
    await restoreFocus(host.page, "v2|raw|0")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("unsupported-focus-version")
    expect(await host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-mode-preview")
    await restoreFocus(host.page, "not-a-focus-token")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("malformed-focus")
    expect(await host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-mode-preview")
    await restoreFocus(host.page, "v1|ambiguous|0")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("ambiguous-focus")
    expect(await host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-mode-preview")
  } finally {
    await host.context.close()
  }
})

test("logical focus is revalidated after an intervening mode change before the frame", async ({ browser }) => {
  const host = await mountHost(browser, "focus-race\n")
  try {
    await host.page.locator("#loomark-mode-preview").focus()
    await focusRawThenSelectPreview(host.page)
    await expect.poll(async () => (await snapshot(host.page)).mode).toBe("preview")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-mode-preview")
  } finally {
    await host.context.close()
  }
})

async function dispatchDriverEvent(page: Page, detail: string): Promise<void> {
  await page.evaluate(detail => {
    const target = document.getElementById("loomark-event-target")
    target?.dispatchEvent(new CustomEvent("loomark-test", { detail }))
  }, detail)
}

test("mounts one fresh connected container and exposes a detached snapshot", async ({ browser }) => {
  const host = await mountHost(browser, "# Loomark\n")
  try {
    expect(host.mountResult).toBe('{"ok":true}')
    expect(await snapshot(host.page)).toMatchObject({ source: "# Loomark\n", mode: "raw" })
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "# Loomark\n")
    await expect(host.page.locator('#loomark-preview h1[data-slot="typography-h1"]')).toHaveText("Loomark")
    await expect.poll(() => host.page.evaluate(() => document.getElementById("app")?.isConnected)).toBe(true)
  } finally {
    await host.context.close()
  }
})

test("two mounted tabs own distinct replica identities", async ({ browser }) => {
  const context = await browser.newContext()
  try {
    const first = await mountPage(context, "first\n")
    const second = await mountPage(context, "second\n")
    const firstReplica = (await snapshot(first.page)).replica_id
    const secondReplica = (await snapshot(second.page)).replica_id
    expect(firstReplica).toEqual(expect.any(String))
    expect(secondReplica).toEqual(expect.any(String))
    expect(firstReplica).not.toBe(secondReplica)
  } finally {
    await context.close()
  }
})

test("rejects a second mount without clearing or reusing the first host", async ({ browser }) => {
  const host = await mountHost(browser, "first\n")
  try {
    const secondMount = await host.page.evaluate(
      ({ moduleUrl }) => import(moduleUrl).then(module => module.mount_dev_host("app", "second\n")),
      { moduleUrl },
    )
    expect(secondMount).toBe('{"ok":false,"error":"host-already-mounted"}')
    await expect(host.page.locator("#loomark-root")).toHaveCount(1)
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "first\n")
  } finally {
    await host.context.close()
  }
})

test("keeps source and mode state separate from after-render focus and DOM effects", async ({ browser }) => {
  const host = await mountHost(browser, "# Effects\n")
  try {
    await requestSource(host.page, "# Updated\n")
    await selectPreview(host.page)
    await expect(host.page.locator("#loomark-mode-preview")).toHaveAttribute(
      "aria-selected",
      "true",
    )
    await expectPreviewSource(host.page, "# Updated\n")

    await focusPreview(host.page)
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe(
      "loomark-preview",
    )

    await selectRaw(host.page)
    await expect(host.page.locator("#loomark-input")).toHaveCount(1)
    await writeSelection(host.page, 1, 3)
    await expect.poll(async () => (await snapshot(host.page)).selection).toBe("1:3")
    await writeSelectionFailure(host.page)
    await expect.poll(async () => String((await snapshot(host.page)).error)).toContain("DOM element not found")

    await selectPreview(host.page)
    await expect(host.page.locator("#loomark-input")).toHaveCount(0)
    await measurePreview(host.page)
    await expect.poll(async () => (await snapshot(host.page)).measurement).toEqual(expect.stringMatching(/^[0-9]/))
    await measureFailure(host.page)
    await expect.poll(async () => String((await snapshot(host.page)).error)).toContain("DOM element not found")
  } finally {
    await host.context.close()
  }
})

test("installs one custom listener, refreshes its tagger, and cleans up repeatedly", async ({ browser }) => {
  const host = await mountHost(browser, "events\n")
  try {
    await expect.poll(async () => (await snapshot(host.page)).event_install_count).toBe(1)
    await dispatchDriverEvent(host.page, "old")
    await expect.poll(async () => (await snapshot(host.page)).event_count).toBe(1)
    await expect.poll(async () => (await snapshot(host.page)).event_install_count).toBe(1)
    expect(await snapshot(host.page)).toMatchObject({
      event_detail: "old|events\n",
      event_install_count: 1,
      event_unload_count: 0,
      listening: true,
    })

    await requestSource(host.page, "events-updated\n")
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "events-updated\n")
    await dispatchDriverEvent(host.page, "new")
    await expect.poll(async () => (await snapshot(host.page)).event_count).toBe(2)
    expect(await snapshot(host.page)).toMatchObject({
      event_detail: "new|events-updated\n",
      event_install_count: 1,
      event_unload_count: 0,
      listening: true,
    })

    await stopListening(host.page)
    await expect.poll(async () => (await snapshot(host.page)).listening).toBe(false)
    await expect.poll(async () => (await snapshot(host.page)).event_unload_count).toBe(1)
    await stopListening(host.page)
    await dispatchDriverEvent(host.page, "after-cleanup")
    await expect.poll(async () => (await snapshot(host.page)).event_count).toBe(2)
    expect(await snapshot(host.page)).toMatchObject({
      listening: false,
      event_detail: "new|events-updated\n",
      event_install_count: 1,
      event_unload_count: 1,
    })
  } finally {
    await host.context.close()
  }
})

test("enters a fatal state and rejects later driver operations", async ({ browser }) => {
  const host = await mountHost(browser, "stable\n")
  try {
    await failHost(host.page, "fatal test")
    await expect.poll(async () => (await snapshot(host.page)).fatal).toBe(true)
    await requestSource(host.page, "must not commit\n")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("stable\n")
    await expect.poll(async () => (await snapshot(host.page)).rejection).toBe(
      "operation=source;reason=fatal-state",
    )
    expect(await snapshot(host.page)).toMatchObject({
      fatal: true,
      error: "fatal test",
      rejection: "operation=source;reason=fatal-state",
    })
  } finally {
    await host.context.close()
  }
})
