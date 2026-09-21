import { expect, test, chromium, type BrowserContext, type Page } from "@playwright/test"
import { spawn, type ChildProcess } from "node:child_process"
import { once } from "node:events"
import { mkdtemp, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const ORIGIN = "http://127.0.0.1:4327"
const ACCOUNT = "11111111-1111-4111-8111-111111111111"
const CONFLICT_ACCOUNT = "33333333-3333-4333-8333-333333333333"
const ACCOUNT_A = "44444444-4444-4444-8444-444444444444"
const OTHER_ACCOUNT = "22222222-2222-4222-8222-222222222222"
const here = dirname(fileURLToPath(import.meta.url))
const loomarkRoot = resolve(here, "../../..")
const wrangler = join(loomarkRoot, "node_modules/.bin/wrangler")

let workspace = ""
let worker: ChildProcess | undefined

async function command(args: string[]): Promise<void> {
  const child = spawn(wrangler, args, { cwd: loomarkRoot, stdio: ["ignore", "pipe", "pipe"] })
  let output = ""
  child.stdout?.on("data", chunk => { output += String(chunk) })
  child.stderr?.on("data", chunk => { output += String(chunk) })
  const [code] = await once(child, "close")
  if (code !== 0) throw new Error(`wrangler ${args.join(" ")} failed:\n${output}`)
}

async function startWorker(): Promise<void> {
  worker = spawn(wrangler, [
    "dev",
    "--config", "wrangler.sync-e2e.jsonc",
    "--port", "4327",
    "--persist-to", join(workspace, "state"),
  ], { cwd: loomarkRoot, stdio: ["ignore", "pipe", "pipe"] })
  let output = ""
  worker.stdout?.on("data", chunk => { output += String(chunk) })
  worker.stderr?.on("data", chunk => { output += String(chunk) })
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (worker.exitCode !== null) throw new Error(`wrangler dev exited early:\n${output}`)
    try {
      const response = await fetch(`${ORIGIN}/api/account`)
      if (response.status === 401) return
    } catch {
      // The socket is not ready yet.
    }
    await new Promise(resolve => setTimeout(resolve, 100))
  }
  throw new Error(`wrangler dev did not become ready:\n${output}`)
}

async function stopWorker(): Promise<void> {
  if (!worker || worker.exitCode !== null) return
  worker.kill("SIGTERM")
  await Promise.race([
    once(worker, "close"),
    new Promise(resolve => setTimeout(resolve, 5_000)),
  ])
  if (worker.exitCode === null) worker.kill("SIGKILL")
  worker = undefined
}

async function restartWorker(): Promise<void> {
  await stopWorker()
  await startWorker()
}

async function openProfile(name: string, mobile = false): Promise<BrowserContext> {
  return chromium.launchPersistentContext(join(workspace, name), {
    baseURL: ORIGIN,
    viewport: mobile ? { width: 390, height: 844 } : { width: 1280, height: 800 },
  })
}

async function signIn(
  context: BrowserContext,
  account: "phone" | "conflict" | "accountA" | "other",
) {
  const response = await context.request.post(`${ORIGIN}/__e2e__/session`, {
    data: { account },
  })
  expect(response.status()).toBe(200)
  return response.json() as Promise<{ id: string; name: string }>
}

async function expectSynced(page: Page): Promise<void> {
  await expect(page.getByRole("status")).toContainText("Synced", { timeout: 20_000 })
}

async function nextRender(page: Page): Promise<void> {
  await page.evaluate(() => new Promise<void>(resolve => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
  }))
}

function captureMutationOperationIds(page: Page, operationIds: string[]): void {
  page.on("request", request => {
    if (
      request.url().startsWith(`${ORIGIN}/api/documents/`) &&
      (request.method() === "PUT" || request.method() === "DELETE")
    ) {
      const body = JSON.parse(request.postData() ?? "{}") as { operationId?: string }
      if (body.operationId) operationIds.push(body.operationId)
    }
  })
}

async function createSynced(page: Page, account: string, text: string): Promise<string> {
  await page.goto("/")
  const editor = page.getByRole("textbox", { name: "Text" })
  await expect(editor).toBeVisible()
  await editor.fill(text)
  await page.getByRole("button", { name: "Sync", exact: true }).click()
  await expectSynced(page)
  const response = await page.request.get(`${ORIGIN}/api/documents`, {
    headers: { "X-Loomark-Account": account },
  })
  expect(response.status()).toBe(200)
  const body = await response.json() as { documents: Array<{ id: string }> }
  expect(body.documents).toHaveLength(1)
  return body.documents[0].id
}

