# Monorepo & Git Submodule Guide

Canopy is a monorepo that pulls in eight independent libraries via git
submodules. The MoonBit module at the repo root (`dowdiness/canopy`) depends on
several of those submodules through path dependencies in `moon.mod.json`.

## Layout

```
canopy/                          dowdiness/canopy (root MoonBit module)
├── core/  editor/  protocol/    monorepo packages (see docs/architecture.md)
├── projection/  relay/  ffi/
├── lang/{lambda,json,markdown}/
├── llm/  echo/  cmd/main/       monorepo packages
├── lib/btree/                   workspace member, in-tree library
├── lib/moji/                    workspace member, in-tree library
├── lib/zipper/                  workspace member, in-tree library
├── lib/text-change/             workspace member, in-tree library
├── lib/semantic/                in-tree library (NOT a workspace member)
├── adapters/editor-adapter/     in-tree TypeScript adapter package
├── examples/                    in-tree example apps (web, ideal, …)
│
├── event-graph-walker/          submodule (CRDT engine)
├── loom/                        submodule (parser framework, seam, incr, …)
├── rle/                         submodule
├── order-tree/                  submodule
├── graphviz/                    submodule
├── svg-dsl/                     submodule
├── valtio/                      submodule
└── alga/                        submodule
```

## Workspace members

`moon.work` lists the modules that root commands operate on:

```
.                  (the canopy module)
./lib/text-change
./lib/zipper
./lib/btree
./lib/moji
```

`moon test`, `moon check`, `moon fmt`, etc. at the repo root run against all
five. Everything else (submodules, `lib/semantic`, `examples/*`) is a separate
MoonBit module and needs its own `moon` invocation.

## Path dependencies

The root `moon.mod.json` references 14 path-based dependencies. The current
list is in `moon.mod.json`; below is a summary of where each lives:

| Dependency | Path |
|------------|------|
| `dowdiness/event-graph-walker` | `./event-graph-walker` (submodule) |
| `dowdiness/loom` | `./loom/loom` (submodule) |
| `dowdiness/seam` | `./loom/seam` (submodule) |
| `dowdiness/incr` | `./loom/incr` (submodule) |
| `dowdiness/pretty` | `./loom/pretty` (submodule) |
| `dowdiness/egglog` | `./loom/egglog` (submodule) |
| `dowdiness/egraph` | `./loom/egraph` (submodule) |
| `dowdiness/lambda` | `./loom/examples/lambda` (submodule example module) |
| `dowdiness/json` | `./loom/examples/json` (submodule example module) |
| `dowdiness/markdown` | `./loom/examples/markdown` (submodule example module) |
| `dowdiness/order-tree` | `./order-tree` (submodule) |
| `dowdiness/text_change` | `./lib/text-change` (in-tree workspace member) |
| `dowdiness/zipper` | `./lib/zipper` (in-tree workspace member) |
| `dowdiness/moji` | `./lib/moji` (in-tree workspace member) |

`svg-dsl`, `graphviz`, `valtio`, and `alga` submodules are *not* root path
dependencies — they are consumed by frontends or by other submodules.

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

Each submodule:

```sh
cd event-graph-walker && moon test
cd loom/loom          && moon test
cd loom/seam          && moon test
cd loom/incr          && moon test
cd loom/pretty        && moon test
cd loom/egglog        && moon test
cd loom/egraph        && moon test
cd loom/examples/lambda   && moon test
cd loom/examples/json     && moon test
cd loom/examples/markdown && moon test
cd svg-dsl   && moon test
cd graphviz  && moon test
cd rle       && moon test
cd order-tree && moon test
cd alga      && moon test
cd valtio    && moon test
```

Non-workspace in-tree modules:

```sh
cd lib/semantic       && moon test
cd lib/semantic/proof && moon prove   # needs Why3 + z3
cd examples/ideal        && moon test
cd examples/block-editor && moon test
cd examples/canvas       && moon test
```

The canonical fan-out (subset of the above) is in `.github/workflows/ci.yml`.

## Submodule reference

| Path | Repository | Role |
|------|------------|------|
| `event-graph-walker/` | [dowdiness/event-graph-walker](https://github.com/dowdiness/event-graph-walker) | CRDT engine |
| `loom/` | [dowdiness/loom](https://github.com/dowdiness/loom) | Parser framework, CST library, reactive signals, pretty-printer, egglog/egraph, example languages |
| `rle/` | [dowdiness/rle](https://github.com/dowdiness/rle) | Run-length encoded sequence |
| `order-tree/` | [dowdiness/order-tree](https://github.com/dowdiness/order-tree) | Counted/order-statistic tree |
| `graphviz/` | [dowdiness/graphviz](https://github.com/dowdiness/graphviz) | Graphviz renderer for the inspector |
| `svg-dsl/` | [dowdiness/svg-dsl](https://github.com/dowdiness/svg-dsl) | SVG DSL |
| `valtio/` | [dowdiness/valtio](https://github.com/dowdiness/valtio) | JS state management glue |
| `alga/` | [dowdiness/alga](https://github.com/dowdiness/alga) | Graph algebra |

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
