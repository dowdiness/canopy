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
`moon.mod.json` format is legacy. This repository is migrating Canopy-owned
module manifests to `moon.mod` where the newer format can preserve the same
dependency semantics; submodules keep whatever manifest format their own
repository currently uses.

Current exception: the newer `moon.mod` format expects registry-style imports
and local-module resolution through `moon.work`, while several Canopy-owned
modules still rely on legacy `moon.mod.json` path dependencies to submodules or
other in-repo modules that are not workspace members. Those manifests stay on
`moon.mod.json` until a later workspace/path-dependency migration can preserve
behavior without changing workspace topology.

`moon.pkg` files are package manifests. They do not define module boundaries;
they define compilation units inside the nearest enclosing module manifest.

## What `moon.work` means

`moon.work` lists **workspace member modules**, not every package in the repo.
A command such as `moon check` or `moon test` from the repository root runs over
those workspace members. It does not automatically include every example,
submodule, generated build directory, or vendored dependency cache.

Read `moon.work` for the authoritative list before adding or removing a member.
For a generated view rather than a hand-maintained copy, run:

```sh
moon work list 2>/dev/null || sed -n '/members = \[/,/\]/p' moon.work
```

The SessionStart package overview (`scripts/package-overview.sh`) also reports
workspace members from the current `moon.work` file.

## Root `dowdiness/canopy` packages

The root module is the `.` workspace member. Any directory under the repository
root with a `moon.pkg` and no intervening `moon.mod`/`moon.mod.json` is a package
whose import path starts with `dowdiness/canopy`.

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
| `js_ffi/` | `dowdiness/canopy/js_ffi` | Root-module JavaScript/FFI substrate, despite living under `lib/`. |
| `codex/`, `llm/`, `echo/`, `relay/`, `cmd/main/` | `dowdiness/canopy/...` | Tooling, experiments, relay, and executable packages. |

A root package may live more than one directory deep. For example
`lang/lambda/companion/` imports as `dowdiness/canopy/lang/lambda/companion`.

## Standalone `lib/*` modules

Most Canopy-owned directories under `lib/` are standalone MoonBit modules with
their own module manifest and one or more packages. They are workspace members
when listed in `moon.work`, and their import paths come from their own module
name rather than from `dowdiness/canopy/lib/...`.

| Directory | Module | Notes |
| --- | --- | --- |
| `lib/analysis/` | `dowdiness/analysis` | Snapshot-bound analysis facts and UTF-16 conversion primitives. |
| `lib/btree/` | `dowdiness/btree` | In-tree B-tree support module. |
| `lib/byte-codec/` | `dowdiness/byte_codec` | Byte encoding/decoding utilities. |
| `lib/canvas-graph/` | `dowdiness/canopy-canvas-graph` | Canvas graph model packages. |
| `lib/cognition/` | `dowdiness/cognition` | Incremental cognition graph runtime; already uses `moon.mod`. |
| `lib/context-menu/` | `dowdiness/rabbita-context-menu` | Rabbita context-menu package under `context_menu/`. |
| `lib/dom-boundary/` | `dowdiness/dom_boundary` | DOM boundary helpers. |
| `lib/menu/` | `dowdiness/rabbita-menu` | Rabbita menu package under `menu/`. |
| `lib/rabbita_codemirror/` | `dowdiness/rabbita_codemirror` | CodeMirror binding packages. |
| `lib/resizable/` | `dowdiness/rabbita-resizable` | Rabbita resizable package under `resizable/`. |
| `lib/semantic/` | `dowdiness/semantic` | Semantic graph/query packages; has standalone proof module under `proof/`. |
| `lib/status/` | `dowdiness/rabbita-status` | Rabbita status package under `status/`. |
| `lib/tabs/` | `dowdiness/rabbita-tabs` | Rabbita tabs package under `tabs/`. |
| `lib/treeview/` | `dowdiness/rabbita-treeview` | Rabbita treeview package under `treeview/`. |
| `lib/visualizer/` | `dowdiness/visualizer` | Visualization helpers. |
| `lib/zipper/` | `dowdiness/zipper` | AST zipper utilities. |

`lib/text-change/` is intentionally documented here even though it is not
currently a tracked Canopy-owned workspace member. Do **not** delete it or treat
that path as stale without a later, separate audit proving it is dead. The active
text-change dependency for the root module currently resolves through the loom
submodule path dependency `./loom/text-change`.

## Canopy-owned manifest migration status

Converted to the newer `moon.mod` format:

- `lib/analysis/`
- `lib/btree/`
- `lib/byte-codec/`
- `lib/canvas-graph/`
- `lib/cognition/` (already newer format)
- `lib/context-menu/` (workspace-resolved dep on `rabbita/rabbita` and
  `dowdiness/rabbita-menu`)
- `lib/dom-boundary/`
- `lib/menu/` (workspace-resolved dep on `rabbita/rabbita`)
- `lib/rabbita_codemirror/` (workspace-resolved dep on `rabbita/rabbita`)
- `lib/resizable/` (workspace-resolved dep on `rabbita/rabbita`)
- `lib/semantic/proof/`
- `lib/status/` (workspace-resolved dep on `rabbita/rabbita`)
- `lib/tabs/` (workspace-resolved dep on `rabbita/rabbita`)
- `lib/treeview/` (workspace-resolved dep on `rabbita/rabbita`)
- `lib/zipper/`
- `examples/disclosure/` (workspace-resolved dep on `rabbita/rabbita`)

Still on legacy `moon.mod.json` because they contain local path dependencies
whose behavior cannot be represented in `moon.mod` without changing workspace
membership or relying on unpublished registry modules:

- the root module (`moon.mod.json`)
- MoonBit examples: `examples/block-editor/`, `examples/canvas/`,
  `examples/codemirror_demo/`, `examples/ideal/`,
  `examples/resizable/`
- `lib/semantic/`, `lib/visualizer/`

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

- **MoonBit workspace example modules**: listed in `moon.work`, checked by root
  workspace commands, and CI's MoonBit example matrix.
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
