import { spawn } from "node:child_process"
import { once } from "node:events"
import { fileURLToPath } from "node:url"

const port = Number.parseInt(process.env.LOOMARK_STANDALONE_PORT ?? "4317", 10)
const serverPath = fileURLToPath(new URL("./serve-standalone-dist.mjs", import.meta.url))
const playwrightPath = fileURLToPath(new URL("./node_modules/playwright/cli.js", import.meta.url))
const server = spawn(process.execPath, [serverPath], {
  env: { ...process.env, LOOMARK_STANDALONE_PORT: String(port) },
  stdio: ["ignore", "pipe", "inherit"],
})

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

try {
  await serverReady

  const playwright = spawn(
    process.execPath,
    [playwrightPath, "test", "--config=playwright.standalone.config.ts", ...process.argv.slice(2)],
    { stdio: "inherit" },
  )
  const [code] = await once(playwright, "close")
  process.exitCode = typeof code === "number" ? code : 1
} finally {
  await stopServer()
}
