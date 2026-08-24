import { expect, test, type Browser, type BrowserContext, type Locator, type Page } from "@playwright/test"

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
 * | semantic Preview | blocks, inline forms, recovery, unsafe URLs | RUI-aligned read-only semantic DOM from the committed MarkdownIR |
 * | fixed split Preview | Raw/Block editor plus Preview, wide/narrow viewport | one editor and one semantic attachment stay live; accepted commits update both panes; the divider axis follows the available width |
 * | production chrome | Raw/Block/Preview, desktop/narrow | one labelled region, tablist, selected panel, and keyboard navigation |
 * | example presets | Hello/Blog/List/Code from any mode | replace canonical source without changing the selected mode |
 * | Block formatting | focused paragraph/heading/list item | typed heading/list/delete requests update source and restore a valid target |
 * | Block keyboard editing | collapsed text cursor at start/middle/end | Enter splits, native direction keys preserve text cursor movement, boundary arrows navigate, empty-start Backspace merges, and focus/text cursor follow the typed target |
 * | interactive chrome | normal, focus, error | only application controls are visible; Preview owns focus; errors appear on demand |
 * | Raw <-> Block <-> Preview | new/same source | one canonical source, no marker leakage |
 * | ownership | fresh page/container | termination only; no cleanup claim |
 * | storage ownership | private development host | canonical edits never read or replace the standalone archive slot |
 */

const moduleUrl = new URL(
  "../../../../../_build/js/release/build/dowdiness/loomark/internal/dev_host/dev_host.js",
  import.meta.url,
).href
const pageUrl = new URL(
  "../index.html?projection-placement=worker",
  import.meta.url,
).href

type Host = {
  context: BrowserContext
  page: Page
  mountResult: string
}

async function mountPage(
  context: BrowserContext,
  source: string,
  profileTextEdit = false,
): Promise<Omit<Host, "context">> {
  const page = await context.newPage()
  await page.goto(pageUrl)
  if (profileTextEdit) {
    await page.evaluate(() => {
      ;(globalThis as any).__canopy_bridge = { perfCurrent: null }
    })
  }
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

type RawNativeEdit = {
  value: string
  beforeStart: number
  beforeEnd: number
  beforeDirection?: "forward" | "backward" | "none"
  afterStart: number
  afterEnd: number
  afterDirection?: "forward" | "backward" | "none"
  inputType?: string
  data?: string | null
  isComposing?: boolean
}

async function dispatchRawNativeEdits(input: Locator, edits: RawNativeEdit[]): Promise<void> {
  await input.evaluate((element, edits) => {
    const textarea = element as HTMLTextAreaElement
    for (const edit of edits) {
      const init: InputEventInit = {
        bubbles: true,
        cancelable: true,
        inputType: edit.inputType ?? "insertText",
        data: edit.data ?? null,
        isComposing: edit.isComposing ?? false,
      }
      textarea.setSelectionRange(
        edit.beforeStart,
        edit.beforeEnd,
        edit.beforeDirection ?? "none",
      )
      if (!textarea.dispatchEvent(new InputEvent("beforeinput", init))) continue
      textarea.value = edit.value
      textarea.setSelectionRange(
        edit.afterStart,
        edit.afterEnd,
        edit.afterDirection ?? "none",
      )
      textarea.dispatchEvent(new InputEvent("input", init))
    }
  }, edits)
}

function markdownPerfBlocks(count: number): string {
  return Array.from(
    { length: count },
    (_, index) => `## Heading ${index}\n\nParagraph ${index} with **bold** and [link](https://example.com/${index}).`,
  ).join("\n\n")
}

async function armRawRenderBarrier(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_arm_raw_render_barrier()), moduleUrl)
  await expect.poll(async () => (await snapshot(page)).raw_render_barrier_armed).toBe(true)
}

async function waitForRawRenderBarrier(page: Page): Promise<void> {
  await expect.poll(async () => (await snapshot(page)).raw_render_barrier_waiting).toBe(true)
}

async function releaseRawRenderBarrier(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_release_raw_render_barrier()), moduleUrl)
  await expect.poll(async () => (await snapshot(page)).raw_render_barrier_armed).toBe(false)
}

async function replaceRawValue(input: Locator, value: string): Promise<void> {
  const currentLength = await input.evaluate(element =>
    (element as HTMLTextAreaElement).value.length)
  await dispatchRawNativeEdits(input, [{
    value,
    beforeStart: 0,
    beforeEnd: currentLength,
    beforeDirection: "forward",
    afterStart: value.length,
    afterEnd: value.length,
    data: value,
  }])
}

async function rawSelectionProbe(page: Page, detail: "capture" | "install"): Promise<void> {
  await page.evaluate(detail => {
    const target = document.getElementById("loomark-driver-target")
    target?.dispatchEvent(new CustomEvent("loomark-driver", {
      detail: `${detail}-raw-selection`,
    }))
  }, detail)
}

async function commitCapturedRawSelection(page: Page, inserted: string): Promise<void> {
  await page.evaluate(inserted => {
    const target = document.getElementById("loomark-driver-target")
    target?.dispatchEvent(new CustomEvent("loomark-driver", {
      detail: `raw-selection-edit|${inserted}`,
    }))
  }, inserted)
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

async function toggleSplitPreview(page: Page): Promise<void> {
  await page.locator("#loomark-split-toggle").click()
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

async function forceParserFailure(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_force_parser_failure()), moduleUrl)
}

async function forceReconstructionFailure(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_force_reconstruction_failure()), moduleUrl)
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

test("private development host remains independent of archive storage", async ({ browser }) => {
  const context = await browser.newContext()
  await context.addInitScript(() => {
    const state = window as typeof window & { __loomarkIndexedDbAccesses: number }
    state.__loomarkIndexedDbAccesses = 0
    Object.defineProperty(window, "indexedDB", {
      configurable: true,
      get() {
        state.__loomarkIndexedDbAccesses += 1
        return undefined
      },
    })
  })

  const host = await mountPage(context, "before\n")
  try {
    await requestSource(host.page, "after\n")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("after\n")
    await expect.poll(() => host.page.evaluate(() => (
      window as typeof window & { __loomarkIndexedDbAccesses: number }
    ).__loomarkIndexedDbAccesses)).toBe(0)
  } finally {
    await context.close()
  }
})

test("post-acceptance parser Failure reopens once and resumes Raw editing", async ({ browser }) => {
  const host = await mountHost(browser, "# Before\n")
  try {
    await toggleSplitPreview(host.page)
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "# Before\n")

    await forceParserFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).parser_failure_armed).toBe(true)
    await requestSource(host.page, "# Accepted\n")

    await expect.poll(async () => (await snapshot(host.page)).source).toBe("# Accepted\n")
    await expect.poll(async () => (await snapshot(host.page)).runtime_state).toBe("healthy")
    await expect.poll(async () => (await snapshot(host.page)).mode).toBe("raw")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-recovered")
    await expect.poll(async () => (await snapshot(host.page)).parser_failure_armed).toBe(false)
    await expect.poll(async () => (await snapshot(host.page)).reconstruction_attempt_count).toBe(1)
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(1)
    await expect(host.page.locator("#loomark-input")).toHaveValue("# Accepted\n")
    await expect(host.page.locator("#loomark-preview")).toHaveCount(0)
    await expect(host.page.locator("#loomark-block")).toHaveCount(0)

    await replaceRawValue(host.page.locator("#loomark-input"), "# Continued\n")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("# Continued\n")
  } finally {
    await host.context.close()
  }
})