async function openRemote(page: Page, name: string, text: string): Promise<void> {
  await page.goto("/")
  const toggle = page.getByRole("button", { name: "Toggle documents" })
  if (await toggle.getAttribute("aria-expanded") === "false") await toggle.click()
  const row = page.getByRole("button", { name, exact: true })
  await expect(row).toBeAttached({ timeout: 20_000 })
  await expect(row).toBeVisible({ timeout: 20_000 })
  await row.click()
  await expect(page.getByRole("textbox", { name: "Text" })).toHaveValue(text)
}

test.beforeAll(async () => {
  workspace = await mkdtemp(join(tmpdir(), "loomark-sync-e2e-"))
  await command([
    "d1", "migrations", "apply", "AUTH_DB",
    "--local",
    "--config", "wrangler.sync-e2e.jsonc",
    "--persist-to", join(workspace, "state"),
  ])
  await startWorker()
})

test.afterAll(async () => {
  await stopWorker()
  await rm(workspace, { recursive: true, force: true })
})

test("durable operation survives a lost response, browser close, and Worker restart", async () => {
  const exact = "# Restart proof\nスマホからの正確な本文 🌳\n"
  const operationIds: string[] = []
  let phone = await openProfile("restart-phone", true)
  await signIn(phone, "phone")
  let page = phone.pages()[0] ?? await phone.newPage()
  captureMutationOperationIds(page, operationIds)
  await page.goto("/")
  const editor = page.getByRole("textbox", { name: "Text" })
  await editor.fill(exact)
  await expect(page.getByRole("button", { name: "Sync", exact: true })).toBeVisible()
  expect((await page.request.post(`${ORIGIN}/__e2e__/lose-next-mutation-response`)).status())
    .toBe(204)
  await page.getByRole("button", { name: "Sync", exact: true }).click()
  await expect(page.getByRole("button", { name: "Retry sync" })).toBeVisible()
  const committed = await page.request.get(`${ORIGIN}/api/documents`, {
    headers: { "X-Loomark-Account": ACCOUNT },
  })
  expect(await committed.json()).toMatchObject({ documents: [{ revision: 1 }] })
  await phone.close()

  await restartWorker()

  const pc = await openProfile("restart-pc")
  await signIn(pc, "phone")
  const pcPage = pc.pages()[0] ?? await pc.newPage()
  const persisted = await pcPage.request.get(`${ORIGIN}/api/documents`, {
    headers: { "X-Loomark-Account": ACCOUNT },
  })
  expect(await persisted.json()).toMatchObject({ documents: [{ revision: 1 }] })
  await openRemote(pcPage, "Restart proof", exact)
  await expectSynced(pcPage)
  await pc.close()

  phone = await openProfile("restart-phone", true)
  await signIn(phone, "phone")
  page = phone.pages()[0] ?? await phone.newPage()
  captureMutationOperationIds(page, operationIds)
  await openRemote(page, "Restart proof", exact)
  await expectSynced(page)
  const remote = await page.request.get(`${ORIGIN}/api/documents`, {
    headers: { "X-Loomark-Account": ACCOUNT },
  })
  expect(await remote.json()).toMatchObject({ documents: [{ revision: 1 }] })
  expect(operationIds).toHaveLength(2)
  expect(operationIds[1]).toBe(operationIds[0])
  await phone.close()
})

