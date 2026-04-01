# Claude Code Quick Reference

`AGENTS.md` is the canonical repo-level agent guidance file.
`CLAUDE.md` is a symlink to `AGENTS.md` for compatibility and should not be
edited directly. If the symlink is replaced by a regular file, restore
`CLAUDE.md -> AGENTS.md`.

Canopy — incremental projectional editor with CRDT collaboration, built in MoonBit.

## MoonBit Language Notes

- `pub` vs `pub(all)` visibility modifiers have different semantics — check current docs before using
- `._` syntax is deprecated, use `.0` for tuple access
- `try?` does not catch `abort` — use explicit error handling
- `?` operator is not always supported — use explicit match/error handling when it fails
- `ref` is a reserved keyword — do not use as variable/field names
- Blackbox tests cannot construct internal structs — use whitebox tests or expose constructors
- For cross-target builds, use per-file conditional compilation rather than `supported-targets` in moon.pkg.json
- Error handling syntax: use `Unit!Error` or `T!Error` for fallible return types. Error propagation uses `!` suffix on calls, not `raise` keyword. Always verify MoonBit syntax against recent compiler behavior before committing.

## MoonBit Code Search

Prefer `moon ide` over grep/glob for MoonBit-specific code search. These commands use the compiler's semantic understanding, not text matching.

```bash
moon ide peek-def SyncEditor              # Go-to-definition with context
moon ide peek-def -loc editor/foo.mbt:5   # Definition at cursor position
moon ide find-references SyncEditor       # All usages across codebase
moon ide outline editor/                  # Package structure overview
moon ide doc "String::*rev*"              # API discovery with wildcards
```

Symbol syntax: `Symbol`, `@pkg.Symbol`, `Type::method`, `@pkg.Type::method`

When to use: finding definitions, tracing usages, understanding package APIs, discovering methods. Falls back to grep only for non-MoonBit files or cross-language patterns.

## Quick Commands

### Setup (after clone)
```bash
git clone --recursive https://github.com/dowdiness/canopy.git
# or if already cloned:
git submodule update --init --recursive
```

### Test & Build
```bash
moon test                           # canopy module tests
cd event-graph-walker && moon test # CRDT library tests
cd loom/loom && moon test          # Parser framework tests
cd loom/seam && moon test          # CST library tests
cd loom/examples/lambda && moon test # Lambda parser tests
moon info && moon fmt               # Format & update interfaces
moon check                          # Lint
```

### Web Development
```bash
cd examples/web && npm run dev      # Dev server (localhost:5173)
# Lambda editor: http://localhost:5173/
# JSON editor:   http://localhost:5173/json.html
moon build --target js              # Build for web
```

### Benchmarks
```bash
moon bench --release                # Always use --release
cd event-graph-walker && moon bench --release
cd loom/examples/lambda && moon bench --release
```

## Submodule Workflow

### Updating submodules
```bash
git submodule update --remote        # Pull latest from all submodules
git add event-graph-walker loom      # Stage submodule pointer updates
git commit -m "chore: update submodules"
```

### Making changes to a submodule
```bash
cd event-graph-walker
# make changes, commit, push
cd ..
git add event-graph-walker
git commit -m "chore: update event-graph-walker submodule"
```

## Package Map

**Main module: `dowdiness/canopy`**

| Package | Path | Purpose |
|---------|------|---------|
| `dowdiness/canopy` | `./` | Public MoonBit API (`top.mbt`), re-exports key types |
| `dowdiness/canopy/ffi` | `ffi/` | JS FFI entry point, 58 link exports |
| `dowdiness/canopy/core` | `core/` | Generic types: NodeId, ProjNode[T], SourceMap, reconcile, helpers |
| `dowdiness/canopy/protocol` | `protocol/` | EditorProtocol: ViewPatch, ViewNode, UserIntent |
| `dowdiness/canopy/editor` | `editor/` | SyncEditor, EphemeralHub, cursor/presence tracking, undo |
| `dowdiness/canopy/projection` | `projection/` | Language-agnostic: TreeEditorState, tree refresh, tree editor ops |
| `dowdiness/canopy/relay` | `relay/` | Relay room, wire protocol (multi-peer sync) |
| `dowdiness/canopy/lang/lambda` | `lang/lambda/` | Lambda language facade (re-exports from sub-packages) |
| `dowdiness/canopy/lang/lambda/proj` | `lang/lambda/proj/` | FlatProj, syntax_to_proj_node, populate_token_spans |
| `dowdiness/canopy/lang/lambda/flat` | `lang/lambda/flat/` | VersionedFlatProj (incr memo wrapper) |
| `dowdiness/canopy/lang/lambda/edits` | `lang/lambda/edits/` | TreeEditOp, text edit handlers, scope, free_vars, actions |
| `dowdiness/canopy/lang/lambda/zipper` | `lang/lambda/zipper/` | Zipper-based tree navigation |
| `dowdiness/canopy/lang/json` | `lang/json/` | JSON language facade (re-exports from sub-packages) |
| `dowdiness/canopy/lang/json/proj` | `lang/json/proj/` | JSON syntax_to_proj_node, populate_token_spans, memo builder |
| `dowdiness/canopy/lang/json/edits` | `lang/json/edits/` | JsonEditOp, edit handlers, bridge, new_json_editor |
| `dowdiness/canopy/cmd/main` | `cmd/main/` | CLI entry point, REPL, demo |