test("failed reconstruction exposes exact Markdown in terminal Raw Recovery", async ({ browser }) => {
  const host = await mountHost(browser, "# Before\n")
  try {
    await forceReconstructionFailure(host.page)
    await forceParserFailure(host.page)
    await requestSource(host.page, "# Accepted\n")

    await expect.poll(async () => (await snapshot(host.page)).runtime_state).toBe("raw-recovery")
    await expect.poll(async () => (await snapshot(host.page)).fatal).toBe(true)
    await expect.poll(async () => (await snapshot(host.page)).reconstruction_attempt_count).toBe(1)
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("# Accepted\n")
    await expect(host.page.locator("#loomark-recovery-source")).toHaveValue("# Accepted\n")
    await expect(host.page.locator("#loomark-recovery-copy")).toBeVisible()
    await expect(host.page.locator("#loomark-recovery-download")).toBeVisible()
    await expect(host.page.locator("#loomark-recovery-reload")).toBeVisible()
    await host.page.locator("#loomark-recovery-copy").click()
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe(
      "editor-recovery-failed",
    )
    const [download] = await Promise.all([
      host.page.waitForEvent("download"),
      host.page.locator("#loomark-recovery-download").click(),
    ])
    expect(download.suggestedFilename()).toBe("loomark-recovered.md")
    await expect(host.page.locator("#loomark-preview")).toHaveCount(0)
    await expect(host.page.locator("#loomark-block")).toHaveCount(0)

    await requestSource(host.page, "# Must not land\n")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("# Accepted\n")
  } finally {
    await host.context.close()
  }
})

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
    await selectPreview(host.page)
    await expect(host.page.locator("#loomark-preview")).toHaveCount(1)
    await expectPreviewSource(host.page, "after\r\n")
  } finally {
    await host.context.close()
  }
})

test("Raw input stays on the browser-owned fast path", async ({ browser }) => {
  const host = await mountHost(browser, "before")
  try {
    const input = host.page.locator("#loomark-input")
    const elapsed = await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      const started = performance.now()
      const init: InputEventInit = {
        bubbles: true,
        cancelable: true,
        inputType: "insertText",
        data: "after",
      }
      textarea.setSelectionRange(0, textarea.value.length, "forward")
      textarea.dispatchEvent(new InputEvent("beforeinput", init))
      textarea.value = "after"
      textarea.setSelectionRange(5, 5)
      textarea.dispatchEvent(new InputEvent("input", init))
      return performance.now() - started
    })
    expect(elapsed).toBeLessThan(10)
    await expect(input).toHaveValue("after")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("after")
    expect((await snapshot(host.page)).raw_input_phase).toBeNull()
  } finally {
    await host.context.close()
  }
})

test("Raw input stays below 10ms on a large source", async ({ browser }) => {
  const context = await browser.newContext()
  const source = markdownPerfBlocks(125)
  const position = source.length - 1
  const mounted = await mountPage(context, source)
  try {
    const input = mounted.page.locator("#loomark-input")
    const expected = `${source.slice(0, position)}x${source.slice(position)}`
    const elapsed = await input.evaluate((element, value) => {
      const textarea = element as HTMLTextAreaElement
      const started = performance.now()
      const init: InputEventInit = {
        bubbles: true,
        cancelable: true,
        inputType: "insertText",
        data: "x",
      }
      textarea.setSelectionRange(value.position, value.position)
      textarea.dispatchEvent(new InputEvent("beforeinput", init))
      textarea.value = value.expected
      textarea.setSelectionRange(value.position + 1, value.position + 1)
      textarea.dispatchEvent(new InputEvent("input", init))
      return performance.now() - started
    }, { position, expected })
    expect(elapsed).toBeLessThan(10)
    await expect(input).toHaveValue(expected)
    await expect.poll(async () => (await snapshot(mounted.page)).source).toBe(expected)
  } finally {
    await context.close()
  }
})

test("real Raw keyboard input keeps task p95 and maximum below 10ms", async ({ browser }) => {
  const context = await browser.newContext()
  const source = markdownPerfBlocks(125)
  const mounted = await mountPage(context, source)
  try {
    const input = mounted.page.locator("#loomark-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      const measurements = {
        task: [] as number[],
        frame: [] as number[],
      }
      ;(window as Window & { __loomarkRawKeyboardTiming?: typeof measurements })
        .__loomarkRawKeyboardTiming = measurements
      textarea.addEventListener("input", () => {
        const started = performance.now()
        queueMicrotask(() => measurements.task.push(performance.now() - started))
        requestAnimationFrame(() => measurements.frame.push(performance.now() - started))
      }, { capture: true })
      textarea.setSelectionRange(textarea.value.length, textarea.value.length)
    })
    const typed = "abcdefghijklmnopqrst"
    for (const character of typed) {
      await mounted.page.keyboard.type(character)
      await mounted.page.evaluate(() => new Promise<void>(resolve => {
        requestAnimationFrame(() => resolve())
      }))
    }
    const timing = await mounted.page.evaluate(() => {
      const values = (window as Window & {
        __loomarkRawKeyboardTiming?: { task: number[]; frame: number[] }
      }).__loomarkRawKeyboardTiming
      if (values == null) throw new Error("Raw keyboard timing was not installed")
      const percentile95 = (samples: number[]) => {
        const ordered = [...samples].sort((a, b) => a - b)
        return ordered[Math.ceil(ordered.length * 0.95) - 1] ?? Number.POSITIVE_INFINITY
      }
      return {
        samples: values.task.length,
        taskP95: percentile95(values.task),
        taskMax: Math.max(...values.task),
        frameP95: percentile95(values.frame),
      }
    })
    expect(timing.samples).toBe(typed.length)
    expect(timing.taskP95).toBeLessThanOrEqual(10)
    expect(timing.taskMax).toBeLessThanOrEqual(10)
    // Frame presentation is intentionally reported separately from task time.
    expect(timing.frameP95).toBeLessThan(50)
    await expect(input).toHaveValue(`${source}${typed}`)
  } finally {
    await context.close()
  }
})

test("Raw split Preview reflects browser source independently of a rejected canonical flush", async ({ browser }) => {
  const host = await mountHost(browser, "# Before\n")
  try {
    await toggleSplitPreview(host.page)
    await expectPreviewSource(host.page, "# Before\n")
    await forceEditorFailure(host.page)
    await replaceRawValue(host.page.locator("#loomark-input"), "# Fast\n")
    await expect(host.page.locator('#loomark-preview h1[data-slot="typography-h1"]').first()).toHaveText("Fast")
    await expectPreviewSource(host.page, "# Fast\n")
    await expect.poll(async () => (await snapshot(host.page)).error_code)
      .toBe("editor-commit-failed")
  } finally {
    await host.context.close()
  }
})

test("Preview split keeps ownership of its editable Raw browser draft", async ({ browser }) => {
  const host = await mountHost(browser, "# Before\n")
  try {
    await toggleSplitPreview(host.page)
    await selectPreview(host.page)
    const input = host.page.locator("#loomark-input")
    const committedBefore = Number((await snapshot(host.page)).committed_change_count)
    await replaceRawValue(input, "# Draft\n")

    await host.page.waitForTimeout(20)
    await expect(input).toHaveValue("# Draft\n")
    await expect(host.page.locator('#loomark-preview h1[data-slot="typography-h1"]').first())
      .toHaveText("Draft")
    await expectPreviewSource(host.page, "# Draft\n")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count)
      .toBe(committedBefore + 1)
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("# Draft\n")
  } finally {
    await host.context.close()
  }
})

test("Preview split flushes its Raw draft before Block navigation and ignores stale ticks", async ({ browser }) => {
  const host = await mountHost(browser, "# Before\n")
  try {
    await toggleSplitPreview(host.page)
    await selectPreview(host.page)
    const input = host.page.locator("#loomark-input")
    const before = await snapshot(host.page)
    const committedBefore = Number(before.committed_change_count)
    const errorsBefore = Number(before.error_count)
    await replaceRawValue(input, "# Boundary\n")
    await selectBlock(host.page)

    expect(await snapshot(host.page)).toMatchObject({
      source: "# Boundary\n",
      mode: "block",
      committed_change_count: committedBefore + 1,
    })
    await host.page.waitForTimeout(350)
    expect(await snapshot(host.page)).toMatchObject({
      source: "# Boundary\n",
      mode: "block",
      committed_change_count: committedBefore + 1,
      error_code: null,
      error_operation: null,
      error_count: errorsBefore,
    })
  } finally {
    await host.context.close()
  }
})

test("Raw canonical flush does not wait for a large speculative Preview", async ({ browser }) => {
  const host = await mountHost(browser, "# Before\n")
  try {
    await toggleSplitPreview(host.page)
    await expectPreviewSource(host.page, "# Before\n")
    const source = `# Fast\n${markdownPerfBlocks(125)}`
    const committedBefore = Number((await snapshot(host.page)).committed_change_count)
    await replaceRawValue(host.page.locator("#loomark-input"), source)
    await expect.poll(
      async () => (await snapshot(host.page)).committed_change_count,
      { timeout: 3000 },
    ).toBe(committedBefore + 1)
    await expect(host.page.locator('#loomark-preview h1[data-slot="typography-h1"]').first()).toHaveText("Fast")
    await expectPreviewSource(host.page, source)
  } finally {
    await host.context.close()
  }
})