test("divergent browser edits preserve the local branch and expose the remote branch", async () => {
  const baseline = "# Shared baseline\n"
  const phoneText = "# Phone branch\nオフラインの編集\n"
  const pcText = "# PC branch\nサーバー側の編集\n"
  const phone = await openProfile("conflict-phone")
  const pc = await openProfile("conflict-pc")
  await signIn(phone, "conflict")
  await signIn(pc, "conflict")
  const phonePage = phone.pages()[0] ?? await phone.newPage()
  await createSynced(phonePage, CONFLICT_ACCOUNT, baseline)
  const pcPage = pc.pages()[0] ?? await pc.newPage()
  await openRemote(pcPage, "Shared baseline", baseline)

  await phone.setOffline(true)
  const phoneEditor = phonePage.getByRole("textbox", { name: "Text" })
  await phoneEditor.evaluate(element => {
    ;(globalThis as typeof globalThis & { __conflictTextArea?: HTMLTextAreaElement })
      .__conflictTextArea = element as HTMLTextAreaElement
  })
  await phoneEditor.fill(phoneText)
  await expect(phonePage.getByRole("button", { name: "Retry sync" })).toBeVisible()
  await phoneEditor.press("End")
  await phoneEditor.pressSequentially("x")
  await phoneEditor.dispatchEvent("compositionstart", { data: "" })
  const composingText = `${phoneText}x`
  await expect(phoneEditor).toHaveValue(composingText)
  await phoneEditor.evaluate(element => {
    const textArea = element as HTMLTextAreaElement
    textArea.focus()
    textArea.setSelectionRange(2, 8)
  })

  await pcPage.getByRole("textbox", { name: "Text" }).fill(pcText)
  await expectSynced(pcPage)

  await phone.setOffline(false)
  await phonePage.getByRole("button", { name: "Retry sync" }).click()
  await expect(phoneEditor).toHaveValue(composingText)
  await expect(phonePage.getByRole("button", { name: "PC branch", exact: true }))
    .toBeVisible({ timeout: 20_000 })
  await expect(phonePage.getByRole("button", { name: "Phone branch", exact: true }))
    .toBeVisible()
  await expect.poll(() => phoneEditor.evaluate(element => (
    element === (globalThis as typeof globalThis & {
      __conflictTextArea?: HTMLTextAreaElement
    }).__conflictTextArea
  ))).toBe(true)
  expect(await phoneEditor.evaluate(element => {
    const textArea = element as HTMLTextAreaElement
    return [textArea.selectionStart, textArea.selectionEnd]
  })).toEqual([2, 8])
  await phoneEditor.dispatchEvent("compositionend", { data: "" })
  await nextRender(phonePage)
  await phoneEditor.press("Control+z")
  await expect(phoneEditor).toHaveValue(phoneText)
  await nextRender(phonePage)
  await phonePage.getByRole("button", { name: "Phone branch", exact: true }).click()
  await expect(phoneEditor).toHaveValue(phoneText)
  await phonePage.getByRole("button", { name: "PC branch", exact: true }).click()
  await expect(phoneEditor).toHaveValue(pcText)
  await phone.close()
  await pc.close()
})

test("switching accounts hides retained replicas and isolates guessed identities", async () => {
  const context = await openProfile("account-switch")
  await signIn(context, "accountA")
  const page = context.pages()[0] ?? await context.newPage()
  const firstId = await createSynced(page, ACCOUNT_A, "# Private A\n")
  const editor = page.getByRole("textbox", { name: "Text" })

  const other = await signIn(context, "other")
  expect(other.id).toBe(OTHER_ACCOUNT)
  const pendingA = "# Private A\nPending while account changes\n"
  await editor.fill(pendingA)
  await expect(page.locator('[role="status"][aria-live="polite"]'))
    .toContainText("Other account", { timeout: 20_000 })
  await expect(page.getByRole("button", { name: "Private A", exact: true })).toHaveCount(0)
  const guessed = await page.request.get(`${ORIGIN}/api/documents/${firstId}`, {
    headers: { "X-Loomark-Account": OTHER_ACCOUNT },
  })
  expect(guessed.status()).toBe(404)
  const guessedMutation = await page.request.delete(`${ORIGIN}/api/documents/${firstId}`, {
    headers: {
      "X-Loomark-Account": OTHER_ACCOUNT,
      "Content-Type": "application/json",
      Origin: ORIGIN,
    },
    data: { operationId: crypto.randomUUID(), baseRevision: 1 },
  })
  expect(guessedMutation.status()).toBe(409)

  await page.getByRole("button", { name: "New document" }).click()
  await expect(editor).toHaveValue("")
  await editor.fill("# Private B\n")
  await page.getByRole("button", { name: "Sync", exact: true }).click()
  await expectSynced(page)

  const original = await signIn(context, "accountA")
  expect(original.id).toBe(ACCOUNT_A)
  await page.reload()
  const privateA = page.getByRole("button", { name: "Private A", exact: true })
  await expect(privateA).toBeVisible()
  await expect(page.getByRole("button", { name: "Private B", exact: true })).toHaveCount(0)
  await privateA.click()
  await expect(editor).toHaveValue(pendingA)
  await expectSynced(page)
  const unchanged = await page.request.get(`${ORIGIN}/api/documents/${firstId}`, {
    headers: { "X-Loomark-Account": ACCOUNT_A },
  })
  expect(await unchanged.json()).toMatchObject({ revision: 2, text: pendingA })
  await context.close()
})
