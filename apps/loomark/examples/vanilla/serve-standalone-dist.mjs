import { createReadStream, existsSync, statSync } from "node:fs"
import { createServer } from "node:http"
import { extname, join, normalize } from "node:path"
import { fileURLToPath } from "node:url"

const distRoot = process.env.LOOMARK_STANDALONE_DIST ??
  fileURLToPath(new URL("../../dist/", import.meta.url))
const r0FixtureRoot = process.env.LOOMARK_R0_BROWSER_FIXTURE_ROOT
const r0FixturePrefix = "/fixtures/r0-browser-v1/"
const port = Number.parseInt(process.env.LOOMARK_STANDALONE_PORT ?? "4317", 10)
const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".map", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
])

const server = createServer((request, response) => {
  const pathname = new URL(request.url ?? "/", `http://127.0.0.1:${port}`).pathname
  const fixtureRequest = r0FixtureRoot !== undefined && pathname.startsWith(r0FixturePrefix)
  const relativePath = fixtureRequest
    ? pathname.slice(r0FixturePrefix.length)
    : pathname === "/" ? "index.html" : pathname.slice(1)
  const normalizedPath = normalize(relativePath)
  const filePath = join(fixtureRequest ? r0FixtureRoot : distRoot, normalizedPath)

  if (
    normalizedPath.startsWith("..") ||
    !existsSync(filePath) ||
    !statSync(filePath).isFile()
  ) {
    response.writeHead(404, { "content-type": "text/plain; charset=utf-8" })
    response.end("Not found")
    return
  }

  response.writeHead(200, {
    "cache-control": "no-store",
    "content-type": contentTypes.get(extname(filePath)) ?? "application/octet-stream",
  })
  createReadStream(filePath).pipe(response)
}).listen(port, "127.0.0.1", () => {
  process.stdout.write(`Loomark standalone output at http://127.0.0.1:${port}\n`)
})

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)))
}