test("Raw split Preview never pairs a stale artifact with a newer browser source", async ({ browser }) => {
  const host = await mountHost(browser, "# Before\n")
  try {
    await toggleSplitPreview(host.page)
    await expectPreviewSource(host.page, "# Before\n")
    const source = `# After\n${markdownPerfBlocks(125)}`
    await replaceRawValue(host.page.locator("#loomark-input"), source)
    await expect(host.page.locator('#loomark-preview h1[data-slot="typography-h1"]')).not.toHaveText("Before")
    await expect(host.page.locator('#loomark-preview h1[data-slot="typography-h1"]').first()).toHaveText("After")
    await expectPreviewSource(host.page, source)
  } finally {
    await host.context.close()
  }
})

test("Raw and Preview observe one accepted document in a fixed resizable split", async ({ browser }) => {
  const host = await mountHost(browser, "# Before\n")
  try {
    await expect(host.page.locator("#loomark-input")).toHaveCount(1)
    await expect(host.page.locator("#loomark-preview")).toHaveCount(0)

    await toggleSplitPreview(host.page)
    await expect(host.page.locator("#loomark-split-toggle")).toHaveAttribute(
      "aria-pressed",
      "true",
    )
    await expect(host.page.locator("#loomark-split")).toHaveAttribute(
      "data-slot",
      "resizable-panel-group",
    )
    await expect(host.page.locator("#loomark-input")).toHaveCount(1)
    await expectPreviewSource(host.page, "# Before\n")
    await expect.poll(async () => (await snapshot(host.page)).semantic_read_count).toBe(1)

    await selectPreview(host.page)
    // #1181: the split stays visible on the Preview tab (raw editor + preview).
    await expect(host.page.locator("#loomark-split")).toHaveCount(1)
    await expect.poll(async () => (await snapshot(host.page)).semantic_read_count).toBe(1)
    await selectRaw(host.page)
    await expect(host.page.locator("#loomark-split")).toHaveCount(1)
    await expect.poll(async () => (await snapshot(host.page)).semantic_read_count).toBe(1)

    const committedBefore = Number((await snapshot(host.page)).committed_change_count)
    await replaceRawValue(host.page.locator("#loomark-input"), "# After\n")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("# After\n")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count)
      .toBe(committedBefore + 1)
    await expectPreviewSource(host.page, "# After\n")
    const readsAfterCommit = Number((await snapshot(host.page)).semantic_read_count)

    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)
    await replaceRawValue(host.page.locator("#loomark-input"), "# Rejected\n")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-commit-failed")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("# After\n")
    await expectPreviewSource(host.page, "# After\n")
    expect(Number((await snapshot(host.page)).semantic_read_count)).toBeGreaterThanOrEqual(readsAfterCommit)

    await toggleSplitPreview(host.page)
    await expect(host.page.locator("#loomark-preview")).toHaveCount(0)
    await expect(host.page.locator("#loomark-input")).toHaveCount(1)
    expect(Number((await snapshot(host.page)).semantic_read_count)).toBeGreaterThanOrEqual(readsAfterCommit)
  } finally {
    await host.context.close()
  }
})

test("Raw keeps focus and accepts consecutive keystrokes while split Preview updates", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    await toggleSplitPreview(host.page)
    // The split toggle re-renders the editor subtree, replacing the Raw
    // textarea with a fresh node. Wait for the split frame to settle before
    // focusing: focusing a still-scheduled predecessor would lose focus when
    // the patch detaches it, and the app never re-focuses the Raw control.
    await expect(host.page.locator("#loomark-split")).toBeVisible()
    const input = host.page.locator("#loomark-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(textarea.value.length, textarea.value.length)
    })

    let expectedSource = "start"
    for (const character of ["a", "b", "c"]) {
      expectedSource += character
      await expect(input).toBeFocused()
      // Target the current textarea node so an already-scheduled split render
      // cannot send the key to a detached predecessor between focus and input.
      await input.pressSequentially(character)
      // A canonical source commit plus focus on the re-resolved control is the
      // explicit acknowledgement that the transaction rendered successfully.
      await expect.poll(async () => (await snapshot(host.page)).source).toBe(
        expectedSource,
      )
      await expect(input).toBeFocused()
    }

    await expect(input).toHaveValue("startabc")
    await expectPreviewSource(host.page, "startabc")

    await host.page.setViewportSize({ width: 390, height: 844 })
    await expect(host.page.locator("#loomark-split")).toHaveAttribute(
      "data-orientation",
      "vertical",
    )
    await expect(input).toBeFocused()
    await input.pressSequentially("d")
    await expect(input).toHaveValue("startabcd")
  } finally {
    await host.context.close()
  }
})

test("RUI split divider resizes by keyboard and pointer", async ({ browser }) => {
  const host = await mountHost(browser, "# Resize\n")
  try {
    await toggleSplitPreview(host.page)
    const split = host.page.locator("#loomark-split")
    const handle = split.locator('[data-slot="resizable-handle"]')
    const control = host.page.locator("#loomark-split-handle")
    await expect(handle).toHaveAttribute("aria-valuenow", "50")

    await control.focus()
    await control.press("ArrowRight")

    await expect(handle).toHaveAttribute("aria-valuenow", "51")
    await expect(host.page.locator('[data-panel="editor"]')).toHaveAttribute(
      "data-size",
      "51",
    )

    const hitArea = host.page.locator('[data-slot="resizable-handle-hit-area"]')
    const bounds = await hitArea.boundingBox()
    expect(bounds).not.toBeNull()
    expect(bounds!.width).toBeGreaterThanOrEqual(12)
    await host.page.mouse.move(bounds!.x + 1, bounds!.y + bounds!.height / 2)
    await host.page.mouse.down()
    await host.page.mouse.move(bounds!.x + 41, bounds!.y + bounds!.height / 2)
    await host.page.mouse.up()

    await expect.poll(async () => Number(await handle.getAttribute("aria-valuenow")))
      .toBeGreaterThan(51)
  } finally {
    await host.context.close()
  }
})

test("Block and Preview converge through the shared canonical document", async ({ browser }) => {
  const host = await mountHost(browser, "# Before\n")
  try {
    await selectBlock(host.page)
    await toggleSplitPreview(host.page)
    await expectPreviewSource(host.page, "# Before\n")

    await host.page.locator("#loomark-block-input").fill("After")

    await expect.poll(async () => (await snapshot(host.page)).source).toBe("# After\n")
    await expectPreviewSource(host.page, "# After\n")
    await expect(
      host.page.locator('#loomark-preview h1[data-slot="typography-h1"]'),
    ).toHaveText("After")
  } finally {
    await host.context.close()
  }
})

test("split view stacks its resizable panes in a narrow viewport", async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } })
  const host = { context, ...await mountPage(context, "# Narrow\n") }
  try {
    await toggleSplitPreview(host.page)

    const split = host.page.locator("#loomark-split")
    const handle = split.locator('[data-slot="resizable-handle"]')
    await expect(split).toHaveAttribute("data-orientation", "vertical")
    await expect(handle).toHaveAttribute("aria-orientation", "horizontal")

    const editor = host.page.locator('[data-panel="editor"]')
    const preview = host.page.locator('[data-panel="preview"]')
    await expect(editor).toBeVisible()
    await expect(preview).toBeVisible()
    const positions = await Promise.all([editor, preview].map(async pane => {
      const bounds = await pane.boundingBox()
      expect(bounds).not.toBeNull()
      return bounds!
    }))
    expect(positions[1].y).toBeGreaterThanOrEqual(positions[0].y + positions[0].height - 1)
    expect(Math.abs(positions[0].height - positions[1].height)).toBeLessThanOrEqual(1)

    const control = host.page.locator("#loomark-split-handle")
    await control.focus()
    await control.press("ArrowDown")
    await expect(handle).toHaveAttribute("aria-valuenow", "51")
    await expect.poll(() => host.page.evaluate(() => ({
      viewport: window.innerWidth,
      content: document.documentElement.scrollWidth,
    }))).toEqual({ viewport: 390, content: 390 })
  } finally {
    await host.context.close()
  }
})

