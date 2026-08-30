import { spawn } from "node:child_process"
import { once } from "node:events"
import { fileURLToPath } from "node:url"

const portText = process.env.LOOMARK_STANDALONE_PORT ?? "4317"
const port = Number(portText)
if (!/^\d+$/.test(portText) || !Number.isInteger(port) || port < 1 || port > 65_535) {
  throw new Error("LOOMARK_STANDALONE_PORT must be an integer from 1 through 65535")
}
const serverPath = fileURLToPath(new URL("./serve-standalone-dist.mjs", import.meta.url))
const playwrightPath = fileURLToPath(new URL("./node_modules/playwright/cli.js", import.meta.url))
const playwrightConfig = process.env.LOOMARK_PLAYWRIGHT_CONFIG ?? "playwright.standalone.config.ts"
const server = spawn(process.execPath, [serverPath], {
  env: { ...process.env, LOOMARK_STANDALONE_PORT: String(port) },
  stdio: ["ignore", "pipe", "inherit"],
})

let playwright
let stopping = false

const serverReady = new Promise((resolve, reject) => {
  const timeout = setTimeout(
    () => reject(new Error("standalone static server did not become ready")),
    5_000,
  )
  server.stdout.setEncoding("utf8")
  server.stdout.on("data", chunk => {
    process.stdout.write(chunk)
    if (chunk.includes(`http://127.0.0.1:${port}`)) {
      clearTimeout(timeout)
      resolve()
    }
  })
  server.once("error", error => {
    clearTimeout(timeout)
    reject(error)
  })
  server.once("close", code => {
    clearTimeout(timeout)
    reject(new Error(`standalone static server exited before readiness (${code ?? "signal"})`))
  })
})

async function stopServer() {
  if (server.exitCode !== null) return
  server.kill("SIGTERM")
  await Promise.race([
    once(server, "close"),
    new Promise(resolve => setTimeout(resolve, 1_000)),
  ])
  if (server.exitCode === null) server.kill("SIGKILL")
}

async function stopForSignal(exitCode) {
  if (stopping) return
  stopping = true
  if (playwright?.exitCode === null) playwright.kill("SIGTERM")
  await stopServer()
  process.exit(exitCode)
}

process.once("SIGINT", () => void stopForSignal(130))
process.once("SIGTERM", () => void stopForSignal(143))

try {
  await serverReady

  playwright = spawn(
    process.execPath,
    [playwrightPath, "test", `--config=${playwrightConfig}`, ...process.argv.slice(2)],
    { stdio: "inherit" },
  )
  const [code] = await once(playwright, "close")
  process.exitCode = typeof code === "number" ? code : 1
} finally {
  await stopServer()
}
