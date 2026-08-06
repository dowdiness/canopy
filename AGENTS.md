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
# (canopy root + all modules/* and examples/* members). Read `moon.work` for the
# current member list — do not maintain a copy here; it drifts.
moon test                           # All workspace members
moon check                          # Lint across workspace

# Submodules are now workspace members (as of #740). Workspace-root
# commands cover them alongside Canopy-owned modules. Vendored submodule
# errors that Canopy cannot fix (pre-existing deprecations, trait API
# mismatches) are suppressed by scripts/vendored-check-common.sh in CI.
# See .github/workflows/ci.yml (Test Submodules matrix) for the full
# tested set and ci-lenient mode details.
moon info && moon fmt               # Format & update interfaces (NEW_MOON_MOD=0 for mixed manifests)
```

`.github/workflows/ci.yml` is the source of truth for the full fan-out — its
`Test Submodules` and `Test MoonBit Examples` matrices list exactly what is
checked and tested. Read it rather than trusting any list reproduced here.

JS build artifacts are namespaced under the module path: `_build/js/release/build/dowdiness/canopy/ffi/{lambda,json,markdown}/...`. `waku.config.ts`, tsconfigs, `scripts/build-js.sh`, `scripts/package-release.sh`, and CI artifact uploads all reference this namespaced path.

### Web Development
```bash
moon build --target js              # Build for web
cd apps/web && npm run dev      # Waku dev server (localhost:3000)
# Demo Hub:         http://localhost:3000/
# Mini-ML:          http://localhost:3000/ml
# JSON editor:      http://localhost:3000/json
# Markdown editor:  http://localhost:3000/markdown
# Canonical routes: /journey, /posts, /memo, /resume, /genui
```

TypeScript front-ends live alongside the MoonBit examples and have separate CI
coverage outside `moon test`:

- **TS typecheck** (`web-build`): `apps/web`, `examples/prosemirror`
- **Playwright E2E** jobs: `apps/web`, `apps/ideal/web`,
  `examples/demo-react`, `apps/canvas/web`

JS artifacts must be built (`moon build --target js`) before these run. See the
matching jobs in `.github/workflows/ci.yml` for the exact commands and the
pinned Playwright container per suite.

### Formal Verification
```bash
cd modules/semantic/proof && moon prove  # Requires Why3 + z3 on PATH
```
Proof packages are standalone modules with `"proof-enabled": true`. Run `moon prove` from within the proof package directory. Requires Why3 1.7.2 and z3 4.13.x on PATH (`eval $(opam env)`). See [docs/development/formal-verification.md](docs/development/formal-verification.md) for setup and decision guide.

### Benchmarks
```bash
moon bench --release                # Always use --release
cd deps/event-graph-walker && moon bench --release
cd deps/loom/examples/lambda && moon bench --release
```

## Submodule Workflow

`git submodule update --remote` pulls latest; stage only the pointers that
actually moved (`git add <changed-submodules>`). When editing a submodule, commit
and **push it to its own remote before** committing the parent pointer or opening
a parent PR — CI fails if the referenced submodule commit isn't on its remote.
Use PRs for submodule changes; never push to a submodule's main without asking.

A parent-owned patch overlay is permitted for a build or development tool when
publishing an upstream commit is intentionally deferred. Keep the recorded
submodule pointer on a remote-reachable commit; store the minimal patch under
`patches/<submodule>/`; pin and verify the exact base SHA in the installer; apply
the patch only to an ephemeral checkout; and test the resulting tool in CI. Do
not dirty or stage the submodule gitlink, copy the patched source into the parent,
or use this exception for runtime/library code linked into Canopy. Rebase or
remove the overlay when its base pointer moves.

## Rabbita Conventions

<!-- textlint-disable slopless/word-repetition -->

Rabbita is vendored at `./deps/rabbita/` (fork of `moonbit-community/rabbita` with the
`diff_subs` `update_tagger` patch — see
`docs/plans/2026-05-18-codemirror-rabbita-binding-phase2.md` §P2.0). Its docs
(`deps/rabbita/doc/*`, `deps/rabbita/rabbita/*/{README.mbt.md,design.md}`) are
authoritative: when they disagree with a plan or pasted spec, the docs win.

<!-- textlint-enable slopless/word-repetition -->

The `.claude/skills/rabbita` skill auto-invokes on rabbita work (`@sub`, `@cmd`,
`@html`, `@dom`, `@http`, bindings) and carries the doc checklist, idiom rules,
and canonical patterns — read it before designing.

## Adding a New Language

See [docs/development/ADDING_A_LANGUAGE.md](docs/development/ADDING_A_LANGUAGE.md) for the full guide (7 steps, with templates and validation checkpoints). Use Markdown as the reference implementation, not Lambda.

## Package Map

Use `docs/development/module-package-map.md` for placement rules, `moon.work`
for exhaustive root-workspace membership, and `.gitmodules` for repository
ownership. Use `moon ide outline <path>` to explore a package's public interface
before modifying it, and read the nearest `moon.mod` and `moon.pkg` for its
module ownership and dependencies.

## Documentation

Browse `docs/` for architecture, decisions, development guides, and performance snapshots. Key rules:

- Architecture docs = principles only, never reference specific types/fields/lines
- Code is the source of truth — if a doc and the code disagree, the doc is wrong
- GitHub Issues = canonical active backlog and status; `docs/plans/*.md` =
  implementation specs linked from issues
- `docs/archive/` = completed work. Do not search here unless asked for historical context.

## Development Workflow

### UI / Visual Feature Rule

**CRITICAL:** Prototype first, plan later. Build the smallest working change, test it in the browser, then iterate. Don't batch-build UI via subagents — tightly-coupled UI needs human-in-the-loop feedback. When the user questions value, stop and validate before continuing.

### Performance Optimization (project-specific addendum)

The base rule (microbenchmark before optimizing) applies. Additionally: stale profiling data from before prior optimizations is not evidence. Check if existing mitigations (batch modes, caching, lazy eval) already neutralize the issue before proposing new ones.

### Quality & Edit Workflow

<!-- textlint-disable slopless/word-repetition -->

Hooks enforce `moon check` after every edit and `moon fmt && moon info` before commits. After edits, also run `moon test` and rebuild JS if web is affected. For packages with `"proof-enabled": true`, also run `moon prove` from the proof package directory. After `moon info`, check `git diff *.mbti` for unintended trait bound changes — widening a bound is an API regression even if all current consumers satisfy it. See [docs/development/task-tracking.md](docs/development/task-tracking.md) for tracking workflow.

**One file per edit call.** A single `edit` targeting lines from two different files with one snapshot hash will silently corrupt the second file. Always re-read for a fresh hash between edits, even within the same package.

<!-- textlint-enable slopless/word-repetition -->

### Required Implementation Order

For implementation PRs, use this order so validation evidence belongs to the
exact commit that is reviewed:

1. `git fetch origin main`, then create or update a dedicated worktree so its
   HEAD contains the current `origin/main`.
2. Initialize submodules recursively and verify their recorded commits,
   configured-origin reachability, and dependency/version identity before
   changing behavior. Push changed submodule commits before the parent PR.
3. Write the behavioral boundary matrix, then add the first failing test. For
   Markdown stabilization, cover syntax form (ATX, Setext, multiline,
   indented), terminator (LF, CRLF, CR, EOF), operation (span projection,
   commit, conversion), and ownership context (top level, container,
   explicitly unsupported).
4. Keep the edit loop scoped to affected packages: failing test, implementation,
   targeted check, targeted release test.
5. Run independent review in parallel after the targeted loop is green; resolve
   findings before final validation.
6. Fetch `origin/main` again. If HEAD no longer contains it, sync the branch and
   repeat the affected targeted checks and review. Commit the candidate result,
   then run the final gate on that clean HEAD:
   `./scripts/validate-pr-ready.sh --target <package-path>`. Repeat `--target`
   for each affected MoonBit package. For changes with no MoonBit package,
   provide `--no-target "<reason>"` instead.
7. Immediately before opening, updating, or merging the PR, fetch `origin/main`
   once more and run `./scripts/validate-pr-ready.sh --verify-evidence`. If the
   base moved, repeat step 6; otherwise copy the HEAD/base evidence into the PR
   description.

Do not open a PR until the final gate succeeds on the current HEAD. A commit,
amend, rebase, cherry-pick, submodule-pointer change, manifest change, or
generated-interface change, or fetched base-ref movement invalidates earlier
evidence; rerun the full gate. The validator is a local preflight and does not
replace required GitHub CI.

### Existing API First Rule

Before defining any new function, method, helper, or type in this repository:

1. Search project APIs and the relevant MoonBit core APIs:
   `NEW_MOON_MOD=0 moon ide doc "<keyword>"`,
   `NEW_MOON_MOD=0 moon ide doc "<CoreType>::*"`,
   `NEW_MOON_MOD=0 moon ide doc "@<core-package>"`,
   `NEW_MOON_MOD=0 moon ide outline <pkg>`,
   `NEW_MOON_MOD=0 moon ide peek-def <symbol>`,
   `NEW_MOON_MOD=0 moon ide find-references <symbol>`.
2. State at least 2 candidate existing APIs, or explain why fewer exist.
   Include actual MoonBit core candidates for the data shape involved (for
   example `Map`, `Set`, `String`/`StringView`, `Bytes`/`BytesView`,
   `Buffer`/`StringBuilder`, `Option`/`Result`, `cmp`/`math` helpers,
   `Array`, `Iter`) rather than listing only `Iter`/`Array` by default.
3. For each candidate: where defined, what it covers, whether reused, and if not — why not.
4. If a new helper is unavoidable, state its responsibility boundary explicitly.

See `docs/api-map.md` for the task→existing-API index. Include a **Reuse check** section in your PR (PR template enforces this).

### MoonBit Implementation Policy

Extends the Existing API First Rule above from *new definitions* to *all* code.

Do not write new low-level loops, helpers, or data-manipulation code until you
have searched for existing project APIs and the actual MoonBit core APIs that
fit the data shape. Use `NEW_MOON_MOD=0 moon ide doc`, `peek-def`,
`find-references`, and `outline` to discover existing functions and methods.

**Prefer declarative code:**
- `match` / `guard` / pattern matching
- MoonBit core APIs for the concrete data shape: `Map`/`Set` lookups,
  `Option`/`Result` handling, `String`/`StringView`/`Bytes`/`BytesView`
  slicing, `Buffer`/`StringBuilder`, `cmp`/`math` helpers, plus `Array`/`Iter`
  methods such as `map`, `filter`, `fold`, `collect`
- arrow functions for higher-order callbacks (`x => expr`, `(a, b) => { ... }`);
  reserve `fn(...) { ... }` for named/local function values, explicit
  `raise`/`async` shape, or recursion
- list comprehensions when clearer
- `ArrayView` / `StringView` / `BytesView` instead of copying
- owning-type methods and constructors
- existing project functions over new helpers

**Avoid incidental mutation:**
- justify every `let mut`, push loop, manual index loop, and `while` loop
- use mutation only for builders, true state machines, interop, or measured
  performance reasons

**Before finalizing, report:**
1. existing project APIs reused
2. MoonBit core APIs checked (not just `Iter`/`Array`) and whether reused
3. existing APIs checked but not used
4. any new helper introduced, and why
5. remaining imperative code, and why it is necessary

Run `moon check` after edits and `moon test` for affected packages.

### Functional Core / Imperative Shell

The canonical cross-project rule is maintained in `~/.codex/AGENTS.md` and
`~/.pi/agent/AGENTS.md`; the Canopy-specific interpretation is documented
below.

Use [Functional Core, Imperative Shell](https://github.com/kbilsted/Functional-core-imperative-shell) as the default architecture for stateful and integration-heavy work.

- **Functional core:** keep domain transformations, validation, lowering, and
  state-transition decisions deterministic. Pass inputs and capabilities
  explicitly; return values, next state, commands, or structured diagnostics.
  The core must not read or write the DOM, filesystem, network, clock, random
  sources, provider clients, or mutable session/store state.
- **Imperative shell:** own I/O, scheduling, cancellation, replay cursors,
  lifecycle mutation, provider adapters, DOM/session adapters, and persistence.
  Keep the shell thin: translate effects into core inputs, then execute the
  core's returned decisions.
- For state machines, prefer a reducer-shaped boundary such as
  `State + Event -> (State, Decision)`. A mutable MoonBit façade is acceptable
  only when it remains a shell around deterministic transition logic.
- Do not expose internal mutable `Array` values from validated core results.
  Return immutable views where possible, or defensive copies when an adapter
  requires an owning array.
- Local mutation used only to build a returned value is permitted in a pure
  function, but it must have no observable external effect and still follow
  the mutation-justification rule above.
- Test the functional core with deterministic unit/property tests. Keep shell
  tests focused on effect wiring, integration boundaries, and a small number
  of end-to-end cases.

## Architecture Conventions

- When adding shared content, use symlinks or references to a single source of truth. Never embed copies of shared files — flag the duplication problem first.
- **Cross-package struct construction:** MoonBit's `pub struct` fields are read-only from outside the defining package. To construct or mutate fields cross-package, the struct must be `pub(all)` or have a named constructor. Verify this before planning any cross-package type migration.
- **Test ownership:** Each package tests its own logic only. Trust imported libraries' correctness by interface contract. When migrating code between packages, delete tests that now test the wrong module — track upstream test debt in the imported package's backlog.

## Model Routing

Route by judgment complexity and context impact, not by perceived importance.
Under ~50 lines / 1-3 files, implement inline when delegation overhead would
outweigh isolation benefits.

Use pi subagents as follows:

- `mechanic`: rote edits, renames, import/path migrations, and repeated
  exact-pattern changes.
- `scout`: broad non-MoonBit reconnaissance or unfamiliar non-MoonBit areas.
- `moonbit-scout`: MoonBit/Canopy reconnaissance involving `.mbt`, `.mbti`,
  `moon.pkg`, `moon.mod` (`moon.mod.json` in legacy submodules), package roots, or `moon ide`.
- `planner`: non-MoonBit implementation planning after reconnaissance.
- `moonbit-planner`: MoonBit implementation planning requiring Existing API
  First, package-root validation, `.mbti` drift checks, proof/docs/TS/submodule
  awareness.
- `worker`: clear implementation tasks large enough to benefit from isolated
  execution; review its patch before continuing.
- `reviewer`: risky non-MoonBit changes, pre-merge review, or independent
  validation.
- `moonbit-reviewer`: MoonBit/Canopy API, package-boundary, validation, or
  `.mbti` review.

Delegation requires clear scope — if you can't list the files to touch, research
first. Use the `/delegate` skill for the handoff format and task templates, and
`/parallel-review` or `moonbit-reviewer`/`reviewer` for review as appropriate.

Do not run editing-capable agents (`mechanic`, `worker`, or any agent with
edit/write access) in parallel in the same worktree. Parallel delegation is for
read-only reconnaissance/review unless separate worktrees are explicitly
arranged.

For current model assignments, prefer the global pi guidance in
`~/.pi/agent/AGENTS.md` rather than duplicating model names here.

## Code Review Expectations

- Expect Codex/CodeRabbit reviews on every PR — proactively check for common issues before submitting: correct API usage (e.g., get_result() not read(), get() not peek()), missed callers when refactoring, variant semantics preserved
- Cite the repository file and section when claiming that a change violates a
  Canopy rule. Distinguish repository requirements, adopted external standards,
  reviewer recommendations, and personal preferences. Do not score a
  recommendation or preference as a repository violation; label it clearly.
- Run format checks and full test suite before pushing

## Git & PR Workflow

- After rebase operations, verify files are in the correct directories
- When asked to 'commit remaining files', interpret generously even if phrasing is unclear
- **NEVER merge PRs until the required CI gate is green.** Run `gh pr checks <NUMBER>` and show the raw output — do not summarize or paraphrase. STOP if any check is `pending` or `fail`, or, when the workflow defines it, if `All Checks Passed` is not `pass`. The sole failure exception is an external `CodeRabbit` status whose raw reason is exactly `Review rate limited`: treat it as non-gating only when every repository-owned required check is `pass`, no check is pending, and the PR is otherwise mergeable. This exception does not cover CodeRabbit analysis failures or review findings. A `skipped` job is acceptable only when it is listed in the `needs` of `.github/workflows/ci.yml`'s `All Checks Passed` job and that aggregate job passes; the aggregate intentionally accepts path-filtered jobs whose result is `success` or `skipped`. Do not treat an unaggregated skipped check as green, and do not claim CI is green without verifying the aggregate and raw statuses.
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
