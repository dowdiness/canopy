import { expect, test, type Browser, type BrowserContext, type Page } from "@playwright/test"

/**
 * #1073 behavioral boundary matrix (each row gets a fresh BrowserContext,
 * page, and connected mount container; no case clears/reuses/remounts it):
 *
 * | mode/event | source shape | result |
 * | Raw -> Preview | new/same, LF/CRLF/CR/EOF | exact source, one commit only when changed |
 * | snapshot restore | v1 / unknown version | source+mode atomic / no transaction |
 * | editor commit | success / failure | install+change / unchanged+one categorized error |
 * | focus | control/stale/malformed/mode-inapplicable | exact compatible target / no move |
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

async function mountHost(browser: Browser, source: string): Promise<Host> {
  const context = await browser.newContext()
  const page = await context.newPage()
  await page.goto(pageUrl)
  const mountResult = await page.evaluate(
    ({ moduleUrl, source }) =>
      import(moduleUrl).then(module => module.mount_dev_host("app", source)),
    { moduleUrl, source },
  )
  await expect(page.locator("#loomark-root")).toBeVisible()
  await expect.poll(async () => (await snapshot(page)).control_ready).toBe(true)
  return { context, page, mountResult }
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

async function selectRaw(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_select_raw()), moduleUrl)
}

async function restoreSnapshot(page: Page, version: number, source: string, mode: "raw" | "preview"): Promise<void> {
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
    await expect(host.page.locator("#loomark-preview")).toHaveText("after\r\n")
  } finally {
    await host.context.close()
  }
})

test("Raw textarea input uses the atomic editor transaction and mode toolbar", async ({ browser }) => {
  const host = await mountHost(browser, "before\n")
  try {
    await selectRaw(host.page)
    await expect(host.page.locator("#loomark-input")).toHaveCount(1)
    await host.page.locator("#loomark-input").fill("edited\nsource")
    await expect.poll(async () => (await snapshot(host.page)).source).toBe("edited\nsource")
    await expect.poll(async () => (await snapshot(host.page)).committed_change_count).toBe(1)
    await selectPreview(host.page)
    await expect(host.page.locator("#loomark-input")).toHaveCount(0)
    await expect(host.page.locator("#loomark-mode")).toHaveText("mode: preview")
    await expect(host.page.locator("#loomark-preview")).toHaveText("edited\nsource")
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
    await expect(host.page.locator("#loomark-preview")).toHaveText("retried edit\n")
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
    await expect(host.page.locator("#loomark-preview")).toHaveText("new\r\n")
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
    await expect(host.page.locator("#app")).toContainText("# Loomark")
    await expect.poll(() => host.page.evaluate(() => document.getElementById("app")?.isConnected)).toBe(true)
  } finally {
    await host.context.close()
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
    await expect(host.page.locator("#loomark-preview")).toHaveText("first\n")
  } finally {
    await host.context.close()
  }
})

test("keeps source and mode state separate from after-render focus and DOM effects", async ({ browser }) => {
  const host = await mountHost(browser, "# Effects\n")
  try {
    await requestSource(host.page, "# Updated\n")
    await selectPreview(host.page)
    await expect(host.page.locator("#loomark-mode")).toHaveText("mode: preview")
    await expect(host.page.locator("#loomark-preview")).toHaveText("# Updated\n")

    await focusPreview(host.page)
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-focus-target")

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
    await expect(host.page.locator("#loomark-preview")).toHaveText("events-updated\n")
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
