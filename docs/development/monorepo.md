# Monorepo & Git Submodule Guide

Canopy combines a primary MoonBit module, in-tree workspace modules, nested
workspaces, and independent libraries recorded as Git submodules. The primary
module (`dowdiness/canopy`) declares versioned imports in `moon.mod`; its nearest
`moon.work` resolves local members.

## Layout

```
canopy/                          dowdiness/canopy (root MoonBit module)
├── core/  editor/  protocol/    monorepo packages (see docs/architecture.md)
├── projection/  relay/  ffi/
├── lang/{lambda,json,markdown}/
├── llm/  echo/  cmd/main/       monorepo packages
├── modules/btree/               workspace member, in-tree library
├── modules/zipper/              workspace member, in-tree library
├── modules/semantic/                workspace member, in-tree library
├── adapters/editor/             in-tree TypeScript adapter package
├── examples/                    in-tree example apps (web, ideal, …)
│   └── canvas/                  standalone MoonBit module with nested workspace
│
└── <Git submodules>/           independent repositories; see .gitmodules
```

## Live topology

Do not copy the workspace-member or submodule inventory into documentation.
Generate the current repository views from their authoritative manifests:

```sh
./scripts/package-overview.sh
```

The output distinguishes:

- packages owned by the primary `dowdiness/canopy` module,
- modules covered by repository-root workspace commands,
- repositories owned through `.gitmodules`.

The last two sets may overlap: a Git submodule can also be a root-workspace
member. Root `moon test`, `moon check`, and `moon fmt` follow `moon.work`, not
repository ownership.

Canvas is intentionally outside the root workspace. Its standalone module and
local dependency modules are listed in `examples/canvas/moon.work`; run Canvas
commands from `examples/canvas` (or use `scripts/run-moon-module.sh`) so that
the nested workspace is selected.

## Module and workspace resolution

Each module declares its versioned imports in `moon.mod`. The nearest
`moon.work` resolves imports to local workspace members, so the root module's
authoritative pair is the root `moon.mod` and `moon.work`. Canvas is intentionally
isolated: `examples/canvas/moon.mod` and `examples/canvas/moon.work` form its
nested module/workspace pair. Vendored submodules retain their own manifests and
workspace boundaries.

## Setup

```sh
git clone --recursive https://github.com/dowdiness/canopy.git
```

If the clone already exists without submodules:

```sh
git submodule update --init --recursive
```

## Daily workflow

### Working on a monorepo package

No submodule awareness required:

```sh
moon check
moon test
```

### Working on the Canvas module

Canvas has its own nested workspace and should be checked from its module root:

```sh
cd examples/canvas
NEW_MOON_MOD=0 moon check main --target js
NEW_MOON_MOD=0 moon test main --target js --release
```

### Editing a submodule

Each submodule is its own repository. Changes inside a submodule are committed
to *that* repo; the parent repo records the new submodule commit hash. You
always make two commits.

```sh
cd event-graph-walker
git checkout main                  # avoid editing on detached HEAD
# … edit, moon check, moon test …
git add -A
git commit -m "feat: …"
git push origin main               # always via PR if the submodule has one

cd ..
git add event-graph-walker          # records the new commit pointer
git commit -m "chore: update event-graph-walker submodule"
```

Always push the submodule's commit to its remote **before** pushing the parent
or opening a parent PR. CI clones with `submodules: recursive`, so a parent
commit referencing a submodule SHA that is not yet on `origin` will fail.

### Pulling

```sh
git pull
git submodule update --init --recursive
```

To pull the latest submodule tips even when the parent has not advanced its
pointers:

```sh
git submodule update --remote
```

### Running tests across the tree

Workspace root:

```sh
moon test
```

For isolated submodule debugging, enter the owning module root and run its
repository-specific test command. Derive the current ownership paths from
`.gitmodules` and workspace membership from `moon.work`; do not maintain a
copied submodule command list here.

Proof modules:

```sh
cd modules/semantic/proof && moon prove   # needs Why3 + z3
```

The canonical CI fan-out is in `.github/workflows/ci.yml`.

## Submodule reference

The root [`.gitmodules`](../../.gitmodules) is authoritative for submodule
membership, paths, and URLs, and `git submodule status --recursive` shows the
live pins and working-tree state. Do not copy the inventory into this guide.

## Why submodules

1. **Reusability** — `event-graph-walker`, `loom`, and `rle` are usable from
   other MoonBit projects without pulling in the editor.
2. **Independent versioning** — each library releases on its own cadence.
3. **Focused testing** — each library owns its CI and benchmarks.
4. **Clear ownership boundaries** — debt routing (below) is enforced by the
   physical repository layout.

## Common pitfalls

- **Detached HEAD inside a submodule.** `git submodule update` checks out a
  specific commit. Run `git checkout main` (or a feature branch) before
  editing.
- **Forgetting the second commit.** Pushing the submodule but not the parent
  pointer leaves collaborators seeing the old version.
- **Stale submodule after `git pull`.** If `moon check` fails with missing
  packages, run `git submodule update --init --recursive`.
- **`git status` from the root only shows pointer changes.** Use
  `cd <submodule> && git status` to see file-level changes.

## Debt routing

When a problem appears in a root package, do not assume the fix belongs there.

- Missing text-edit primitives belong in `event-graph-walker/`.
- Parser or edit-semantics belong in `loom/`.
- Pretty-printer changes belong in `loom/pretty/`.
- Run-length encoding belongs in `rle/`.
- Root-module helpers exist only when multiple root packages need them.
- Submodules never grow upward dependencies on the root.

See [Paying Technical Debt](technical-debt.md) for the full strategy.
