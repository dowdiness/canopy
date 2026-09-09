import { expect, test } from "@playwright/test"

type Probe = {
  workers: Array<{ terminateCalls: number; worker: Worker }>
  createdUrls: string[]
  revokedUrls: string[]
  held: Array<{ worker: Worker; data: string }>
  hold: boolean
  timers: number[]
  late: Array<() => void>
}

function installProbe(): void {
  const state = globalThis as typeof globalThis & { __loomarkFixtureProbe?: Probe }
  const probe: Probe = { workers: [], createdUrls: [], revokedUrls: [], held: [], hold: false, timers: [], late: [] }
  state.__loomarkFixtureProbe = probe
  const originalSet = window.setTimeout.bind(window)
  const originalClear = window.clearTimeout.bind(window)
  window.setTimeout = ((handler: TimerHandler, delay?: number, ...args: unknown[]) => {
    const id = originalSet(handler, delay, ...args)
    if (delay === 10000) probe.timers.push(id)
    return id
  }) as typeof window.setTimeout
  window.clearTimeout = id => {
    probe.timers = probe.timers.filter(timer => timer !== id)
    originalClear(id)
  }
  const originalWorker = window.Worker
  window.Worker = class extends originalWorker {
    constructor(url: string | URL, options?: WorkerOptions) {
      super(url, options)
      const entry = { terminateCalls: 0, worker: this as Worker }
      probe.workers.push(entry)
      const terminate = this.terminate.bind(this)
      this.terminate = () => {
        entry.terminateCalls += 1
        terminate()
      }
      this.addEventListener("message", event => {
        if (probe.hold && typeof event.data === "string") {
          try {
            if (JSON.parse(event.data).type === "preview") {
              event.stopImmediatePropagation()
              probe.held.push({ worker: this as Worker, data: event.data })
            }
          } catch (_) {
            // The application handles malformed messages; the probe only holds previews.
          }
        }
      })
    }
  }
  const originalCreate = URL.createObjectURL.bind(URL)
  const originalRevoke = URL.revokeObjectURL.bind(URL)
  URL.createObjectURL = value => {
    const url = originalCreate(value)
    probe.createdUrls.push(url)
    return url
  }
  URL.revokeObjectURL = url => {
    probe.revokedUrls.push(url)
    originalRevoke(url)
  }
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(installProbe)
})

test("switch_by unmount balances Worker and blob resources across repeated remounts", async ({ page }) => {
  await page.goto("/?preview-worker=1")
  const toggle = page.getByRole("button", { name: "Toggle Loomark app", exact: true })
  const text = page.getByRole("textbox", { name: "Text", exact: true })

  for (let cycle = 0; cycle < 3; cycle += 1) {
    await text.fill(`# Cycle ${cycle}`)
    await page.getByRole("tab", { name: "Split", exact: true }).click()
    await expect(page.getByRole("heading", { name: `Cycle ${cycle}`, exact: true })).toBeVisible()
    await toggle.click()
    await expect(text).toHaveCount(0)
    await toggle.click()
    await expect(page.getByRole("textbox", { name: "Text", exact: true })).toBeVisible()
  }

  const resources = await page.evaluate(() => {
    const probe = (globalThis as typeof globalThis & { __loomarkFixtureProbe: Probe }).__loomarkFixtureProbe
    return {
      workers: probe.workers.length,
      terminated: probe.workers.filter(entry => entry.terminateCalls === 1).length,
      created: probe.createdUrls.length,
      revoked: probe.revokedUrls.length,
      timers: probe.timers.length,
      balanced: [...probe.createdUrls].sort().join() === [...probe.revokedUrls].sort().join(),
    }
  })
  expect(resources).toEqual({ workers: 3, terminated: 3, created: 3, revoked: 3, timers: 0, balanced: true })
})

test("unmount fences held callbacks and a remount remains live", async ({ page }) => {
  await page.goto("/?preview-worker=1")
  const toggle = page.getByRole("button", { name: "Toggle Loomark app", exact: true })
  const text = page.getByRole("textbox", { name: "Text", exact: true })
  await text.fill("# Old owner")
  await page.evaluate(() => {
    (globalThis as typeof globalThis & { __loomarkFixtureProbe: Probe }).__loomarkFixtureProbe.hold = true
  })
  await page.getByRole("tab", { name: "Split", exact: true }).click()
  await expect.poll(() => page.evaluate(() => (
    (globalThis as typeof globalThis & { __loomarkFixtureProbe: Probe }).__loomarkFixtureProbe.held.length
  ))).toBe(1)
  await page.evaluate(() => {
    const p = (globalThis as typeof globalThis & { __loomarkFixtureProbe: Probe }).__loomarkFixtureProbe
    const held = p.held[0]
    const handler = held.worker.onmessage
    if (handler) p.late.push(() => handler.call(held.worker, new MessageEvent('message', {data: held.data})))
  })

  await toggle.click()
  await expect(text).toHaveCount(0)
  expect(await page.evaluate(() => {
    const p = (globalThis as typeof globalThis & { __loomarkFixtureProbe: Probe }).__loomarkFixtureProbe
    return [p.timers.length, p.revokedUrls.length]
  })).toEqual([0, 1])
  await toggle.click()
  const freshText = page.getByRole("textbox", { name: "Text", exact: true })
  await freshText.fill("# New owner")
  await page.evaluate(() => {
    const probe = (globalThis as typeof globalThis & { __loomarkFixtureProbe: Probe }).__loomarkFixtureProbe
    probe.hold = false
    for (const callback of probe.late.splice(0)) callback()
    for (const held of probe.held.splice(0)) {
      held.worker.dispatchEvent(new MessageEvent("message", { data: held.data }))
    }
  })
  await page.getByRole("tab", { name: "Split", exact: true }).click()
  await expect(page.getByRole("heading", { name: "New owner", exact: true })).toBeVisible()
  await expect(page.getByRole("heading", { name: "Old owner", exact: true })).toHaveCount(0)

  const terminated = await page.evaluate(() => (
    (globalThis as typeof globalThis & { __loomarkFixtureProbe: Probe }).__loomarkFixtureProbe
      .workers.filter(entry => entry.terminateCalls === 1).length
  ))
  expect(terminated).toBe(1)
})

test('unmount before deferred preparation cannot create a Worker later', async ({page}) => {
  await page.goto('/?preview-worker=1')
  await page.getByRole('textbox', {name:'Text',exact:true}).fill('# Deferred')
  const split = await page.getByRole('tab', {name:'Split',exact:true}).elementHandle()
  const toggle = await page.getByRole('button', {name:'Toggle Loomark app',exact:true}).elementHandle()
  await page.evaluate(({split,toggle}) => {
    if (!(split instanceof HTMLElement) || !(toggle instanceof HTMLElement)) throw Error('missing fixture controls')
    split.click()
    toggle.click()
  }, {split,toggle})
  await expect(page.getByRole('textbox', {name:'Text',exact:true})).toHaveCount(0)
  await page.waitForTimeout(300)
  expect(await page.evaluate(() => {
    const p = (globalThis as typeof globalThis & { __loomarkFixtureProbe: Probe }).__loomarkFixtureProbe
    return [p.workers.length,p.createdUrls.length,p.timers.length]
  })).toEqual([0,0,0])
})
