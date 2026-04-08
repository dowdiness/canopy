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
- Be aware of orphan rules, deprecated typealias syntax, pub using semantics, and that string indexing doesn't return Char. Verify MoonBit-specific syntax before committing.

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

## Adding a New Language

See [docs/development/ADDING_A_LANGUAGE.md](docs/development/ADDING_A_LANGUAGE.md) for the full guide (7 steps, with templates and validation checkpoints). Use Markdown as the reference implementation, not Lambda.

## Package Map

The SessionStart hook runs `scripts/package-overview.sh` which provides a live package map at the start of every session. Use `moon ide outline <path>` to explore any package's public API before modifying it. Read `moon.mod.json` for module dependencies.

## Documentation

Browse `docs/` for architecture, decisions, development guides, and performance snapshots. Key rules:

- Architecture docs = principles only, never reference specific types/fields/lines
- Code is the source of truth — if a doc and the code disagree, the doc is wrong
- `docs/TODO.md` = active backlog index; `docs/plans/*.md` = execution specs
- `docs/archive/` = completed work. Do not search here unless asked for historical context.

## Development Workflow

### UI / Visual Feature Rule

**CRITICAL:** Prototype first, plan later. Build the smallest working change, test it in the browser, then iterate. Don't batch-build UI via subagents — tightly-coupled UI needs human-in-the-loop feedback. When the user questions value, stop and validate before continuing.

### Performance Optimization Rule

**CRITICAL:** Before designing any performance optimization, write a microbenchmark that **reproduces the claimed bottleneck** in isolation. If the benchmark can't demonstrate the problem, stop and re-evaluate. Stale profiling data (from before prior optimizations) and O(bad) asymptotic complexity are not proof of a real problem. Check if existing mitigations (batch modes, caching, lazy eval) already neutralize the issue.

### Quality & Edit Workflow

Hooks enforce `moon check` after every edit and `moon fmt && moon info` before commits. After edits, also run `moon test` and rebuild JS if web is affected. See [docs/development/task-tracking.md](docs/development/task-tracking.md) for tracking workflow.

## MoonBit Conventions

- **Custom constructors for structs:** When defining public structs, declare a custom constructor via `fn new(...)` inside the struct body. This enables `StructName(args)` construction syntax with labelled/optional parameters, validation, and defaults. Prefer this over bare struct literals `{ field: value }`.
  ```moonbit
  struct MyStruct {
    x : Int
    y : Int

    fn new(x~ : Int, y? : Int) -> MyStruct  // declaration inside struct
  } derive(Debug)

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
- **StringView/ArrayView patterns:** Use `.view()` + array patterns for iteration instead of index loops. Works with `String`, `Array`, `Bytes`. Prefer `loop s.view() { [ch, ..rest] => ...; [] => ... }` over `for i = 0; i < s.length(); i = i + 1 { s[i] }`.
  ```moonbit
  // Prefer this:
  loop text.view(), 0 {
    [], _ => ()
    [ch, ..rest], i => {
      process(ch)
      continue rest, i + 1
    }
  }
  // Over this:
  for i = 0; i < text.length(); i = i + 1 {
    let ch = text[i]
    process(ch)
  }
  ```
  Also useful for prefix matching: `match s.view() { [.."let", ..rest] => ... }` and palindrome-style middle access: `[a, ..rest, b] => ...`

## Architecture Conventions

- When adding shared content, use symlinks or references to a single source of truth. Never embed copies of shared files — flag the duplication problem first.

## Code Review Standards

- Never dismiss a review request — always do a thorough line-by-line review even if changes seem minor
- Check for: integer overflow, zero/negative inputs, boundary validation, generation wrap-around
- Do not delete public API types or re-exported symbols as 'unused' — they may be needed by downstream consumers
- Verify method names match actual API before writing tests (e.g., check if it's `insert` vs `add_local_op`)

## Git & PR Workflow

- Always check if git is initialized before running git commands
- After rebase operations, verify files are in the correct directories
- When asked to 'commit remaining files', interpret generously even if phrasing is unclear
- **NEVER merge PRs until CI is fully green.** Run `gh pr checks <NUMBER>` and show the raw output — do not summarize or paraphrase. If any check is `pending`, `fail`, or `skipped`, STOP and report the exact status. Skipped is NOT passing. Do not claim CI is green without verifying.
- After rebasing or refactoring, verify file paths haven't shifted unexpectedly. Run `git diff --stat` to confirm only intended files changed.
- When making changes across submodules, always push submodule commits to remote BEFORE pushing the parent repo or creating parent PRs. CI will fail if submodule commits aren't available on remote.
- Always use PRs for submodule changes — never push directly to main branches of submodules without asking first.

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
