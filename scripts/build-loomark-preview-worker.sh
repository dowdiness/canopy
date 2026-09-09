#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname "$0")/.." && pwd)"
export MOON_HOME="${MOON_HOME:-/tmp/loomark-toolchain-aug19}"
export PATH="$MOON_HOME/bin:$PATH"
export NEW_MOON_MOD=0
WARREN="${WARREN:-$ROOT/../canopy-loomark-demand-preview/_build/tools/bin/warren}"
# Experiment only. Never invoke a shared toolchain installer or alter pins.
cd "$ROOT/apps/loomark"
npm ci
npm run build:styles
"$WARREN" build --public-dir "$PWD/public"
moon run --build-only --target js --release worker
# Minified with Warren terser options (-c/-m toplevel=true); version pinned to existing 5.51.2, no property mangling.
npm exec --yes --package=terser@5.51.2 -- terser "$ROOT/_build/js/release/build/dowdiness/loomark/worker/worker.js" -c toplevel=true -m toplevel=true -o "$PWD/dist/preview-worker.js"
node - "$PWD/dist/preview-worker.js" "$PWD/dist/index.html" <<'NODE'
const { readFileSync, writeFileSync } = require("node:fs")
const { createHash } = require("node:crypto")
const [workerPath, htmlPath] = process.argv.slice(2)
const code = readFileSync(workerPath, "utf8")
const version = createHash("sha256").update(code).digest("hex")
const payload = JSON.stringify({ version, code }).replaceAll("<", "\\u003c")
const html = readFileSync(htmlPath, "utf8")
const marker = /\s*<script type="application\/json" id="loomark-preview-worker-payload">[\s\S]*?<\/script>/g
if (html.match(marker)?.length > 1) throw new Error("duplicate Preview Worker payload")
const without = html.replace(marker, "")
const insertion = `\n    <script type="application/json" id="loomark-preview-worker-payload">${payload}</script>`
// A replacement string would interpret minified identifiers containing $$.
const result = without.replace("</head>", () => `${insertion}\n  </head>`)
if (!result.includes(insertion)) throw new Error("Preview Worker payload was not inserted verbatim")
writeFileSync(htmlPath, result)
NODE
test -s dist/styles.css
test -s dist/preview-worker.js
grep -q 'id="loomark-preview-worker-payload"' dist/index.html

if [[ "${1:-}" == "--fixture" ]]; then
  moon run --build-only --target js --release fixture
  FIXTURE_DIST="$ROOT/_build/loomark-worker-fixture"
  mkdir -p "$FIXTURE_DIST"
  cp "$ROOT/_build/js/release/build/dowdiness/loomark/fixture/fixture.js" "$FIXTURE_DIST/fixture.js"
  cp dist/styles.css "$FIXTURE_DIST/styles.css"
  node - "$PWD/dist/index.html" "$FIXTURE_DIST/index.html" <<'NODE'
const { readFileSync, writeFileSync } = require("node:fs")
const [productionHtmlPath, fixtureHtmlPath] = process.argv.slice(2)
const productionHtml = readFileSync(productionHtmlPath, "utf8")
const payload = productionHtml.match(/<script type="application\/json" id="loomark-preview-worker-payload">[\s\S]*?<\/script>/)?.[0]
if (!payload) throw new Error("production Preview Worker payload missing")
writeFileSync(fixtureHtmlPath, `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="./styles.css"></head><body><main id="fixture"></main>${payload}<script type="module" src="./fixture.js"></script></body></html>\n`)
NODE
  test -s "$FIXTURE_DIST/fixture.js"
  grep -q 'id="loomark-preview-worker-payload"' "$FIXTURE_DIST/index.html"
  sha256sum "$FIXTURE_DIST/fixture.js"
fi

sha256sum dist/index.js dist/preview-worker.js