**Local module: `dowdiness/text_change`** (`lib/text-change/`) — text change utilities

**Submodule deps (separate git repos):**

| Module | Path | Purpose |
|--------|------|---------|
| `dowdiness/event-graph-walker` | `event-graph-walker/` | FugueMax CRDT, eg-walker algorithm |
| `dowdiness/loom` | `loom/loom/` | Incremental parser framework |
| `dowdiness/seam` | `loom/seam/` | Language-agnostic CST (CstNode, SyntaxNode) |
| `dowdiness/incr` | `loom/incr/` | Reactive signals (Signal, Memo) |
| `dowdiness/lambda` | `loom/examples/lambda/` | Lambda calculus parser |
| `dowdiness/order-tree` | `order-tree/` | Order-tree (O(log n) ancestor queries, FugueMax position) |

## Documentation

**Main docs:** [docs/](docs/)

- **Architecture:** [docs/architecture/](docs/architecture/)
  - [Module Structure](docs/architecture/modules.md)
  - [Incremental Hylomorphism](docs/architecture/Incremental-Hylomorphism.md)
  - [Anamorphism Discipline](docs/architecture/anamorphism-discipline.md)
  - [Projectional Editing](docs/architecture/PROJECTIONAL_EDITING.md)

- **Decisions:** [docs/decisions/](docs/decisions/)
  - [Framework Genericity Contract](docs/decisions/2026-03-29-framework-genericity-contract.md) — why framework/core/ must stay language-agnostic

- **Development:** [docs/development/](docs/development/)
  - [Workflow](docs/development/workflow.md)
  - [Task Tracking](docs/development/task-tracking.md)
  - [Conventions](docs/development/conventions.md)
  - [Testing](docs/development/testing.md)
  - [Documentation Doctrine](docs/development/documentation-doctrine.md) — how to write docs that don't go stale

- **Performance:** [docs/performance/](docs/performance/) — dated snapshots, not updated in place

- **Archive:** `docs/archive/` — completed plans and stale documents. Do not search here unless you need historical context.

**Documentation rules** (see [doctrine](docs/development/documentation-doctrine.md)):
- Architecture docs = principles only, never reference specific types/fields/lines
- Plans = implementation details, archived on completion
- Performance docs = dated snapshots, never updated (new measurements → new files)
- Code is the source of truth — if a doc and the code disagree, the doc is wrong

**Task tracking rules** (see [task-tracking](docs/development/task-tracking.md)):
- `docs/TODO.md` = active backlog index only, not the full implementation spec
- `docs/plans/*.md` = canonical execution spec for any non-trivial task
- GitHub issues = durable backlog/prioritization, not the only implementation plan
- For active work, keep exactly one canonical implementation spec and link everything else to it

**Submodule docs:**
- [event-graph-walker](event-graph-walker/README.md) - CRDT library
- [loom](loom/README.md) - Loom framework (lambda calculus parser in `loom/examples/lambda/`)

## Key Facts

**Project:** Canopy — incremental projectional editor
**CRDT:** eg-walker algorithm with FugueMax sequence CRDT, binary lifting jump pointers for O(log n) ancestor queries
**Language:** MoonBit
**Parser:** Lambda calculus with arithmetic (`λx.x`, `1+2`, `if-then-else`, `let x = 1`)
**Ground truth:** Text CRDT (FugueMax), AST derived via incremental parsing (loom)
**Submodules:** 6 git submodules (event-graph-walker, loom, svg-dsl, graphviz, valtio, rle)

## Development Workflow

### Performance Optimization Rule

**CRITICAL:** Before designing any performance optimization, write a microbenchmark that **reproduces the claimed bottleneck** in isolation. If the benchmark can't demonstrate the problem, stop and re-evaluate. Stale profiling data (from before prior optimizations) and O(bad) asymptotic complexity are not proof of a real problem. Check if existing mitigations (batch modes, caching, lazy eval) already neutralize the issue.

### Quality-First Approach

**CRITICAL:** When implementing or modifying MoonBit code, ALWAYS follow the `/moonbit-check` skill workflow to catch issues before they become bugs:

