# Monorepo & Git Submodule Guide

Canopy combines a primary MoonBit module at `modules/canopy/`, in-tree reusable
modules under `modules/`, nested workspaces, and independent libraries recorded
as Git submodules under `deps/`. The primary module (`dowdiness/canopy`)
declares versioned imports in `modules/canopy/moon.mod`; the root `moon.work`
resolves local members.

## Layout

```
canopy/
├── modules/
│   ├── canopy/                   dowdiness/canopy (primary MoonBit module)
│   │   ├── core/  editor/  protocol/  projection/
│   │   ├── lang/{lambda,json,markdown}/
│   │   ├── ffi/  relay/  llm/  echo/  cmd/main/
│   │   └── ...                     see package-overview.sh
│   ├── btree/  zipper/  semantic/   reusable Canopy-owned modules
│   ├── analysis/  cognition/  js-ffi/  dom-boundary/  ...
│   └── rabbita_codemirror/  rabbita-menu/  ...
├── apps/
│   ├── web/                      Waku Worker web demo (TypeScript)
│   ├── ideal/                    MoonBit module + browser E2E
│   ├── canvas/                   nested workspace (moon.mod + moon.work)
│   ├── block-editor/             MoonBit module
│   ├── loomark/                  MoonBit module
│   └── relay-server/             Cloudflare Workers relay (TypeScript)
├── examples/                     removable learning/integration examples
│   ├── codemirror/  resizable/  disclosure/   MoonBit workspace members
│   └── prosemirror/  demo-react/              TypeScript/browser
├── adapters/
│   └── editor/                   TypeScript adapter package
├── deps/                         Git submodules (separate repositories)
│   ├── event-graph-walker/  loom/  rabbita/
│   ├── svg-dsl/  graphviz/  order-tree/  alga/
│   └── ...                     see .gitmodules
├── rules/                        policy definitions
├── scripts/                      operations and tooling
├── moon.work                     root workspace membership
└── .gitmodules                   submodule ownership
```

## Live topology

Do not copy the workspace-member or submodule inventory into documentation.
Generate the current repository views from their authoritative manifests:

```sh
./scripts/package-overview.sh
```

The output distinguishes:

- packages owned by the primary `dowdiness/canopy` module (at `modules/canopy/`),
- modules covered by repository-root workspace commands,
- repositories owned through `.gitmodules` (under `deps/`).

The last two sets may overlap: a Git submodule under `deps/` can also be a
root-workspace member. Root `moon test`, `moon check`, and `moon fmt` follow
`moon.work`, not repository ownership.

Canvas is intentionally outside the root workspace. Its standalone module and
local dependency modules are listed in `apps/canvas/moon.work`; run Canvas
commands with `moon -C apps/canvas ...` so that the nested workspace is
selected.

## Module and workspace resolution

Each module declares its versioned imports in `moon.mod`. The nearest
`moon.work` resolves imports to local workspace members, so the primary module's
authoritative pair is `modules/canopy/moon.mod` and root `moon.work`. Canvas is
intentionally isolated: `apps/canvas/moon.mod` and `apps/canvas/moon.work`
form its nested module/workspace pair. Vendored submodules under `deps/` retain
their own manifests and workspace boundaries.

## Setup

```sh
git clone --recursive https://github.com/dowdiness/canopy.git
```

If the clone already exists without submodules:

```sh
git submodule update --init --recursive
```

## Daily workflow

### Working on the primary module

The primary module lives at `modules/canopy/`. Workspace-root commands cover it
along with all other root-workspace members:

```sh
moon check
moon test
```

To target only the primary module:

```sh
moon -C modules/canopy check
moon -C modules/canopy test
```

### Working on a reusable module

Other `modules/*` members (btree, zipper, semantic, etc.) are also covered by
root workspace commands. To target a specific module:

```sh
moon -C modules/btree test
moon -C modules/semantic check
```

### Working on the Canvas module

Canvas has its own nested workspace and should be checked from its module root:

```sh
moon -C apps/canvas check --target js
moon -C apps/canvas test --target js --release
```

### Editing a submodule

Each submodule under `deps/` is its own repository. Changes inside a submodule
are committed to *that* repo; the parent repo records the new submodule commit
hash. You always make two commits.

```sh
cd deps/event-graph-walker
git checkout main                  # avoid editing on detached HEAD
# … edit, moon check, moon test …
git add -A
git commit -m "feat: …"
git push origin main               # always via PR if the submodule has one

cd ../..
git add deps/event-graph-walker     # records the new commit pointer
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

1. **Reusability** — `deps/event-graph-walker`, `deps/loom`, and similar
   libraries are usable from other MoonBit projects without pulling in the
   editor.
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
  `cd deps/<name> && git status` to see file-level changes.

## Debt routing

When a problem appears in a primary-module package, do not assume the fix
belongs there.

- Missing text-edit primitives belong in `deps/event-graph-walker/`.
- Parser or edit-semantics belong in `deps/loom/`.
- Pretty-printer changes belong in `deps/loom/pretty/`.
- Primary-module helpers exist only when multiple primary packages need them.
- Submodules under `deps/` never grow upward dependencies on the primary
  module.

See [Paying Technical Debt](technical-debt.md) for the full strategy.
