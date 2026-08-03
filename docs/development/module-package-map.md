# Module, Package, Workspace, and Submodule Map

Canopy's repository is organised into seven zones. Four overlapping identity
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
| Scripts | `scripts/` | Operations and tooling |

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
`dowdiness/canopy`, which lives at `modules/canopy/moon.mod`. It fails when
that name is missing or ambiguous.

Nested workspaces such as `apps/canvas/moon.work` are intentionally outside
the root-workspace section. Read their own manifest and workspace file when
working in those directories.

## Primary `dowdiness/canopy` module

The primary module manifest is at `modules/canopy/moon.mod`. A tracked package
belongs to it when the nearest enclosing module manifest names
`dowdiness/canopy`. Package directories live under `modules/canopy/`
(e.g. `modules/canopy/core/`, `modules/canopy/editor/`,
`modules/canopy/protocol/`).

Use `./scripts/package-overview.sh` for the complete current package list.
A root package may live more than one directory deep; for example
`modules/canopy/lang/lambda/companion/` imports as
`dowdiness/canopy/lang/lambda/companion`.

## Canopy-owned reusable modules

Canopy-owned reusable modules live under `modules/` alongside the primary
module. Each has its own `moon.mod` and independent publication ownership.
Representative members include `modules/btree/`, `modules/zipper/`,
`modules/semantic/`, `modules/analysis/`, and `modules/cognition/`.

Use `./scripts/package-overview.sh` for the complete current member list and
read each listed module manifest for its canonical module name.

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
  `moon.mod` and are listed in the root `moon.work`.
- `apps/web/` and `apps/relay-server/` are TypeScript/Worker projects, not
  MoonBit modules.

## Examples

Examples under `examples/` fall into two broad groups:

- **MoonBit workspace example modules**: listed in the root `moon.work`, checked
  by root workspace commands, and covered by CI's MoonBit example matrix.
  Examples include `examples/codemirror/`, `examples/resizable/`, and
  `examples/disclosure/`.
- **Frontend/TypeScript/browser examples**: npm/Vite/Playwright projects that
  require built MoonBit JS artifacts before TypeScript typechecks or browser
  tests run. Examples include `examples/prosemirror/` and
  `examples/demo-react/`.

See [`examples/README.md`](../../examples/README.md) for the example-by-example
classification and commands.

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