test("Preview renders committed MarkdownIR as semantic HTML with source-aware forms", async ({ browser }) => {
  const source = "# Semantic title\n\nReadable body with a [reference][docs].  \nnext line\n\n~~~moonbit\nlet answer = 42\n~~~\n\n- one\n- two\n\n3. three\n4. four\n\n> quoted\n\n---\n\n[docs]: https://example.test/docs \"Documentation\"\n"
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
    await expect(preview.locator('h1[data-slot="typography-h1"]')).toHaveText("Semantic title")
    await expect(preview.locator('p[data-slot="typography-p"]').first()).toContainText(
      "Readable body with a reference.",
    )
    await expect(preview.locator('pre code[data-loomark-code-info="moonbit"]')).toHaveText(
      "let answer = 42",
    )
    await expect(preview.locator('ul[data-loomark-list-marker="-"] > li')).toHaveText(["one", "two"])
    await expect(preview.locator('ol[data-loomark-list-marker="3."]')).toHaveAttribute("start", "3")
    await expect(preview.locator('ol[data-loomark-list-marker="3."] > li')).toHaveText(["three", "four"])
    await expect(preview.locator("blockquote")).toHaveText("quoted")
    await expect(preview.locator("hr")).toHaveCount(1)
    await expect(preview.locator('a[data-loomark-link-reference-form="full-reference"]')).toHaveAttribute(
      "href",
      "https://example.test/docs",
    )
    await expect(preview.locator('a[data-loomark-link-reference-form="full-reference"]')).toHaveAttribute(
      "title",
      "Documentation",
    )
    await expect(preview.locator('[data-loomark-hard-break-form="trailing-spaces"]')).toHaveCount(1)
    await expect(preview.locator("textarea, input, button")).toHaveCount(0)
  } finally {
    await host.context.close()
  }
})

test("Preview refreshes semantic DOM and source metadata after a committed source shift", async ({ browser }) => {
  const initial = "[Docs][docs]\n\n[docs]: https://old.example.test \"Old title\"\n"
  const shifted = "# Prepended\n\n[Docs][docs]\n\n[docs]: https://new.example.test/path \"New title\"\n"
  const host = await mountHost(browser, initial)
  try {
    await selectPreview(host.page)
    const preview = host.page.locator("#loomark-preview")
    const link = preview.locator('a[data-loomark-link-reference-form="full-reference"]')
    await expect(link).toHaveAttribute("href", "https://old.example.test")
    await requestSource(host.page, shifted)
    await expectPreviewSource(host.page, shifted)
    await expect(preview.locator('h1[data-slot="typography-h1"]')).toHaveText("Prepended")
    await expect(link).toHaveAttribute("href", "https://new.example.test/path")
    await expect(link).toHaveAttribute("title", "New title")
  } finally {
    await host.context.close()
  }
})

test("Preview replaces stale semantic DOM with recovered diagnostics and restores it on exact reversal", async ({ browser }) => {
  const source = "# Good\n\n- one\n- two\n"
  const host = await mountHost(browser, source)
  try {
    await selectPreview(host.page)
    const preview = host.page.locator("#loomark-preview")
    await expect(preview.locator("ul > li")).toHaveText(["one", "two"])
    await requestSource(host.page, "[unclosed\n")
    await expectPreviewSource(host.page, "[unclosed\n")
    await expect(preview.locator('[data-loomark-preview-fallback="recovered"]')).toContainText(
      "Recovered Markdown:",
    )
    await expect(preview.locator("[data-loomark-preview-diagnostic]")).toContainText("Diagnostic:")
    await expect(preview.locator('h1[data-slot="typography-h1"], ul[data-loomark-list-marker] > li')).toHaveCount(0)
    await requestSource(host.page, source)
    await expectPreviewSource(host.page, source)
    await expect(preview.locator('h1[data-slot="typography-h1"]')).toHaveText("Good")
    await expect(preview.locator("ul > li")).toHaveText(["one", "two"])
    await expect(preview.locator('[data-loomark-preview-fallback="recovered"]')).toHaveCount(0)
  } finally {
    await host.context.close()
  }
})

