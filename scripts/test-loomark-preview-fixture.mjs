import { spawn } from "node:child_process"
import { once } from "node:events"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("../", import.meta.url))
const vanilla = `${root}/apps/loomark/examples/vanilla`
const port = process.env.LOOMARK_FIXTURE_PORT ?? "4326"
const server = spawn(process.execPath, [`${vanilla}/serve-standalone-dist.mjs`], {
  cwd: vanilla,
  env: { ...process.env, LOOMARK_STANDALONE_PORT: port, LOOMARK_STANDALONE_DIST: `${root}/_build/loomark-worker-fixture` },
  stdio: ["ignore", "pipe", "inherit"],
})
const ready = new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error("fixture server did not become ready")), 5_000)
  server.stdout.setEncoding("utf8")
  server.stdout.on("data", chunk => {
    process.stdout.write(chunk)
    if (chunk.includes(`http://127.0.0.1:${port}`)) {
      clearTimeout(timeout)
      resolve()
    }
  })
  server.once("error", reject)
})
try {
  await ready
  const result = spawn(process.execPath, [
    `${vanilla}/node_modules/playwright/cli.js`,
    "test",
    `--config=${vanilla}/playwright.worker-fixture.config.ts`,
    ...process.argv.slice(2),
  ], { cwd: vanilla, env: { ...process.env, LOOMARK_FIXTURE_PORT: port }, stdio: "inherit" })
  const [code] = await once(result, "close")
  process.exitCode = typeof code === "number" ? code : 1
} finally {
  server.kill("SIGTERM")
  await Promise.race([once(server, "close"), new Promise(resolve => setTimeout(resolve, 1_000))])
  if (server.exitCode === null) server.kill("SIGKILL")
}
