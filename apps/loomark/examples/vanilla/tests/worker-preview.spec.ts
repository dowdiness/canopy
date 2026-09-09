import { expect, test as base } from '@playwright/test'

const test = base.extend({
  page: async ({ page }, use) => {
    await page.addInitScript(() => {
      const url = new URL(location.href)
      if (!url.protocol.startsWith('http')) return
      url.searchParams.set('preview-worker', '1')
      history.replaceState(null, '', url)
      const metrics = { workers: [] as Worker[], urls: [] as string[], requests: [] as unknown[], held: [] as [Worker, unknown][], hold: false }
      ;(window as unknown as { workerProbe: typeof metrics }).workerProbe = metrics
      const Original = window.Worker
      window.Worker = class extends Original {
        constructor(url: string | URL, options?: WorkerOptions) {
          super(url, options)
          metrics.workers.push(this)
          metrics.urls.push(String(url))
          const post = this.postMessage.bind(this)
          this.postMessage = (message: unknown, transfer?: Transferable[] | StructuredSerializeOptions) => {
            if (typeof message === 'string' && JSON.parse(message).type === 'preview') metrics.requests.push(JSON.parse(message))
            if (Array.isArray(transfer)) post(message, transfer)
            else post(message, transfer)
          }
          this.addEventListener('message', e => {
            if (metrics.hold && typeof e.data === 'string' && JSON.parse(e.data).type === 'preview') {
              e.stopImmediatePropagation()
              metrics.held.push([this, e.data])
            }
          })
        }
      }
    })
    await use(page)
  },
})

test('Worker is the actual Preview source, coalesces latest input and ACKs rejection', async ({ page }) => {
  await page.goto('/')
  const text = page.getByRole('textbox', { name: 'Text', exact: true })
  await text.fill('# Worker first')
  await page.evaluate(() => { (window as any).workerProbe.hold = true })
  await page.getByRole('tab', { name: 'Split', exact: true }).click()
  await expect.poll(() => page.evaluate(() => (window as any).workerProbe.held.length)).toBe(1)
  expect(await page.evaluate(() => (window as any).workerProbe.urls)).toEqual([expect.stringMatching(/^blob:/)])
  await expect(page.getByRole('heading', { name: 'Worker first', exact: true })).toHaveCount(0)
  await text.fill('# Intermediate')
  await text.fill('# Latest 😀')
  await page.waitForTimeout(100)
  expect(await page.evaluate(() => (window as any).workerProbe.requests.length)).toBe(1)
  await page.evaluate(() => {
    const p = (window as any).workerProbe; p.hold = false
    for (const [worker, data] of p.held.splice(0)) worker.dispatchEvent(new MessageEvent('message', { data }))
  })
  await expect(page.getByRole('heading', { name: 'Latest 😀', exact: true })).toBeVisible()
  expect(await page.evaluate(() => (window as any).workerProbe.requests.length)).toBe(2)
  await expect(page.getByRole('heading', { name: 'Intermediate', exact: true })).toHaveCount(0)
})

