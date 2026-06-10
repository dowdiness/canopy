# Canopy — Agent Guidance

Incremental projectional editor with CRDT collaboration, built in MoonBit.

@~/.claude/moonbit-base.md

## Quick Commands

### Setup (after clone)
```bash
git clone --recursive https://github.com/dowdiness/canopy.git
# or if already cloned:
git submodule update --init --recursive
```

### Test & Build
```bash
# Workspace-root commands cover every in-repo module listed in `moon.work`
# (canopy root + all lib/* and examples/* members). Read `moon.work` for the
# current member list — do not maintain a copy here; it drifts.
moon test                           # All workspace members
moon check                          # Lint across workspace
moon info && moon fmt               # Format & update interfaces

# Submodules are NOT workspace members — each needs its own:
cd <submodule> && moon test
# The authoritative tested set is CI's "Test Submodules" matrix in
# .github/workflows/ci.yml (currently event-graph-walker, loom, svg-dsl,
# graphviz). rle, order-tree, alga, and vendored rabbita are pure deps —
# no separate test step; consumers exercise them.
```

`.github/workflows/ci.yml` is the source of truth for the full fan-out — its
`Test Submodules` and `Test MoonBit Examples` matrices list exactly what is
checked and tested. Read it rather than trusting any list reproduced here.

JS build artifacts are namespaced under the module path: `_build/js/release/build/dowdiness/canopy/ffi/{lambda,json,markdown}/...`. Vite configs, tsconfigs, `scripts/build-js.sh`, `scripts/package-release.sh`, and CI artifact uploads all reference this namespaced path.

### Web Development
```bash
cd examples/web && npm run dev      # Dev server (localhost:5173)
# Lambda editor:   http://localhost:5173/
# JSON editor:     http://localhost:5173/json.html
# Markdown editor: http://localhost:5173/markdown.html
moon build --target js              # Build for web
```

TypeScript front-ends live alongside the MoonBit examples and are typechecked +
E2E-tested separately in CI (they are NOT covered by `moon test`):

- **TS typecheck** (`Type Check TS Examples`): `examples/{web,prosemirror,demo-react}`
- **Playwright E2E** jobs: `examples/web`, `examples/ideal/web`,
  `examples/demo-react`, `examples/canvas/web`

JS artifacts must be built (`moon build --target js`) before these run. See the
matching jobs in `.github/workflows/ci.yml` for the exact commands and the
pinned Playwright container per suite.

### Formal Verification
```bash
cd lib/semantic/proof && moon prove  # Requires Why3 + z3 on PATH
```
Proof packages are standalone modules with `"proof-enabled": true`. Run `moon prove` from within the proof package directory. Requires Why3 1.7.2 and z3 4.13.x on PATH (`eval $(opam env)`). See [docs/development/formal-verification.md](docs/development/formal-verification.md) for setup and decision guide.

### Benchmarks
```bash
moon bench --release                # Always use --release
cd event-graph-walker && moon bench --release
cd loom/examples/lambda && moon bench --release
```

## Submodule Workflow

`git submodule update --remote` pulls latest; stage only the pointers that
actually moved (`git add <changed-submodules>`). When editing a submodule, commit
and **push it to its own remote before** committing the parent pointer or opening
a parent PR — CI fails if the referenced submodule commit isn't on its remote.
Use PRs for submodule changes; never push to a submodule's main without asking.

## Rabbita Conventions

<!-- textlint-disable slopless/word-repetition -->

Rabbita is vendored at `./rabbita/` (fork of `moonbit-community/rabbita` with the
`diff_subs` `update_tagger` patch — see
`docs/plans/2026-05-18-codemirror-rabbita-binding-phase2.md` §P2.0). Its docs
(`rabbita/doc/*`, `rabbita/rabbita/*/{README.mbt.md,design.md}`) are
authoritative: when they disagree with a plan or pasted spec, the docs win.

<!-- textlint-enable slopless/word-repetition -->

The `.claude/skills/rabbita` skill auto-invokes on rabbita work (`@sub`, `@cmd`,
`@html`, `@dom`, `@http`, bindings) and carries the doc checklist, idiom rules,
and canonical patterns — read it before designing.

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

### Performance Optimization (project-specific addendum)

The base rule (microbenchmark before optimizing) applies. Additionally: stale profiling data from before prior optimizations is not evidence. Check if existing mitigations (batch modes, caching, lazy eval) already neutralize the issue before proposing new ones.

### Quality & Edit Workflow

<!-- textlint-disable slopless/word-repetition -->