test("Preview escapes HTML and rejects dangerous link, image, and autolink destinations", async ({ browser }) => {
  const source = "<script>window.loomarkScriptExecuted = true</script>\n\ninline <i>markup</i>\n\n[link](javascript:alert(1)) ![image](javascript:alert(1)) <javascript:alert(1)>\n"
  const host = await mountHost(browser, source)
  try {
    await selectPreview(host.page)
    const preview = host.page.locator("#loomark-preview")
    await expect(preview.locator("script")).toHaveCount(0)
    await expect(preview).toContainText("<script>window.loomarkScriptExecuted = true</script>")
    await expect(preview.locator('[data-loomark-preview-html="block"]')).toHaveText(
      "<script>window.loomarkScriptExecuted = true</script>",
    )
    await expect(preview.locator('[data-loomark-preview-html="inline"]')).toHaveText(["<i>", "</i>"])
    expect(await host.page.evaluate(() => (
      window as Window & { loomarkScriptExecuted?: boolean }
    ).loomarkScriptExecuted)).toBeUndefined()
    await expect(preview.locator('[data-loomark-preview-url-rejected="link"]')).toHaveText("link")
    await expect(preview.locator('[data-loomark-preview-url-rejected="image"]')).toContainText("image")
    await expect(preview.locator('[data-loomark-preview-url-rejected="autolink"]')).toHaveText(
      "javascript:alert(1)",
    )
    await expect(preview.locator('a[href^="javascript:"], img[src^="javascript:"]')).toHaveCount(0)
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
        name: "Guide: Apply Blog example",
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

test("Block view presents typed blocks as compact RUI editing rows", async ({ browser }) => {
  const source = "# Title\n\nBody\n\n3) Third\n\n```moonbit\nlet x = 1\n```\n"
  const host = await mountHost(browser, source)
  try {
    await selectBlock(host.page)
    const block = host.page.locator("#loomark-block")
    await expect(block.locator('[data-slot="block-editor-input"]')).toHaveCount(4)
    await expect(block.getByRole("textbox", { name: "Heading 1 block 1" })).toHaveValue("Title")
    await expect(block.getByRole("textbox", { name: "Paragraph block 2" })).toHaveValue("Body")
    await expect(block.locator('[data-loomark-block-marker="ordered"]')).toHaveText("3)")
    await expect(block.getByRole("textbox", { name: "Ordered list item 3" })).toHaveValue("Third")
    await expect(block.getByRole("textbox", { name: "moonbit code block 4" })).toHaveValue(
      "let x = 1",
    )
    await expect(block.getByRole("button", { name: "Split" })).toHaveCount(0)
    await expect(block.getByRole("button", { name: "Merge" })).toHaveCount(0)
  } finally {
    await host.context.close()
  }
})

test("interactive chrome hides driver controls and focuses the Preview view", async ({ browser }) => {
  const host = await mountHost(browser, "# Focusable preview\n")
  try {
    await expect(host.page.getByRole("toolbar", { name: "Example documents" }).getByRole("button")).toHaveCount(5)
    await expect(host.page.getByRole("tablist", { name: "Editor view" }).getByRole("tab")).toHaveCount(3)
    await expect(host.page.locator("#loomark-event-target")).toBeHidden()
    await expect(host.page.locator("#loomark-focus-target")).toHaveCount(0)
    await expect(host.page.locator("#loomark-mode")).toHaveCount(0)
    await selectPreview(host.page)
    const preview = host.page.locator("#loomark-preview")
    await expect(preview).toHaveAttribute("tabindex", "0")
    await expect(preview).toHaveAttribute("aria-label", "Markdown preview")
    await expect(host.page.getByRole("region", { name: "Markdown preview" })).toBeVisible()
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
    const heading2 = toolbar.getByRole("button", { name: "H2: Heading 2, Ctrl+2" })
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

test("Block delete focuses the adjacent survivor instead of a stale editor cursor", async ({ browser }) => {
  const host = await mountHost(browser, "First\n\nSecond\n\nThird\n")
  try {
    await selectBlock(host.page)
    const first = host.page.locator("#loomark-block-input")
    await first.fill("Changed")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(
      "Changed\n\nSecond\n\nThird\n",
    )
    const third = host.page.locator("#loomark-block-input-2")
    await third.focus()
    await expect(
      host.page.locator('[data-loomark-block-row]').filter({ has: third }),
    ).toHaveAttribute("data-loomark-block-active", "true")

    await host.page.getByRole("button", { name: "Delete selected block" }).click()

    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Changed\n\nSecond\n\n")
    const second = host.page.locator("#loomark-block-input-1")
    await expect(second).toBeFocused()
    await expect.poll(() => second.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("6:6")
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

    await expect(toolbar.getByRole("button", { name: "H2: Heading 2, Ctrl+2" })).toBeDisabled()
    await expect(toolbar.getByRole("button", { name: "Toggle list, Ctrl+Shift+L" })).toBeDisabled()
    await expect(toolbar.getByRole("button", { name: "Delete selected block" })).toBeEnabled()
    await input.dispatchEvent("keydown", { key: "2", ctrlKey: true })
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

    await input.dispatchEvent("keydown", { key: "2", ctrlKey: true })
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("## Title\n")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(1)
    await expect(input).toHaveAttribute("aria-label", "Heading 2 block 1")
    await expect(input).toBeFocused()
    await input.dispatchEvent("keydown", { key: "2", ctrlKey: true })
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(2)
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Title\n")
    await expect(input).toHaveAttribute("aria-label", "Paragraph block 1")
    await expect(input).toBeFocused()
    await input.dispatchEvent("keydown", { key: "4", ctrlKey: true })
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("#### Title\n")
    await expect(input).toHaveAttribute("aria-label", "Heading 4 block 1")
    await expect(input).toBeFocused()
    await input.dispatchEvent("keydown", { key: "5", ctrlKey: true })
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("##### Title\n")
    await expect(input).toHaveAttribute("aria-label", "Heading 5 block 1")
    await expect(input).toBeFocused()
    await input.dispatchEvent("keydown", { key: "6", ctrlKey: true })
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("###### Title\n")
    await expect(input).toHaveAttribute("aria-label", "Heading 6 block 1")
    await expect(input).toBeFocused()
    await input.dispatchEvent("keydown", { key: "0", ctrlKey: true })
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Title\n")
    await expect(input).toHaveAttribute("aria-label", "Paragraph block 1")
    await expect(input).toBeFocused()
    await input.dispatchEvent("keydown", { key: "0", ctrlKey: true })
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Title\n")
    await expect.poll(async () => (await snapshot(host.page)).error_count).toBe(0)
    await expect(input).toBeFocused()
    await input.dispatchEvent("keydown", { key: "L", ctrlKey: true, shiftKey: true })
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

test("failed Block formatting shortcut restores its originating selection", async ({ browser }) => {
  const host = await mountHost(browser, "Title\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(2, 2)
    })
    await forceEditorFailure(host.page)
    await input.dispatchEvent("keydown", { key: "2", ctrlKey: true })

    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-commit-failed")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Title\n")
    await expect(input).toBeFocused()
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("2:2")
  } finally {
    await host.context.close()
  }
})

test("failed Block toolbar edit returns focus to its invoked control", async ({ browser }) => {
  const host = await mountHost(browser, "Title\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    const heading2 = host.page.getByRole("button", { name: "H2: Heading 2, Ctrl+2" })
    await forceEditorFailure(host.page)
    await heading2.click()

    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-commit-failed")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Title\n")
    await expect(heading2).toBeFocused()
  } finally {
    await host.context.close()
  }
})

test("same-frame formatting callbacks reduce against the latest model", async ({ browser }) => {
  const host = await mountHost(browser, "Title\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      element.dispatchEvent(new KeyboardEvent("keydown", { key: "2", ctrlKey: true, bubbles: true }))
      element.dispatchEvent(new KeyboardEvent("keydown", { key: "2", ctrlKey: true, bubbles: true }))
    })

    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(2)
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Title\n")
    await expect.poll(async () => (await snapshot(host.page)).error_count).toBe(0)
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
    await expect(host.page.locator("#loomark-block")).toHaveAttribute(
      "data-loomark-source",
      "- ONE\r\n\r\n7) two\r\n~~~moonbit\r\nold\r\n~~~\r\n",
    )
    await host.page.locator('[data-loomark-block-kind="ordered-list-item"]').fill("TWO")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(
      "- ONE\r\n\r\n7) TWO\r\n~~~moonbit\r\nold\r\n~~~\r\n",
    )
    await expect(host.page.locator("#loomark-block")).toHaveAttribute(
      "data-loomark-source",
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
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("\n")
    await input.fill("Again")
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
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      Object.assign(element, { __loomarkIdentity: "preserved" })
    })
    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)
    await input.fill("Rejected")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-commit-failed")
    expect(await snapshot(host.page)).toMatchObject({
      source: "Stable\n",
      source_revision: 0,
      committed_change_count: 0,
      editor_failure_armed: false,
    })
    await expect(input).toHaveValue("Stable")
    await expect(input).toBeFocused()
    await expect.poll(() => input.evaluate(
      element => (element as HTMLTextAreaElement & { __loomarkIdentity?: string }).__loomarkIdentity,
    )).toBe("preserved")
  } finally {
    await host.context.close()
  }
})

test("rejected Block insertion restores a UTF-16 text cursor to its accepted position", async ({ browser }) => {
  const host = await mountHost(browser, "A😀B\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(3, 3)
      Object.assign(textarea, { __loomarkIdentity: "preserved" })
    })
    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(3, 3)
    })
    await host.page.keyboard.type("X")

    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-commit-failed")
    await expect(input).toHaveValue("A😀B")
    await expect(input).toBeFocused()
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("3:3")
    await expect.poll(() => input.evaluate(
      element => (element as HTMLTextAreaElement & { __loomarkIdentity?: string }).__loomarkIdentity,
    )).toBe("preserved")
  } finally {
    await host.context.close()
  }
})

test("rejected coalesced Block input is not retried", async ({ browser }) => {
  const host = await mountHost(browser, "start\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      for (const value of ["startX", "startXY"]) {
        textarea.value = value
        textarea.setSelectionRange(value.length, value.length)
        textarea.dispatchEvent(new Event("input", { bubbles: true }))
      }
    })
    await host.page.evaluate(() => new Promise<void>(resolve => {
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
    }))

    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe(
      "editor-commit-failed",
    )
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("start\n")
    await expect(input).toHaveValue("start")
    await expect(input).toBeFocused()
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("5:5")
  } finally {
    await host.context.close()
  }
})

