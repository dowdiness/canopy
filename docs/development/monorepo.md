# Monorepo & Git Submodule Guide

This project was restructured from a single `til` repository into a monorepo with git submodules. This guide explains the setup, daily workflows, and common pitfalls.

## Background

Previously, all code lived in a single `dowdiness/til` repository. The restructuring extracted reusable libraries into independent repositories and links them back via git submodules:

```
crdt/                           ← monorepo (dowdiness/crdt)
├── event-graph-walker/         ← submodule (dowdiness/event-graph-walker)
├── loom/                       ← submodule (dowdiness/loom)
├── svg-dsl/                    ← submodule (dowdiness/svg-dsl)
├── graphviz/                   ← submodule (dowdiness/graphviz)
├── valtio/                     ← submodule (dowdiness/valtio)
├── editor/                     ← monorepo package
├── projection/                 ← monorepo package
├── cmd/                        ← monorepo package
├── examples/web/               ← monorepo (web frontend)
└── examples/demo-react/        ← monorepo (React demo)
```

The root MoonBit module (`dowdiness/crdt`) depends on submodules via path dependencies in `moon.mod.json`:

```json
{
  "deps": {
    "dowdiness/event-graph-walker": { "path": "./event-graph-walker" },
    "dowdiness/lambda": { "path": "./loom/examples/lambda" },
    "dowdiness/loom": { "path": "./loom/loom" }
  }
}
```

## Initial Setup

Clone with `--recursive` to fetch all submodules:

```bash
git clone --recursive https://github.com/dowdiness/crdt.git
```

If you already cloned without `--recursive`:

```bash
git submodule update --init --recursive
```

## Daily Cheat Sheet

### Edit a submodule

```bash
cd event-graph-walker
git checkout main            # or your feature branch

# make changes
moon check
moon test

git add -A
git commit -m "feat: ..."
git push origin main

cd ..
git add event-graph-walker
git commit -m "chore: update event-graph-walker submodule"
```

### Sync after pulling the monorepo

```bash
git pull
git submodule update --init --recursive
```

### Advance a submodule to latest upstream

```bash
git submodule update --remote event-graph-walker

# then test what depends on it
cd event-graph-walker && moon test && cd ..
moon test

git add event-graph-walker
git commit -m "chore: update event-graph-walker submodule"
```

### Inspect submodule changes

```bash
git status                   # monorepo root: pointer changes only
cd event-graph-walker
git status                   # submodule: actual file changes
```

### Daily rule

- Always make two commits: one inside the submodule, one in the root repo.
- If you change `event-graph-walker`, run its tests and root `moon test`.
- If you change `loom`, run `cd loom/loom && moon test` and any affected root tests.

## Daily Workflow

### Working on monorepo packages (editor/, projection/, cmd/, examples/web/)

No submodule awareness needed. Work as normal:

```bash
# edit files in editor/, projection/, etc.
moon check
moon test
```

### Working inside a submodule (e.g. event-graph-walker/)

Each submodule is its own git repository. Changes inside a submodule are committed to that submodule's repo, not to the parent monorepo.

```bash
cd event-graph-walker

# make changes
moon check
moon test

# commit inside the submodule
git add -A
git commit -m "feat: add new feature"
git push origin main

# go back to monorepo root
cd ..

# the monorepo now sees the submodule pointer has changed
git status
# modified:   event-graph-walker (new commits)

# update the monorepo to point to the new submodule commit
git add event-graph-walker
git commit -m "chore: update event-graph-walker submodule"
```

**Key point:** You always make two commits — one inside the submodule, one in the monorepo to update the pointer.

### Pulling latest changes

```bash
# pull monorepo changes
git pull

# update submodules to match what the monorepo expects
git submodule update --init --recursive
```

To pull the latest from all submodule remotes (even if the monorepo hasn't updated its pointers yet):

```bash
git submodule update --remote
```

### Running tests across the monorepo

Each MoonBit module has its own test suite. Run them separately:

```bash
# root module (crdt)
moon test

# submodule: event-graph-walker
cd event-graph-walker && moon test && cd ..

# submodule: loom (parser framework + lambda example)
cd loom/loom && moon test && cd ../..
cd loom/examples/lambda && moon test && cd ../..
```

## Submodule Reference

| Directory | Repository | Role | Has MoonBit module? |
|---|---|---|---|
| `event-graph-walker/` | [dowdiness/event-graph-walker](https://github.com/dowdiness/event-graph-walker) | Core CRDT library | Yes |
| `loom/` | [dowdiness/loom](https://github.com/dowdiness/loom) | Incremental parser framework | Yes |
| `svg-dsl/` | [dowdiness/svg-dsl](https://github.com/dowdiness/svg-dsl) | SVG DSL | Yes |
| `graphviz/` | [dowdiness/graphviz](https://github.com/dowdiness/graphviz) | Graphviz renderer | Yes |
| `valtio/` | [dowdiness/valtio](https://github.com/dowdiness/valtio) | Valtio state management | Yes |

Only `event-graph-walker`, `dowdiness/lambda`, and `dowdiness/loom` are path dependencies of the root MoonBit module. The others (`svg-dsl`, `graphviz`, `valtio`) are independent modules used by the web frontend.

## Common Pitfalls

### Detached HEAD inside a submodule

When you `git submodule update`, the submodule is checked out at a specific commit (detached HEAD). If you want to make changes:

```bash
cd event-graph-walker
git checkout main     # switch to a branch first
# now make changes and commit
```

### Forgetting to update the submodule pointer

If you commit and push changes inside a submodule but forget to update the monorepo pointer, other collaborators will still see the old version. Always remember the second commit:

```bash
cd ..
git add event-graph-walker
git commit -m "chore: update event-graph-walker submodule"
```

### Stale submodule after pulling

If `moon check` fails with missing package errors after `git pull`, your submodules are likely out of date:

```bash
git submodule update --init --recursive
```

### Editing the wrong copy

Each submodule directory is its own git repo. Running `git status` from the monorepo root will show submodule changes as a single line like `modified: event-graph-walker (new commits)`. To see the actual file changes, `cd` into the submodule and run `git status` there.

## Dependency Graph

```
svg-dsl (independent)
   ↑
graphviz (depends on svg-dsl)

valtio (independent)

event-graph-walker (independent)

loom (independent: loom/seam/incr/lambda)

crdt (root module)
 ├── depends on event-graph-walker (path dep)
 ├── depends on dowdiness/lambda (path dep)
 └── depends on dowdiness/loom (path dep)
```

## Why Submodules?

1. **Reusability** — `event-graph-walker` and `loom` can be used by other MoonBit projects without pulling the entire editor
2. **Independent versioning** — Each library is versioned and released on its own schedule
3. **Focused testing** — Each library has its own test suite and CI
4. **Clear boundaries** — Dependencies are explicit in `moon.mod.json`
5. **Separate issue tracking** — Bugs in the CRDT library are tracked in its own repository

## Debt Routing

When a problem appears in the root `crdt` module, do not assume the fix belongs
there.

- Missing text-edit primitives belong in `event-graph-walker/`
- Parser/edit semantics belong in `loom/`
- Root-module helpers should only exist when multiple root packages need them
- Standalone submodules should not grow dependencies upward on `crdt/`

See [Paying Technical Debt](technical-debt.md) for the full strategy.