Hooks enforce `moon check` after every edit and `moon fmt && moon info` before commits. After edits, also run `moon test` and rebuild JS if web is affected. For packages with `"proof-enabled": true`, also run `moon prove` from the proof package directory. After `moon info`, check `git diff *.mbti` for unintended trait bound changes — widening a bound is an API regression even if all current consumers satisfy it. See [docs/development/task-tracking.md](docs/development/task-tracking.md) for tracking workflow.

<!-- textlint-enable slopless/word-repetition -->

### Existing API First Rule

Before defining any new function, method, helper, or type in this repository:

1. Search: `NEW_MOON_MOD=0 moon ide doc "<keyword>"`, `NEW_MOON_MOD=0 moon ide outline <pkg>`, `NEW_MOON_MOD=0 moon ide peek-def <symbol>`, `NEW_MOON_MOD=0 moon ide find-references <symbol>`.
2. State at least 2 candidate existing APIs, or explain why fewer exist.
3. For each candidate: where defined, what it covers, whether reused, and if not — why not.
4. If a new helper is unavoidable, state its responsibility boundary explicitly.

See `docs/api-map.md` for the task→existing-API index. Include a **Reuse check** section in your PR (PR template enforces this).

### MoonBit Implementation Policy

Extends the Existing API First Rule above from *new definitions* to *all* code.

Do not write new low-level loops, helpers, or data-manipulation code until you
have searched for existing project APIs and MoonBit/core APIs. Use
`NEW_MOON_MOD=0 moon ide doc`, `peek-def`, `find-references`, and `outline` to
discover existing functions and methods.

**Prefer declarative code:**
- `match` / `guard` / pattern matching
- `Iter` methods: `map`, `filter`, `fold`, `collect`
- list comprehensions when clearer
- `ArrayView` / `StringView` / `BytesView` instead of copying
- owning-type methods and constructors
- existing project functions over new helpers

**Avoid incidental mutation:**
- justify every `let mut`, push loop, manual index loop, and `while` loop
- use mutation only for builders, true state machines, interop, or measured
  performance reasons

**Before finalizing, report:**
1. existing APIs reused
2. existing APIs checked but not used
3. any new helper introduced, and why
4. remaining imperative code, and why it is necessary

Run `moon check` after edits and `moon test` for affected packages.

## Architecture Conventions

- When adding shared content, use symlinks or references to a single source of truth. Never embed copies of shared files — flag the duplication problem first.
- **Cross-package struct construction:** MoonBit's `pub struct` fields are read-only from outside the defining package. To construct or mutate fields cross-package, the struct must be `pub(all)` or have a named constructor. Verify this before planning any cross-package type migration.
- **Test ownership:** Each package tests its own logic only. Trust imported libraries' correctness by interface contract. When migrating code between packages, delete tests that now test the wrong module — track upstream test debt in the imported package's backlog.

## Model Routing

Route by judgment complexity rather than importance: Opus for architecture/novel
design/debugging, Sonnet for clear-spec implementation (50+ lines) and pre-merge
review, Haiku for mechanical work (renames, formatting, rote migration). Under
~50 lines / 1-3 files, implement inline — no delegation.

Delegation requires clear scope — if you can't list the files to touch, research
first. Use the `/delegate` skill for the handoff format and task templates, and
`/parallel-review` or `Agent(subagent_type: "code-reviewer")` for review.

## Code Review Expectations

- Expect Codex/CodeRabbit reviews on every PR — proactively check for common issues before submitting: correct API usage (e.g., get_result() not read(), get() not peek()), missed callers when refactoring, variant semantics preserved
- Run format checks and full test suite before pushing

## Git & PR Workflow

- After rebase operations, verify files are in the correct directories
- When asked to 'commit remaining files', interpret generously even if phrasing is unclear
- **NEVER merge PRs until CI is fully green.** Run `gh pr checks <NUMBER>` and show the raw output — do not summarize or paraphrase. If any check is `pending`, `fail`, or `skipped`, STOP and report the exact status. Skipped is NOT passing. Do not claim CI is green without verifying.
- After rebasing or refactoring, verify file paths haven't shifted unexpectedly. Run `git diff --stat` to confirm only intended files changed.
- Submodule push-order and PR rules: see [Submodule Workflow](#submodule-workflow).

## Design Context

**Elegant, Thoughtful, Deep** — beauty emerging from structure. Dark, focused,
typography-driven; deep navy base with restrained purple accent. References: Zed,
Dark/Luna, Strudel. Anti-references: generic SaaS, toy/playground aesthetics.

`.impeccable.md` is the single source of truth for the full design context —
personality, principles, palette, fonts, and design tokens. Read it before any
UI/visual work; do not duplicate token values here (they drift).

## References

- [eg-walker paper](https://arxiv.org/abs/2409.14252)
- [MoonBit docs](https://docs.moonbitlang.com)
- [Full documentation](docs/)