test('first Preview demand works offline while the HTTP Worker asset is aborted', async ({ page }) => {
  let aborted = 0
  await page.context().route('**/preview-worker.js', async route => {
    aborted += 1
    await route.abort('internetdisconnected')
  })
  await page.goto('/')
  await page.context().setOffline(true)
  const text = page.getByRole('textbox', { name: 'Text', exact: true })
  await text.fill('# Offline first')
  await page.getByRole('tab', { name: 'Split', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Offline first', exact: true })).toBeVisible()
  expect(aborted).toBe(0)
})

test('Worker failure releases busy state, retains display and restarts offline on next edit', async ({ page }) => {
  await page.goto('/')
  await page.context().route('**/preview-worker.js', route => route.abort('internetdisconnected'))
  await page.context().setOffline(true)
  const text = page.getByRole('textbox', { name: 'Text', exact: true })
  await text.fill('# Accepted')
  await page.getByRole('tab', { name: 'Split', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Accepted', exact: true })).toBeVisible()
  await page.evaluate(() => { (window as any).workerProbe.hold = true })
  await text.fill('# Pending')
  await expect.poll(() => page.evaluate(() => (window as any).workerProbe.held.length)).toBe(1)
  await page.evaluate(() => {
    const p = (window as any).workerProbe; p.hold = false
    p.workers[0].dispatchEvent(new ErrorEvent('error', { message: 'injected Worker failure' }))
  })
  await expect(page.getByRole('alert')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Accepted', exact: true })).toBeVisible()
  await text.fill('# Restarted')
  await expect(page.getByRole('heading', { name: 'Restarted', exact: true })).toBeVisible()
  expect(await page.evaluate(() => (window as any).workerProbe.workers.length)).toBe(2)
  expect(await page.evaluate(() => new Set((window as any).workerProbe.urls).size)).toBe(1)
})

test('document activation offline discards old Worker completion while latest document stays current', async ({ page }) => {
  await page.goto('/')
  await page.context().route('**/preview-worker.js', route => route.abort('internetdisconnected'))
  await page.context().setOffline(true)
  const text = page.getByRole('textbox', { name: 'Text', exact: true })
  await text.fill('# Old document')
  await page.evaluate(() => { (window as any).workerProbe.hold = true })
  await page.getByRole('tab', { name: 'Split', exact: true }).click()
  await expect.poll(() => page.evaluate(() => (window as any).workerProbe.held.length)).toBe(1)
  await page.evaluate(() => { (window as any).workerProbe.hold = false })
  await page.getByRole('button', { name: 'New document', exact: true }).click()
  await expect(text).toHaveValue('')
  await text.fill('# New owner')
  await expect(page.getByRole('heading', { name: 'New owner', exact: true })).toBeVisible()
  await page.evaluate(() => {
    const p = (window as any).workerProbe
    for (const [worker, data] of p.held.splice(0)) worker.dispatchEvent(new MessageEvent('message', { data }))
  })
  await page.waitForTimeout(100)
  await expect(page.getByRole('heading', { name: 'Old document', exact: true })).toHaveCount(0)
  await expect(page.getByRole('heading', { name: 'New owner', exact: true })).toBeVisible()
})

test('an inflight Worker result cannot publish during composition', async ({ page }) => {
  await page.goto('/')
  const text = page.getByRole('textbox', { name: 'Text', exact: true })
  await text.fill('# Composing')
  await page.evaluate(() => { (window as any).workerProbe.hold = true })
  await page.getByRole('tab', { name: 'Split', exact: true }).click()
  await expect.poll(() => page.evaluate(() => (window as any).workerProbe.held.length)).toBe(1)
  await text.evaluate(el => el.dispatchEvent(new CompositionEvent('compositionstart', {bubbles:true})))
  await page.evaluate(() => {
    const p = (window as any).workerProbe; p.hold = false
    for (const [worker,data] of p.held.splice(0)) worker.dispatchEvent(new MessageEvent('message',{data}))
  })
  await page.waitForTimeout(100)
  await expect(page.getByRole('heading', {name:'Composing',exact:true})).toHaveCount(0)
  expect(await page.evaluate(() => (window as any).workerProbe.requests.length)).toBe(1)
  await text.evaluate(el => el.dispatchEvent(new CompositionEvent('compositionend',{bubbles:true,data:''})))
  await expect(page.getByRole('heading', {name:'Composing',exact:true})).toBeVisible()
})

test('malformed Worker payload does not fall back to the main parser', async ({ page }) => {
  await page.goto('/')
  await page.evaluate(() => {
    const payload = document.getElementById('loomark-preview-worker-payload')
    if (!payload) throw new Error('Preview Worker payload missing')
    payload.textContent = '{malformed'
  })
  const text = page.getByRole('textbox', { name: 'Text', exact: true })
  await text.fill('# Must not render')
  await page.getByRole('tab', { name: 'Split', exact: true }).click()
  await expect(page.getByRole('alert')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Must not render', exact: true })).toHaveCount(0)
})

test('missing Worker payload does not fall back to the main parser', async ({ page }) => {
  await page.goto('/')
  await page.evaluate(() => document.getElementById('loomark-preview-worker-payload')?.remove())
  const text = page.getByRole('textbox', { name: 'Text', exact: true })
  await text.fill('# Must not render')
  await page.getByRole('tab', { name: 'Split', exact: true }).click()
  await expect(page.getByRole('alert')).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Must not render', exact: true })).toHaveCount(0)
})

test('silent Worker timeout preserves text and allows a fresh request', async ({ page }) => {
  await page.goto('/')
  const text = page.getByRole('textbox', {name:'Text',exact:true})
  await text.fill('# Timeout')
  await page.evaluate(() => { (window as any).workerProbe.hold = true })
  await page.getByRole('tab', {name:'Split',exact:true}).click()
  await expect(page.getByRole('alert')).toBeVisible({timeout:13000})
  await expect(text).toHaveValue('# Timeout')
  await page.evaluate(() => { (window as any).workerProbe.hold = false })
  await text.fill('# After timeout')
  await expect(page.getByRole('heading', {name:'After timeout',exact:true})).toBeVisible()
  expect(await page.evaluate(() => (window as any).workerProbe.workers.length)).toBe(2)
})
