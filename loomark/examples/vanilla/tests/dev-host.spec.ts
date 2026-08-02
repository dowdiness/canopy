import { expect, test, type Browser, type BrowserContext, type Page } from "@playwright/test"

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

async function selectPreview(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_select_preview()), moduleUrl)
}

async function focusPreview(page: Page): Promise<void> {
  await page.evaluate(moduleUrl =>
    import(moduleUrl).then(module => module.dev_host_focus_preview()), moduleUrl)
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
    await expect(host.page.locator("#app")).toContainText("# Loomark")
    await expect.poll(() => host.page.evaluate(() => document.getElementById("app")?.isConnected)).toBe(true)
    expect(await snapshot(host.page)).toMatchObject({ source: "# Loomark\n", mode: "raw" })
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
    await expect(host.page.locator("#loomark-preview")).toHaveText("first\n")
  } finally {
    await host.context.close()
  }
})

test("keeps source and mode state separate from after-render focus and DOM effects", async ({ browser }) => {
  const host = await mountHost(browser, "# Effects\n")
  try {
    await requestSource(host.page, "# Updated\n")
    await expect(host.page.locator("#loomark-preview")).toHaveText("# Updated\n")
    await selectPreview(host.page)
    await expect(host.page.locator("#loomark-mode")).toHaveText("mode: preview")

    await focusPreview(host.page)
    await expect.poll(() => host.page.evaluate(() => document.activeElement?.id)).toBe("loomark-focus-target")

    await writeSelection(host.page, 1, 3)
    await expect.poll(async () => (await snapshot(host.page)).selection).toBe("1:3")
    await writeSelectionFailure(host.page)
    await expect.poll(async () => String((await snapshot(host.page)).error)).toContain("DOM element not found")

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