test("Enter splits the active text block at the caret and focuses the new block", async ({ browser }) => {
  const host = await mountHost(browser, "Hello\n\nWorld\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(2, 2)
    })

    await input.press("Enter")

    await expect.poll(async () => (await snapshot(host.page)).source).toBe("He\n\nllo\n\nWorld\n")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe(
      "loomark-block-input-1",
    )
    await expect.poll(() => host.page.evaluate(() => {
      const textarea = document.activeElement as HTMLTextAreaElement | null
      return textarea === null ? "missing" : `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("0:0")
  } finally {
    await host.context.close()
  }
})

test("Backspace at the start of an empty text block merges into the previous block", async ({ browser }) => {
  const host = await mountHost(browser, "First\n\nSecond\n")
  try {
    await selectBlock(host.page)
    const first = host.page.locator("#loomark-block-input")
    await first.focus()
    await first.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(textarea.value.length, textarea.value.length)
    })
    await first.press("Enter")
    const empty = host.page.locator("#loomark-block-input-1")
    await expect(empty).toBeFocused()
    await expect(empty).toHaveValue("")

    await empty.press("Backspace")

    await expect.poll(async () => (await snapshot(host.page)).source).toBe("First\n\nSecond\n")
    await expect(host.page.locator("[data-loomark-block-id]")).toHaveCount(2)
    await expect(first).toBeFocused()
    await expect.poll(() => first.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("5:5")
  } finally {
    await host.context.close()
  }
})

test("Backspace preserves focus when an unsupported predecessor rejects merge", async ({ browser }) => {
  const host = await mountHost(browser, "First\n\n---\n\nBody\n")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input-1")
    await input.fill("")
    await expect(input).toHaveValue("")
    const source = "First\n\n---\n\n\n"
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(source)

    await input.press("Backspace")

    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe(
      "editor-commit-failed",
    )
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(source)
    await expect(input).toBeFocused()
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("0:0")
  } finally {
    await host.context.close()
  }
})

test("boundary keys navigate between text blocks without changing source", async ({ browser }) => {
  const source = "First\n\nSecond\n\nThird\n"
  const host = await mountHost(browser, source)
  try {
    await selectBlock(host.page)
    const first = host.page.locator("#loomark-block-input")
    const second = host.page.locator("#loomark-block-input-1")
    await second.focus()
    await second.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(0, 0)
    })

    await second.press("ArrowLeft")
    await expect(first).toBeFocused()
    await expect.poll(() => first.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("5:5")

    await first.press("ArrowDown")
    await expect(second).toBeFocused()
    await expect.poll(() => second.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("0:0")

    await second.press("Backspace")
    await expect(first).toBeFocused()
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(source)
  } finally {
    await host.context.close()
  }
})

test("a direction key keeps native text cursor movement inside a Block editor", async ({ browser }) => {
  const source = "ABCDE\n"
  const host = await mountHost(browser, source)
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await expect(input).toHaveValue("ABCDE")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(3, 3)
    })

    await input.press("ArrowLeft")
    await expect(input).toBeFocused()
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("2:2")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(source)
  } finally {
    await host.context.close()
  }
})

test("Enter rejects unsupported list structure changes without mutating source", async ({ browser }) => {
  const source = "- Item\n\nTail\n"
  const host = await mountHost(browser, source)
  try {
    await selectBlock(host.page)
    const item = host.page.locator("#loomark-block-input")
    await item.focus()
    await item.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(textarea.value.length, textarea.value.length)
    })

    await item.press("Enter")

    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe(
      "block-selection-rejected",
    )
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(source)
    await expect(item).toBeFocused()
  } finally {
    await host.context.close()
  }
})

test("Enter edits fenced code payload without splitting its typed block", async ({ browser }) => {
  const host = await mountHost(browser, "```moonbit\nab\n```\n")
  try {
    await selectBlock(host.page)
    const code = host.page.locator("#loomark-block-input")
    await code.focus()
    await code.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(1, 1)
    })

    await code.press("Enter")

    await expect.poll(async () => (await snapshot(host.page)).source).toBe(
      "```moonbit\na\nb\n```\n",
    )
    await expect(host.page.locator('[data-loomark-block-kind="code"]')).toHaveCount(1)
    await expect(code).toBeFocused()
    await expect.poll(() => code.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("2:2")
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
    await input.press("Enter")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("block-selection-rejected")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Hello\n")
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("Hello")
    await expect(input).toBeFocused()
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("0:2")
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
    await input.press("Enter")
    await expect(host.page.locator("[data-loomark-block-id]")).toHaveCount(2)
    await expect(host.page.locator("#loomark-block-input")).toHaveValue("")
    await expect(host.page.locator("#loomark-block-input-1")).toHaveValue("Hello")
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-block-input")
    await expect.poll(() => host.page.evaluate(() => {
      const textarea = document.activeElement as HTMLTextAreaElement | null
      return textarea === null ? "missing" : `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("0:0")
    await input.fill("Before")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("Before\n\nHello\n")
  } finally {
    await host.context.close()
  }
})

test("Block split uses a typed structural edit and deterministic selection", async ({ browser }) => {
  const host = await mountHost(browser, "Hello\n\nWorld\n")
  try {
    await selectBlock(host.page)
    const firstInput = host.page.locator("#loomark-block-input")
    await firstInput.focus()
    await firstInput.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(2, 2)
    })
    await firstInput.press("Enter")
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
    await input.press("Enter")
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
    await replaceRawValue(host.page.locator("#loomark-input"), "edited\nsource")
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

test("failed normalized Raw input maps canonical CRLF to textarea offsets", async ({ browser }) => {
  const host = await mountHost(browser, "a\r\nb")
  try {
    const input = host.page.locator("#loomark-input")
    await expect(input).toHaveValue("a\nb")
    await input.focus()
    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)

    await dispatchRawNativeEdits(input, [{
      value: "a\nbx",
      beforeStart: 3,
      beforeEnd: 3,
      afterStart: 4,
      afterEnd: 4,
      data: "x",
    }])

    await expect.poll(async () => (await snapshot(host.page)).error_code)
      .toBe("editor-commit-failed")
    await expect(input).toHaveValue("a\nb")
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("3:3")
    await host.page.waitForTimeout(100)
    expect(await snapshot(host.page)).toMatchObject({
      source: "a\r\nb",
      error_code: "editor-commit-failed",
      error_count: 1,
    })
  } finally {
    await host.context.close()
  }
})

test("failed normalized Raw input maps canonical lone CR to textarea offsets", async ({ browser }) => {
  const host = await mountHost(browser, "a\rb")
  try {
    const input = host.page.locator("#loomark-input")
    await expect(input).toHaveValue("a\nb")
    await input.focus()
    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)

    await dispatchRawNativeEdits(input, [{
      value: "a\nbx",
      beforeStart: 3,
      beforeEnd: 3,
      afterStart: 4,
      afterEnd: 4,
      data: "x",
    }])

    await expect.poll(async () => (await snapshot(host.page)).error_code)
      .toBe("editor-commit-failed")
    await expect(input).toHaveValue("a\nb")
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("3:3")
    await host.page.waitForTimeout(100)
    expect(await snapshot(host.page)).toMatchObject({
      source: "a\rb",
      error_code: "editor-commit-failed",
      error_count: 1,
    })
  } finally {
    await host.context.close()
  }
})

test("Raw DOM selection conversion and post-render installation preserve direction", async ({ browser }) => {
  const host = await mountHost(browser, "a\r\nb\rc\n")
  try {
    const input = host.page.locator("#loomark-input")
    await expect(input).toHaveValue("a\nb\nc\n")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(2, 4, "backward")
    })

    await rawSelectionProbe(host.page, "capture")
    await expect.poll(async () => (await snapshot(host.page)).selection).toBe("5:3")

    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(0, 0, "none")
    })
    await rawSelectionProbe(host.page, "install")
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return {
        start: textarea.selectionStart,
        end: textarea.selectionEnd,
        direction: textarea.selectionDirection,
      }
    })).toEqual({ start: 2, end: 4, direction: "backward" })
  } finally {
    await host.context.close()
  }
})

test("accepted Raw selection edit supersedes pending full-source input", async ({ browser }) => {
  const host = await mountHost(browser, "abcdef")
  try {
    const input = host.page.locator("#loomark-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(0, 6, "backward")
    })
    await rawSelectionProbe(host.page, "capture")
    await expect.poll(async () => (await snapshot(host.page)).selection).toBe("6:0")

    await dispatchRawNativeEdits(input, [{
      value: "pending",
      beforeStart: 0,
      beforeEnd: 6,
      beforeDirection: "backward",
      afterStart: 7,
      afterEnd: 7,
      data: "pending",
    }])
    await commitCapturedRawSelection(host.page, "x")

    await expect.poll(async () => (await snapshot(host.page)).source).toBe("x")
    await host.page.waitForTimeout(100)
    expect(await snapshot(host.page)).toMatchObject({
      source: "x",
      committed_change_count: 1,
    })
    await expect(input).toHaveValue("x")
  } finally {
    await host.context.close()
  }
})

test("Raw browser draft coalesces to one canonical quiet-period flush", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    const input = host.page.locator("#loomark-input")
    const committedBefore = Number((await snapshot(host.page)).committed_change_count)
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      for (const value of ["starta", "startab", "startabc"]) {
        textarea.value = value
        textarea.setSelectionRange(value.length, value.length)
        textarea.dispatchEvent(new InputEvent("input", {
          bubbles: true,
          inputType: "insertText",
          data: value.at(-1),
        }))
      }
    })
    await expect(input).toHaveValue("startabc")
    expect(await snapshot(host.page)).toMatchObject({
      source: "startabc",
      committed_change_count: committedBefore,
    })
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count)
      .toBe(committedBefore + 1)
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("startabc")
  } finally {
    await host.context.close()
  }
})