1. **Pre-flight**: Check dependencies with `moon update` before starting implementation
2. **Syntax awareness**: Verify MoonBit patterns (tuple destructuring, labelled args, error handling)
3. **Test verification**: Run tests and ensure error message formats match assertions exactly
4. **CLI testing**: If applicable, verify help text, flag behavior, and check for shadowing issues
5. **Interface review**: Update `.mbti` files and verify API changes are intentional
6. **Format & lint**: Run `moon fmt` and `moon check` before completing

### Incremental Edit Rule

**CRITICAL:** After every file edit, run `moon check` before proceeding to the next file. If there are errors, fix them immediately before continuing with the plan.

### Standard Workflow

1. Make edits
2. `moon check` - Lint
3. `moon test` - Run tests
4. `moon test --update` - Update snapshots (if behavior changed)
5. `moon info` - Update `.mbti` interfaces
6. Check `git diff *.mbti` - Verify API changes
7. `moon fmt` - Format
8. Rebuild JS if web affected

### Tracking Workflow

Before starting medium or large work:

1. Decide the canonical tracking surface using [docs/development/task-tracking.md](docs/development/task-tracking.md)
2. If the task is non-trivial, create a plan in `docs/plans/` from [docs/plans/TEMPLATE.md](docs/plans/TEMPLATE.md)
3. Add or update a short item in `docs/TODO.md` linking to that plan
4. Keep acceptance criteria and validation commands in the plan, not scattered across multiple docs

## MoonBit Conventions

- **Custom constructors for structs:** When defining public structs, declare a custom constructor via `fn new(...)` inside the struct body. This enables `StructName(args)` construction syntax with labelled/optional parameters, validation, and defaults. Prefer this over bare struct literals `{ field: value }`.
  ```moonbit
  struct MyStruct {
    x : Int
    y : Int

    fn new(x~ : Int, y? : Int) -> MyStruct  // declaration inside struct
  } derive(Show)

  fn MyStruct::new(x~ : Int, y? : Int = x) -> MyStruct {  // implementation
    { x, y }
  }

  let s = MyStruct(x=1)  // usage — like enum constructors
  ```
- **Block-style:** Code organized in `///|` separated blocks
- **Testing:** Use `inspect` for snapshots, `@qc` for properties
- **Files:** `*_test.mbt` (blackbox), `*_wbtest.mbt` (whitebox), `*_benchmark.mbt`
- **Format:** Always `moon info && moon fmt` before committing
- **Trait impl:** `pub impl Trait for Type with method(self) { ... }` — one method per impl block
- **Arrow functions:** `() => expr`, `() => { stmts }`. Empty body: `() => ()` not `() => {}`

## Code Changes

- Before suggesting code removal, check if symbols are re-exported as public API for downstream consumers. Do not delete structs/types that appear unused internally but may be part of the library's public interface.

## Code Review Standards

- Never dismiss a review request — always do a thorough line-by-line review even if changes seem minor
- Check for: integer overflow, zero/negative inputs, boundary validation, generation wrap-around
- Do not suggest deleting public API types (Id structs, etc.) as 'unused' — they may be needed by downstream consumers
- Verify method names match actual API before writing tests (e.g., check if it's `insert` vs `add_local_op`)

## Git & PR Workflow

- Always check if git is initialized before running git commands
- After rebase operations, verify files are in the correct directories
- When asked to 'commit remaining files', interpret generously even if phrasing is unclear
- When merging PRs, always verify CI status is actually passing (not skipped) before proceeding. Never represent CI as green if any checks were skipped or failed.
- After rebasing or refactoring, verify file paths haven't shifted unexpectedly. Run `git diff --stat` to confirm only intended files changed.

## Design Context

**Personality:** Elegant, Thoughtful, Deep — beauty emerging from structure.

**References:** Zed Editor, Dark/Luna, Strudel (strudel.cc)

**Anti-references:** Generic SaaS, toy/playground aesthetics.

**Design Principles:**
1. **Structure reveals meaning** — color, spacing, nesting communicate relationships before labels
2. **Progressive disclosure** — clean and focused by default, reveal depth on demand
3. **Typography carries weight** — Inter (UI) vs JetBrains Mono (code) creates clear zones
4. **Color is semantic, not decorative** — every color means something, no color without purpose
5. **Calm confidence** — solid and trustworthy, never frantic. Subtle transitions, generous whitespace

**Palette:** Deep navy base (`#1a1a2e`), purple accent (`#8250df`), syntax colors: keyword `#c792ea`, identifier `#82aaff`, number `#f78c6c`, string `#c3e88d`, operator `#ff5370`

See `.impeccable.md` for full design tokens and context.

## References

- [eg-walker paper](https://arxiv.org/abs/2409.14252)
- [MoonBit docs](https://docs.moonbitlang.com)
- [Full documentation](docs/)
