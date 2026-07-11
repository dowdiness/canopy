# Examples

Canopy examples are not all built the same way. Some are MoonBit workspace
modules; others are browser/TypeScript projects that consume generated MoonBit
JavaScript artifacts.

## MoonBit workspace example modules

These directories have their own MoonBit module manifest and are listed in the
root `moon.work`, so root-level `moon check` / `moon test` covers them as
workspace members:

| Example | Purpose | CI mechanism |
| --- | --- | --- |
| `ideal/` | Main Ideal editor example and MoonBit/JS bridge. | `scripts/run-moon-module.sh ci examples/ideal`; also has browser E2E under `ideal/web/`. |
| `block-editor/` | Block editor MoonBit example. | `scripts/run-moon-module.sh ci examples/block-editor`. |
| `canvas/` | Canvas graph editor MoonBit example. | `scripts/run-moon-module.sh ci examples/canvas`; also builds JS for `canvas/web/`. |
| `codemirror_demo/` | CodeMirror binding demo module. | `scripts/run-moon-module.sh ci examples/codemirror_demo`; also has a small Vite app. |
| `resizable/` | Rabbita resizable example module. | Covered by root workspace commands. |
| `disclosure/` | Rabbita disclosure example module. | Covered by root workspace commands. |

Run a single MoonBit example directly with:

```sh
cd examples/<name>
moon check
moon test
```

## Frontend / TypeScript / browser examples

These examples use npm tooling. Build the MoonBit JS artifacts first from the
repository root when they import Canopy-generated JS:

```sh
moon build --target js
```

| Example | Tooling | Notes |
| --- | --- | --- |
| `web/` | Vite + TypeScript + Playwright | Main browser demo pages for Lambda, JSON, and Markdown editors. CI runs TypeScript typecheck and Playwright. |
| `ideal/web/` | Vite + Playwright | Browser E2E suite for the Ideal editor; paired with the `examples/ideal` MoonBit module. |
| `canvas/web/` | Vite + TypeScript + Playwright | Browser UI for `examples/canvas`; CI builds canvas MoonBit JS from `examples/canvas` before typecheck/E2E. |
| `demo-react/` | React/Vite + TypeScript + Vitest + Playwright | React demo plus local WebSocket server helpers. |
| `prosemirror/` | Vite + TypeScript | ProseMirror integration example; CI typechecks it. |
| `codemirror_demo/` | Vite | Browser wrapper around the MoonBit CodeMirror demo module. |
| `relay-server/` | Wrangler | Cloudflare Worker relay-server example. |
| `rabbita/` | npm / vendored rabbita tooling | Rabbita-specific example area; check local package scripts and rabbita docs. |

Typical frontend workflow:

```sh
cd examples/web
npm ci
npm run dev
```

CI is the source of truth for the exact frontend fan-out and pinned Playwright
container versions. See `.github/workflows/ci.yml` for the current matrices.

## Relationship to module/package map

For the repository-level distinction between root packages, standalone
`lib/*` modules, examples, and git submodules, see
[`docs/development/module-package-map.md`](../docs/development/module-package-map.md).
