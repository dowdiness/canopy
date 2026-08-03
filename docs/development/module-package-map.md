# Module, Package, Workspace, and Submodule Map

Canopy has four overlapping shapes that are easy to confuse:

1. **MoonBit packages inside the root module** (`dowdiness/canopy`).
2. **Standalone workspace modules** listed by `moon.work`.
3. **Git submodules** that are separate repositories.
4. **Examples**, split between MoonBit modules and TypeScript/browser apps.

Use this page to decide which manifest owns a directory, which commands cover
it, and whether edits belong in this repository or in a submodule repository.

## Manifest formats

MoonBit now supports the newer `moon.mod` manifest format. The older
`moon.mod.json` format is legacy, and all tracked Canopy-owned module manifests
use `moon.mod`. Vendored submodules and dependency caches keep whatever manifest
format their owning repositories use.

Module-local dependencies use versioned imports in `moon.mod` and are resolved
through the nearest `moon.work`. The Canvas example is a nested workspace:
`examples/canvas/moon.mod` and `examples/canvas/moon.work` resolve its local
members independently of the root `moon.work`.

`moon.pkg` files are package manifests. They do not define module boundaries;
they define compilation units inside the nearest enclosing module manifest.

## Live inventory

Run the repository inventory instead of copying package, workspace, or
submodule lists into documentation:

```sh
./scripts/package-overview.sh
```

The command derives three independent views:

- **Primary-module ownership** from tracked `moon.mod`/`moon.mod.json` and
  `moon.pkg`/`moon.pkg.json` files. Each package belongs to its nearest module
  manifest.
- **Root-workspace membership** from the root `moon.work`. This is the set
  covered by repository-root workspace commands.
- **Repository ownership** from `.gitmodules`. A submodule can also be a root
  workspace member; overlap is expected because the two lists answer different
  questions.

The script locates the primary module by its unique name,
`dowdiness/canopy`, rather than assuming that its manifest remains at the
repository root. It fails when that name is missing or ambiguous.

Nested workspaces such as `examples/canvas/moon.work` are intentionally outside
the root-workspace section. Read their own manifest and workspace file when
working in those directories.

## Primary `dowdiness/canopy` packages

At present the primary module manifest is at the repository root. A tracked
package belongs to it when the nearest enclosing module manifest names
`dowdiness/canopy`.

Important root-module package groups include:

| Directory | Import-path shape | Role |
| --- | --- | --- |
| `core/` | `dowdiness/canopy/core` | Language-agnostic projection primitives. |
| `editor/` | `dowdiness/canopy/editor` | Generic editor facade and sync integration. |
| `projection/` | `dowdiness/canopy/projection` | Interactive projection/tree UI state. |
| `protocol/`, `protocol/wire/` | `dowdiness/canopy/protocol[/wire]` | User-intent and wire protocol types. |
| `lang/{json,lambda,markdown}/...` | `dowdiness/canopy/lang/...` | Language-specific projection, edit, companion, and semantic packages. |
| `ffi/{host,io,json,lambda,markdown}/` | `dowdiness/canopy/ffi/...` | JS/host-facing FFI surfaces. |
| `transport_ws/`, `sync_session/`, `ephemeral/` | `dowdiness/canopy/...` | Collaboration transport/session and ephemeral state. |
| `workspace/{coordinator,probe}/` | `dowdiness/canopy/workspace/...` | Multi-editor workspace coordination and probes. |
| `analysis_bridge/` | `dowdiness/canopy/analysis_bridge` | Bridge from analysis facts to Canopy decorations and match lists. |
| `codex/`, `llm/`, `echo/`, `relay/`, `cmd/main/` | `dowdiness/canopy/...` | Tooling, experiments, relay, and executable packages. |

A root package may live more than one directory deep. For example
`lang/lambda/companion/` imports as `dowdiness/canopy/lang/lambda/companion`.

## Standalone modules

Canopy-owned standalone modules currently live mainly under `lib/`; examples
and tools may also own module manifests. Their import paths come from their own
`moon.mod`, not from their repository directory. Representative groups:

| Directory family | Examples | Placement meaning |
| --- | --- | --- |
| `lib/` | `analysis`, `btree`, `semantic`, `zipper` | Reusable modules with independent package and publication ownership. |
| `examples/` | `ideal`, `block-editor`, `codemirror_demo` | Runnable or learning surfaces with their own module lifecycle. |
| `loomark/` | `loomark` | Product/tool module whose ownership does not fit the reusable-library or example categories. |

Use `./scripts/package-overview.sh` for the complete current member list and
read each listed module manifest for its canonical module name.

## Canopy-owned manifest migration status

All tracked Canopy-owned module manifests use `moon.mod`. Canvas is the
nested-workspace case: its `moon.mod` works with the local members in
`examples/canvas/moon.work`, while the root module uses the root `moon.mod` and
`moon.work`. Vendored submodules and dependency-cache artifacts retain the
manifest formats owned by their respective projects.

## Git submodules

`.gitmodules` is authoritative for submodule membership. These directories are
separate repositories; edit and commit them inside their own repo first, push the
submodule commit, then update the parent pointer in Canopy.

For the current submodule list, use the source file or generated git output
rather than a copied table:

```sh
cat .gitmodules
git submodule status --recursive
```

Submodule manifests are not Canopy-owned for manifest migrations. Do not convert
or edit them from the parent repository unless you are intentionally making a
submodule change in that submodule's own workflow.

## Examples

Examples fall into two broad groups:

- **MoonBit workspace example modules**: listed in the root `moon.work`, checked
  by root workspace commands, and covered by CI's MoonBit example matrix.
- **Nested-workspace MoonBit modules**: `examples/canvas/` owns its `moon.mod`
  and `moon.work`; run its checks and tests from that directory rather than
  treating it as a root workspace member.
- **Frontend/TypeScript/browser examples**: npm/Vite/Playwright projects that
  require built MoonBit JS artifacts before TypeScript typechecks or browser
  tests run.

See [`examples/README.md`](../../examples/README.md) for the example-by-example
classification and commands.

## Experimental and compatibility surfaces

Some directories are intentionally more experimental or compatibility-oriented
than the core editor packages:

- `codex/`, `llm/`, `echo/`, and `relay/` are integration/tooling surfaces rather
  than core editor data structures.
- `workspace/probe/` contains probe and regression packages for workspace-level
  behavior.
- `examples/*` are allowed to be more application-shaped than reusable library
  modules.
- `rabbita/` is vendored as a submodule fork; treat its docs and conventions as
  authoritative for rabbita work.

When in doubt, prefer the owning module's manifest and `moon.pkg` imports over
repository layout guesses.
