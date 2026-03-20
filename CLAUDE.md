# Claude Code Quick Reference

Canopy — incremental projectional editor with CRDT collaboration, built in MoonBit.

## Project Structure

**Monorepo with git submodules:**
- `event-graph-walker/` - CRDT library (submodule → [dowdiness/event-graph-walker](https://github.com/dowdiness/event-graph-walker))
- `loom/` - Incremental parser framework (submodule → [dowdiness/loom](https://github.com/dowdiness/loom))
  - `loom/loom/` — `dowdiness/loom`: parser framework (core, pipeline, incremental, viz)
  - `loom/seam/` — `dowdiness/seam`: language-agnostic CST (CstNode, SyntaxNode)
  - `loom/incr/` — `dowdiness/incr`: reactive signals (Signal, Memo)
  - `loom/examples/lambda/` — `dowdiness/lambda`: lambda calculus parser
- `svg-dsl/` - SVG DSL (submodule → [dowdiness/svg-dsl](https://github.com/dowdiness/svg-dsl))
- `graphviz/` - Graphviz renderer (submodule → [dowdiness/graphviz](https://github.com/dowdiness/graphviz))
- `valtio/` - Valtio state management (submodule → [dowdiness/valtio](https://github.com/dowdiness/valtio))
- `rle/` - RLE data structure library (submodule → [dowdiness/rle](https://github.com/dowdiness/rle))
- `editor/`, `projection/`, `cmd/` - Application packages (in monorepo)
- `examples/web/`, `examples/demo-react/` - Web frontends (in monorepo)

## MoonBit Language Notes

- `pub` vs `pub(all)` visibility modifiers have different semantics — check current docs before using
- `._` syntax is deprecated, use `.0` for tuple access
- `try?` does not catch `abort` — use explicit error handling
- `?` operator is not always supported — use explicit match/error handling when it fails
- `ref` is a reserved keyword — do not use as variable/field names
- Blackbox tests cannot construct internal structs — use whitebox tests or expose constructors
- For cross-target builds, use per-file conditional compilation rather than `supported-targets` in moon.pkg.json

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

## Documentation

**Main docs:** [docs/](docs/)

- **Architecture:** [docs/architecture/](docs/architecture/)
  - [Module Structure](docs/architecture/modules.md)
  - [Incremental Hylomorphism](docs/architecture/Incremental-Hylomorphism.md)
  - [Anamorphism Discipline](docs/architecture/anamorphism-discipline.md)
  - [Projectional Editing](docs/architecture/PROJECTIONAL_EDITING.md)

- **Development:** [docs/development/](docs/development/)
  - [Workflow](docs/development/workflow.md)
  - [Conventions](docs/development/conventions.md)
  - [Testing](docs/development/testing.md)

- **Performance:** [docs/performance/](docs/performance/)

- **Archive:** `docs/archive/` — completed plans and stale documents. Do not search here unless you need historical context.

**Submodule docs:**
- [event-graph-walker](event-graph-walker/README.md) - CRDT library
- [loom](loom/README.md) - Loom framework (lambda calculus parser in `loom/examples/lambda/`)

## Key Facts

**Project:** Canopy — incremental projectional editor
**CRDT:** eg-walker algorithm with FugueMax sequence CRDT
**Language:** MoonBit
**Parser:** Lambda calculus with arithmetic (`λx.x`, `1+2`, `if-then-else`, `let x = 1`)
**Ground truth:** Text CRDT (FugueMax), AST derived via incremental parsing (loom)
**Submodules:** 6 git submodules (event-graph-walker, loom, svg-dsl, graphviz, valtio, rle)

## Development Workflow

### Quality-First Approach

**CRITICAL:** When implementing or modifying MoonBit code, ALWAYS follow the `/moonbit-check` skill workflow to catch issues before they become bugs:

1. **Pre-flight**: Check dependencies with `moon update` before starting implementation
2. **Syntax awareness**: Verify MoonBit patterns (tuple destructuring, labelled args, error handling)
3. **Test verification**: Run tests and ensure error message formats match assertions exactly
4. **CLI testing**: If applicable, verify help text, flag behavior, and check for shadowing issues
5. **Interface review**: Update `.mbti` files and verify API changes are intentional
6. **Format & lint**: Run `moon fmt` and `moon check` before completing

### Standard Workflow

1. Make edits
2. `moon check` - Lint
3. `moon test` - Run tests
4. `moon test --update` - Update snapshots (if behavior changed)
5. `moon info` - Update `.mbti` interfaces
6. Check `git diff *.mbti` - Verify API changes
7. `moon fmt` - Format
8. Rebuild JS if web affected

## MoonBit Conventions

- **Block-style:** Code organized in `///|` separated blocks
- **Testing:** Use `inspect` for snapshots, `@qc` for properties
- **Files:** `*_test.mbt` (blackbox), `*_wbtest.mbt` (whitebox), `*_benchmark.mbt`
- **Format:** Always `moon info && moon fmt` before committing
- **Trait impl:** `pub impl Trait for Type with method(self) { ... }` — one method per impl block
- **Arrow functions:** `() => expr`, `() => { stmts }`. Empty body: `() => ()` not `() => {}`

## Code Review Standards

- Never dismiss a review request — always do a thorough line-by-line review even if changes seem minor
- Check for: integer overflow, zero/negative inputs, boundary validation, generation wrap-around
- Do not suggest deleting public API types (Id structs, etc.) as 'unused' — they may be needed by downstream consumers
- Verify method names match actual API before writing tests (e.g., check if it's `insert` vs `add_local_op`)

## Important Notes

- **Quality verification:** Use `/moonbit-check` skill for all MoonBit implementations
- **Character-level ops:** Split multi-char inserts into individual chars
- **Submodules:** After cloning, run `git submodule update --init --recursive`
- **Snapshots:** Use `moon test --update` when behavior changes
- **Interfaces:** Check `.mbti` files after refactoring
- **Benchmarks:** Always use `--release` flag
- **Parser module:** `dowdiness/lambda` in `loom/examples/lambda/`

## Git Workflow

- Always check if git is initialized before running git commands
- After rebase operations, verify files are in the correct directories
- When asked to 'commit remaining files', interpret generously even if phrasing is unclear

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
