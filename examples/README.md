# Examples

Canopy examples are not all built the same way. Some are MoonBit workspace
modules; others are browser/TypeScript projects that consume generated MoonBit
JavaScript artifacts.

## MoonBit workspace example modules

MoonBit examples have their own module manifests. Root commands cover only the
members declared by [`../moon.work`](../moon.work); read the nearest `moon.mod`
and `moon.pkg` for module and package dependencies.

Run a single MoonBit example directly with:

```sh
cd examples/NAME
moon check
moon test
```

## Frontend / TypeScript / browser examples

These examples use npm tooling. Build the MoonBit JavaScript artifacts first
from the repository root when they import Canopy-generated output:

```sh
moon build --target js
```

Typical frontend workflow:

```sh
cd examples/NAME
npm ci
npm run dev
```

CI is the source of truth for the exact frontend fan-out and pinned browser
test environment. See
[`../.github/workflows/ci.yml`](../.github/workflows/ci.yml) for the current
matrices.

## Relationship to module/package map

For the repository-level distinction between primary packages, reusable
`modules/*`, product `apps/*`, integration `examples/*`, and repository
dependencies under `deps/*`, see
[`docs/development/module-package-map.md`](../docs/development/module-package-map.md).
