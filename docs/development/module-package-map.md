# Module, Package, Workspace, and Submodule Map

Canopy's repository is organised into eight zones. Four overlapping identity
systems are easy to confuse:

1. **MoonBit modules** under `modules/`, each with its own `moon.mod`.
2. **Packages** inside a module, defined by `moon.pkg` files.
3. **Workspace membership** declared by `moon.work`.
4. **Git submodule ownership** declared by `.gitmodules`.

Use this page to decide which manifest owns a directory, which commands cover
it, and whether edits belong in this repository or in a submodule repository.

## Zone overview

| Zone | Path | Purpose |
|------|------|---------|
| Modules | `modules/` | Reusable, publishable MoonBit modules; includes the primary `modules/canopy` (`dowdiness/canopy`) |
| Applications | `apps/` | Runnable or deployable vertical slices |
| Examples | `examples/` | Removable learning and integration examples |
| Adapters | `adapters/` | Non-MoonBit runtime and interface adapters |
| Dependencies | `deps/` | Separately owned Git submodules |
| Rules | `rules/` | Policy definitions |
| Tools | `tools/` | Local developer and verification executables |
| Scripts | `scripts/` | Repository operations and automation |

## Manifest formats

MoonBit now supports the newer `moon.mod` manifest format. The older
`moon.mod.json` format is legacy, and all tracked Canopy-owned module manifests
use `moon.mod`. Vendored submodules and dependency caches keep whatever manifest
format their owning repositories use.

Module-local dependencies use versioned imports in `moon.mod` and are resolved
through the nearest `moon.work`. The Canvas app is a nested workspace:
`apps/canvas/moon.mod` and `apps/canvas/moon.work` resolve its local
members independently of the root `moon.work`.

`moon.pkg` files are package manifests. They do not define module boundaries;
they define compilation units inside the nearest enclosing module manifest.

## Inventory sources

Do not copy exhaustive package, workspace, or submodule lists into
documentation. Read each identity from its authoritative manifest:

- **Primary-module ownership:** the nearest enclosing `moon.mod` or
  `moon.mod.json`, plus `moon.pkg` or `moon.pkg.json` for each compilation unit.
- **Root-workspace membership:** the root `moon.work`, which defines the modules
  covered by repository-root workspace commands.
- **Repository ownership:** `.gitmodules` and the nearest Git root. A submodule
  can also be a root workspace member; overlap is expected because these answer
  different questions.

Use `moon ide outline <path>` when exploring a package's public interface.
Nested workspaces such as `apps/canvas/moon.work` are intentionally separate
from the root workspace; read their own manifests when working in those
directories.

## Primary `dowdiness/canopy` module

The primary module manifest is at `modules/canopy/moon.mod`. A tracked package
belongs to it when the nearest enclosing module manifest names
`dowdiness/canopy`. Package directories live under `modules/canopy/`
(e.g. `modules/canopy/core/`, `modules/canopy/editor/`,
`modules/canopy/protocol/`).

Inspect the package manifests under `modules/canopy/` for the complete current
package list.
A root package may live more than one directory deep; for example
`modules/canopy/lang/lambda/companion/` imports as
`dowdiness/canopy/lang/lambda/companion`.

Keep ordinary tests and specifications that compile with a production package
under that package. Executable verification harnesses that import production
packages and require third-party toolchains live under
`tools/verification/<owner>/` instead. Give such a harness its own `moon.mod`,
restrict `supported_targets` when it uses target-specific APIs, and link it from
the owning package README. Root workspace membership may provide local module
resolution; it does not authorize CI to run the external verification toolchain.
`tools/verification/sync_session/` is the reference layout. This differs from
`examples/`, whose contents remain removable.

## Canopy-owned reusable modules

Canopy-owned reusable modules live under `modules/` alongside the primary
module. Each has its own `moon.mod` and independent publication ownership.
Representative members include `modules/btree/`, `modules/zipper/`,
`modules/semantic/`, `modules/analysis/`, and `modules/cognition/`.

Read `moon.work` for the complete current member list and each member's module
manifest for its canonical module name.

## Canopy-owned manifest migration status

All tracked Canopy-owned module manifests use `moon.mod`. Canvas is the
nested-workspace case: its `moon.mod` works with the local members in
`apps/canvas/moon.work`, while the primary module uses
`modules/canopy/moon.mod` and root `moon.work`. Vendored submodules and
dependency-cache artifacts retain the manifest formats owned by their
respective projects.

## Git submodules

`.gitmodules` is authoritative for submodule membership. All submodules live
under `deps/`. These directories are separate repositories; edit and commit them
inside their own repo first, push the submodule commit, then update the parent
pointer in Canopy.

For the current submodule list, use the source file or generated git output
rather than a copied table:

```sh
cat .gitmodules
git submodule status --recursive
```

Submodule manifests are not Canopy-owned for manifest migrations. Do not convert
or edit them from the parent repository unless you are intentionally making a
submodule change in that submodule's own workflow.

## Applications

Apps under `apps/` are runnable or deployable vertical slices. Some have their
own MoonBit module and workspace:

- `apps/canvas/` owns a nested workspace (`apps/canvas/moon.mod` and
  `apps/canvas/moon.work`). Run its checks and tests from that directory or
  with `moon -C apps/canvas ...`.
- `apps/ideal/`, `apps/block-editor/`, and `apps/loomark/` have their own
  `moon.mod` and are listed in the root `moon.work`. Loomark's executable
  package is `apps/loomark/main`; Warren serves it with `warren dev --direct`
  and assembles ignored static output with `warren build`. Within Loomark,
  `app/` owns the Rabbita Model, Msg, update, and view;
  `app/internal/source_repository/` owns authoritative Source persistence and
  the derived in-memory Catalog; and `main/` mounts the application.
- `apps/web/` and `apps/relay-server/` are TypeScript/Worker projects, not
  MoonBit modules.

## Examples

Examples under `examples/` fall into two broad groups:

- **MoonBit workspace example modules**: declared by the root `moon.work` and
  their nearest MoonBit manifests.
- **Frontend/TypeScript/browser examples**: declared by their local package and
  build configuration, with CI coverage defined in `.github/workflows/ci.yml`.

See [`examples/README.md`](../../examples/README.md) for the two workflow
categories and their generic commands.

## Experimental and compatibility surfaces

Some areas are intentionally more experimental or compatibility-oriented than
the core editor packages:

- `modules/canopy/codex/`, `modules/canopy/llm/`, `modules/canopy/echo/`, and
  `modules/canopy/relay/` are integration/tooling surfaces rather than core
  editor data structures.
- `modules/canopy/workspace/probe/` contains probe and regression packages for
  workspace-level behavior.
- `examples/*` are allowed to be more application-shaped than reusable library
  modules.
- `deps/rabbita/` is vendored as a submodule fork; treat its docs and
  conventions as authoritative for rabbita work.

When in doubt, prefer the owning module's manifest and `moon.pkg` imports over
repository layout guesses.

## Command forms

Workspace-root commands (run from the repository root) follow `moon.work`:

```sh
moon test          # all root-workspace members
moon check         # all root-workspace members
moon fmt           # all root-workspace members
```

Module-local commands target a specific module:

```sh
moon -C modules/canopy test      # primary module only
moon -C modules/canopy check     # primary module only
moon -C apps/canvas check        # Canvas nested workspace
```