test("Raw quiet period is fenced by draft identity across A to B to A", async ({ browser }) => {
  const context = await browser.newContext()
  await context.addInitScript(() => {
    const scope = globalThis as typeof globalThis & {
      __loomarkArmFlushClock?: () => void
      __loomarkPendingFlushes?: () => number
      __loomarkRunNextFlush?: () => void
    }
    const nativeSetTimeout = globalThis.setTimeout.bind(globalThis)
    const pending: Array<() => void> = []
    let armed = false
    let syntheticTimer = -1
    scope.__loomarkArmFlushClock = () => { armed = true }
    scope.__loomarkPendingFlushes = () => pending.length
    scope.__loomarkRunNextFlush = () => { pending.shift()?.() }
    globalThis.setTimeout = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
      if (armed && timeout === 250 && typeof handler === "function") {
        pending.push(() => handler(...args))
        return syntheticTimer--
      }
      return nativeSetTimeout(handler, timeout, ...args)
    }) as typeof globalThis.setTimeout
  })
  const mounted = await mountPage(context, "start")
  try {
    await mounted.page.evaluate(() => {
      ;(globalThis as typeof globalThis & { __loomarkArmFlushClock?: () => void })
        .__loomarkArmFlushClock?.()
    })
    const input = mounted.page.locator("#loomark-input")
    const committedBefore = Number((await snapshot(mounted.page)).committed_change_count)
    await replaceRawValue(input, "A")
    await replaceRawValue(input, "B")
    await replaceRawValue(input, "A")
    await expect.poll(() => mounted.page.evaluate(() => (
      globalThis as typeof globalThis & { __loomarkPendingFlushes?: () => number }
    ).__loomarkPendingFlushes?.())).toBe(3)

    await mounted.page.evaluate(() => {
      ;(globalThis as typeof globalThis & { __loomarkRunNextFlush?: () => void })
        .__loomarkRunNextFlush?.()
    })
    await mounted.page.waitForTimeout(20)
    expect(await snapshot(mounted.page)).toMatchObject({
      source: "A",
      committed_change_count: committedBefore,
    })

    await mounted.page.evaluate(() => {
      const scope = globalThis as typeof globalThis & { __loomarkRunNextFlush?: () => void }
      scope.__loomarkRunNextFlush?.()
      scope.__loomarkRunNextFlush?.()
    })
    await expect.poll(async () => (await snapshot(mounted.page)).committed_change_count)
      .toBe(committedBefore + 1)
    await expect.poll(async () => (await snapshot(mounted.page)).source).toBe("A")
  } finally {
    await context.close()
  }
})

test("Raw IME exposes its browser draft but canonicalizes only the final value", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    const input = host.page.locator("#loomark-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(5, 5)
    })
    const session = await host.context.newCDPSession(host.page)
    const committedBefore = Number((await snapshot(host.page)).committed_change_count)
    await session.send("Input.imeSetComposition", {
      text: "かんじ",
      selectionStart: 3,
      selectionEnd: 3,
    })
    await expect(input).toHaveValue("startかんじ")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("startかんじ")
    await host.page.waitForTimeout(350)
    expect((await snapshot(host.page)).committed_change_count).toBe(committedBefore)

    await session.send("Input.insertText", { text: "漢字" })
    await expect(input).toHaveValue("start漢字")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count)
      .toBe(committedBefore + 1)
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("start漢字")
  } finally {
    await host.context.close()
  }
})

test("Raw composition suppresses a quiet flush scheduled before compositionstart", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    const input = host.page.locator("#loomark-input")
    const committedBefore = Number((await snapshot(host.page)).committed_change_count)
    await replaceRawValue(input, "draft")
    await host.page.waitForTimeout(100)
    await input.evaluate(element => {
      element.dispatchEvent(new CompositionEvent("compositionstart", {
        bubbles: true,
        data: "",
      }))
    })
    await host.page.waitForTimeout(300)
    expect((await snapshot(host.page)).committed_change_count).toBe(committedBefore)
    await input.evaluate(element => {
      element.dispatchEvent(new CompositionEvent("compositionend", {
        bubbles: true,
        data: "draft",
      }))
    })
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count)
      .toBe(committedBefore + 1)
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("draft")
  } finally {
    await host.context.close()
  }
})

test("Raw mode boundary flushes the latest browser draft", async ({ browser }) => {
  const host = await mountHost(browser, "# Before\n")
  try {
    const committedBefore = Number((await snapshot(host.page)).committed_change_count)
    await replaceRawValue(host.page.locator("#loomark-input"), "# Draft\n")
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "# Draft\n")
    expect(await snapshot(host.page)).toMatchObject({
      source: "# Draft\n",
      committed_change_count: committedBefore + 1,
      mode: "preview",
    })
  } finally {
    await host.context.close()
  }
})

test("external canonical source supersedes an unflushed Raw browser draft", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    await replaceRawValue(host.page.locator("#loomark-input"), "draft")
    await requestSource(host.page, "external")
    await expect(host.page.locator("#loomark-input")).toHaveValue("external")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("external")
    await host.page.waitForTimeout(350)
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("external")
  } finally {
    await host.context.close()
  }
})

test("rejected Raw quiet-period flush restores accepted text without retry", async ({ browser }) => {
  const host = await mountHost(browser, "before")
  try {
    const committedBefore = Number((await snapshot(host.page)).committed_change_count)
    await forceEditorFailure(host.page)
    await replaceRawValue(host.page.locator("#loomark-input"), "rejected")
    await expect(host.page.locator("#loomark-input")).toHaveValue("rejected")
    await expect.poll(async () => (await snapshot(host.page)).error_code)
      .toBe("editor-commit-failed")
    await expect(host.page.locator("#loomark-input")).toHaveValue("before")
    expect(await snapshot(host.page)).toMatchObject({
      source: "before",
      committed_change_count: committedBefore,
      error_operation: "editor-dispatch",
    })
    await host.page.waitForTimeout(350)
    expect((await snapshot(host.page)).committed_change_count).toBe(committedBefore)
  } finally {
    await host.context.close()
  }
})

test("Block IME composition commits the accepted final value once", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(5, 5)
    })
    const session = await host.context.newCDPSession(host.page)

    await session.send("Input.imeSetComposition", {
      text: "かんじ",
      selectionStart: 3,
      selectionEnd: 3,
    })
    await expect(input).toHaveValue("startかんじ")
    expect(await snapshot(host.page)).toMatchObject({
      source: "start",
      committed_change_count: 0,
      error_code: null,
    })

    await session.send("Input.insertText", { text: "漢字" })

    await expect.poll(async () => (await snapshot(host.page)).source).toBe("start漢字")
    expect(await snapshot(host.page)).toMatchObject({
      committed_change_count: 1,
      error_code: null,
    })
    await expect(input).toHaveValue("start漢字")
    await expect(input).toBeFocused()
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return [textarea.selectionStart, textarea.selectionEnd]
    })).toEqual([7, 7])
  } finally {
    await host.context.close()
  }
})

test("Block IME composition supersedes ordinary input pending from the same task", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.value = "startX"
      textarea.setSelectionRange(6, 6)
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        data: "X",
        inputType: "insertText",
      }))
      textarea.dispatchEvent(new CompositionEvent("compositionstart", {
        bubbles: true,
        data: "",
      }))
      textarea.value = "startX漢"
      textarea.setSelectionRange(7, 7)
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        data: "漢",
        inputType: "insertCompositionText",
        isComposing: true,
      }))
      textarea.dispatchEvent(new CompositionEvent("compositionend", {
        bubbles: true,
        data: "漢",
      }))
    })

    await expect.poll(async () => (await snapshot(host.page)).source).toBe("startX漢")
    expect(await snapshot(host.page)).toMatchObject({
      committed_change_count: 1,
      error_code: null,
    })
    await expect(input).toHaveValue("startX漢")
  } finally {
    await host.context.close()
  }
})

