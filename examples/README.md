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
| `examples/codemirror/` | CodeMirror binding demo module. | `scripts/run-moon-module.sh ci examples/codemirror`; browser wrapper is in the same directory. |
| `examples/resizable/` | Rabbita resizable example module. | Covered by root workspace commands. |
| `examples/disclosure/` | Rabbita disclosure example module. | Covered by root workspace commands. |

Run a single MoonBit example directly with:

```sh
cd examples/<name>
moon check
moon test
```

## Frontend / TypeScript / browser examples

These examples use npm tooling. Build the MoonBit JavaScript artifacts first
from the repository root when they import Canopy-generated output:

```sh
moon build --target js
```

| Frontend | Tooling | Notes |
| --- | --- | --- |
| `examples/demo-react/` | React/Vite + TypeScript + Vitest + Playwright | React integration demo plus local WebSocket helpers. |
| `examples/prosemirror/` | Vite + TypeScript | ProseMirror integration example. |

Typical frontend workflow:

```sh
cd examples/demo-react
npm ci
npm run dev
```

CI is the source of truth for the exact frontend fan-out and pinned Playwright
container versions. See `.github/workflows/ci.yml` for the current matrices.

## Relationship to module/package map

For the repository-level distinction between primary packages, reusable
`modules/*`, product `apps/*`, integration `examples/*`, and repository
dependencies under `deps/*`, see
[`docs/development/module-package-map.md`](../docs/development/module-package-map.md).