test("Block IME preserves pending ordinary input when composition ends without input", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.value = "startX"
      textarea.setSelectionRange(6, 6)
      textarea.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        data: "X",
        inputType: "insertText",
      }))
      textarea.dispatchEvent(new CompositionEvent("compositionstart", {
        bubbles: true,
        data: "",
      }))
      textarea.dispatchEvent(new CompositionEvent("compositionend", {
        bubbles: true,
        data: "",
      }))
    })

    await expect.poll(async () => (await snapshot(host.page)).source).toBe("startX")
    expect(await snapshot(host.page)).toMatchObject({
      committed_change_count: 1,
      error_code: null,
    })
    await expect(input).toHaveValue("startX")
  } finally {
    await host.context.close()
  }
})

test("Block IME preserves paragraph, heading, list, and code syntax", async ({ browser }) => {
  const initial = "# Title\n\n- item\n\n~~~moonbit\ncode\n~~~\n\nparagraph\n"
  const host = await mountHost(browser, initial)
  try {
    await selectBlock(host.page)
    const session = await host.context.newCDPSession(host.page)
    const composeAtEnd = async (
      input: Locator,
      currentText: string,
      expectedSource: string,
    ): Promise<void> => {
      await input.focus()
      await input.evaluate((element, offset) => {
        const textarea = element as HTMLTextAreaElement
        textarea.setSelectionRange(offset, offset)
      }, currentText.length)
      await session.send("Input.imeSetComposition", {
        text: "漢",
        selectionStart: 1,
        selectionEnd: 1,
      })
      await session.send("Input.insertText", { text: "漢" })
      await expect.poll(async () => (await snapshot(host.page)).source).toBe(expectedSource)
    }

    let source = "# Title漢\n\n- item\n\n~~~moonbit\ncode\n~~~\n\nparagraph\n"
    await composeAtEnd(
      host.page.locator('[data-loomark-block-kind="heading"]'),
      "Title",
      source,
    )
    source = "# Title漢\n\n- item漢\n\n~~~moonbit\ncode\n~~~\n\nparagraph\n"
    await composeAtEnd(
      host.page.locator('[data-loomark-block-kind="unordered-list-item"]'),
      "item",
      source,
    )
    source = "# Title漢\n\n- item漢\n\n~~~moonbit\ncode漢\n~~~\n\nparagraph\n"
    await composeAtEnd(
      host.page.locator('[data-loomark-block-kind="code"]'),
      "code",
      source,
    )
    source = "# Title漢\n\n- item漢\n\n~~~moonbit\ncode漢\n~~~\n\nparagraph漢\n"
    await composeAtEnd(
      host.page.locator('[data-loomark-block-kind="paragraph"]'),
      "paragraph",
      source,
    )

    expect(await snapshot(host.page)).toMatchObject({
      source,
      committed_change_count: 4,
      error_code: null,
    })
  } finally {
    await host.context.close()
  }
})

test("canceling Block IME composition preserves canonical source and focus", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(5, 5)
    })
    const session = await host.context.newCDPSession(host.page)
    await session.send("Input.imeSetComposition", {
      text: "取消",
      selectionStart: 2,
      selectionEnd: 2,
    })
    await expect(input).toHaveValue("start取消")

    await session.send("Input.imeSetComposition", {
      text: "",
      selectionStart: 0,
      selectionEnd: 0,
    })

    expect(await snapshot(host.page)).toMatchObject({
      source: "start",
      committed_change_count: 0,
      error_code: null,
    })
    await expect(input).toHaveValue("start")
    await expect(input).toBeFocused()
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return [textarea.selectionStart, textarea.selectionEnd]
    })).toEqual([5, 5])
  } finally {
    await host.context.close()
  }
})

test("a Block mode click accepts composition before changing mode", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(5, 5)
    })
    const session = await host.context.newCDPSession(host.page)
    await session.send("Input.imeSetComposition", {
      text: "漢",
      selectionStart: 1,
      selectionEnd: 1,
    })

    await host.page.locator("#loomark-mode-raw").click()

    await expect.poll(async () => (await snapshot(host.page)).mode).toBe("raw")
    expect(await snapshot(host.page)).toMatchObject({
      source: "start漢",
      committed_change_count: 1,
      error_code: null,
    })
    await expect(host.page.locator("#loomark-input")).toHaveValue("start漢")
  } finally {
    await host.context.close()
  }
})

test("a synthetic mode change cancels unfinished Block composition", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    await selectBlock(host.page)
    const input = host.page.locator("#loomark-block-input")
    await input.focus()
    await input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      textarea.setSelectionRange(5, 5)
    })
    const session = await host.context.newCDPSession(host.page)
    await session.send("Input.imeSetComposition", {
      text: "未確定",
      selectionStart: 3,
      selectionEnd: 3,
    })
    await expect(input).toHaveValue("start未確定")

    await selectRaw(host.page)

    await expect.poll(async () => (await snapshot(host.page)).mode).toBe("raw")
    expect(await snapshot(host.page)).toMatchObject({
      source: "start",
      committed_change_count: 0,
      error_code: null,
    })
    await expect(host.page.locator("#loomark-input")).toHaveValue("start")
  } finally {
    await host.context.close()
  }
})

test("external source replacement supersedes pending Raw input", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    await dispatchRawNativeEdits(host.page.locator("#loomark-input"), [{
      value: "startX",
      beforeStart: 5,
      beforeEnd: 5,
      afterStart: 6,
      afterEnd: 6,
      data: "X",
    }])
    await requestSource(host.page, "external")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("external")
    await host.page.waitForTimeout(100)
    expect(await snapshot(host.page)).toMatchObject({ source: "external" })
  } finally {
    await host.context.close()
  }
})

test("snapshot restore supersedes pending Raw input", async ({ browser }) => {
  const host = await mountHost(browser, "start")
  try {
    await dispatchRawNativeEdits(host.page.locator("#loomark-input"), [{
      value: "startX",
      beforeStart: 5,
      beforeEnd: 5,
      afterStart: 6,
      afterEnd: 6,
      data: "X",
    }])
    await restoreSnapshot(host.page, 1, "restored", "raw")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("restored")
    await host.page.waitForTimeout(100)
    expect(await snapshot(host.page)).toMatchObject({ source: "restored", mode: "raw" })
  } finally {
    await host.context.close()
  }
})

test("Raw textarea editor failure preserves committed state and consumes the arm", async ({ browser }) => {
  const host = await mountHost(browser, "before\n")
  try {
    await selectRaw(host.page)
    const input = host.page.locator("#loomark-input")
    await expect(input).toHaveValue("before\n")
    await input.focus()
    await input.evaluate(element => {
      Object.assign(element, { __loomarkIdentity: "preserved" })
    })
    await forceEditorFailure(host.page)
    await expect.poll(async () => (await snapshot(host.page)).editor_failure_armed).toBe(true)
    const before = await snapshot(host.page)

    await replaceRawValue(input, "failed edit\n")
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
    await expect(input).toHaveValue("before\n")
    await expect(input).toBeFocused()
    await expect.poll(() => input.evaluate(element => {
      const textarea = element as HTMLTextAreaElement
      return `${textarea.selectionStart}:${textarea.selectionEnd}`
    })).toBe("7:7")
    await expect.poll(() => input.evaluate(
      element => (element as HTMLTextAreaElement & { __loomarkIdentity?: string }).__loomarkIdentity,
    )).toBe("preserved")
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
    await replaceRawValue(host.page.locator("#loomark-input"), "failed edit\n")
    await expect.poll(async () => (await snapshot(host.page)).error_code).toBe("editor-commit-failed")
    await expect(host.page.locator("#loomark-input")).toHaveValue("before\n")

    await replaceRawValue(host.page.locator("#loomark-input"), "retried edit\n")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("retried edit\n")
    await selectPreview(host.page)
    await expectPreviewSource(host.page, "retried edit\n")
  } finally {
    await host.context.close()
  }
})

test("Raw source transport preserves LF, CRLF, CR, EOF, and empty EOF sources", async ({ browser }) => {
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
    const restored = "# Restored\n\n> semantic quote\n"
    await restoreSnapshot(host.page, 1, restored, "preview")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe(restored)
    await expect.poll(async () => (await snapshot(host.page)).mode).toBe("preview")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(1)
    await expect(host.page.locator("#loomark-input")).toHaveCount(0)
    await expectPreviewSource(host.page, restored)
    await expect(host.page.locator('#loomark-preview h1[data-slot="typography-h1"]')).toHaveText("Restored")
    await expect(host.page.locator("#loomark-preview blockquote")).toHaveText("semantic quote")
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
