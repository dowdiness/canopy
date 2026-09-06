# Development Workflow

## Validation Scope

Use the affected-package edit/check/test loop. Repository hooks run targeted
formatting and interface generation before commit, then the affected checks
and release tests before push. Documentation, tooling, web, and submodule
changes use their applicable lightweight contracts. See
[AGENTS.md](../../AGENTS.md#quality--edit-workflow), `lefthook.yml`, and the
`hook-*` recipes in `justfile` for the local gate.

Do not run workspace checks after every file edit or run MoonBit tests for
pure documentation changes. Repeat validation when changes or failures make
previous evidence stale. Full workspace builds and browser E2E belong to
GitHub CI. Run conditional proof checks from the proof package before push.
Review generated `.mbti` changes for unintended API or trait-bound changes.
Update snapshots only for intentional behavior changes, after reviewing the
new expected output.

## Required Implementation PR Order

For implementation PRs, use this order so validation evidence belongs to the
exact commit that is reviewed:

1. `git fetch origin main`, then create or update a dedicated worktree so its
   HEAD contains the current `origin/main`.
2. Initialize submodules recursively and verify their recorded commits,
   configured-origin reachability, and dependency/version identity before
   changing behavior. Push changed submodule commits before the parent PR.
3. Write the behavioral boundary matrix, then add the first failing test.
   For Markdown stabilization, use the conditional matrix below. Pure
   documentation/configuration changes use their applicable contracts;
   explain why no behavioral matrix or failing regression applies.
4. Keep the edit loop scoped to affected packages: failing test, implementation,
   targeted check, targeted release test.
5. Apply the review scope below after the targeted loop is green. Resolve
   findings before final validation; use parallel reviewers only for
   independent questions that benefit from separate perspectives.
6. Fetch `origin/main` again. If HEAD no longer contains it, sync the branch and
   repeat the affected targeted checks and review. Commit the candidate result,
   then push normally; Lefthook runs the affected local gate before the push.
7. Immediately before opening, updating, or merging the PR, fetch `origin/main`
   once more. If the base moved, repeat step 6; otherwise verify that the current
   HEAD is pushed and open or update the PR. GitHub CI validates the exact PR
   commit and remains the merge authority.

Do not open a PR until the normal push succeeds for the current HEAD. After a
commit, amend, rebase, cherry-pick, submodule-pointer change, manifest change,
or generated-interface change, push again so the pre-push gate checks that
candidate. The local gate is a fast preflight and does not replace required
GitHub CI, which remains the only full-workspace gate.

### Review Scope

Require independent review for changes to public APIs, package/ownership
boundaries, CRDT or parser semantics, concurrency, persistence, security, or
algorithms with nontrivial invariants. Resolve supported findings before final
validation. Explicit repository or user review requirements still apply.

For documentation, configuration, and mechanical changes without those risks,
review the diff and run the applicable contracts. State the chosen scope and
any limitations in the PR; a separate reviewer is not required solely because
a file changed. Add independent review when uncertainty remains.

Delegate when a bounded task can run independently and the result will improve
quality or save time. Use parallel review for distinct questions, not as a
fixed ceremony. Do not use line or file counts as a substitute for risk.

### Markdown Stabilization Boundary Matrix

Use this matrix when stabilizing Markdown span projection, commit, or
conversion behavior. It is not a checklist for unrelated changes.

| Dimension | Cases |
|-----------|-------|
| Syntax form | ATX, Setext, multiline, indented |
| Terminator | LF, CRLF, CR, EOF |
| Operation | Span projection, commit, conversion |
| Ownership context | Top level, container, explicitly unsupported |

Record which combinations the affected behavior supports and test its
boundaries, including how explicitly unsupported cases are handled.

## Working with Submodules

See [Monorepo & Submodules](monorepo.md) for the full guide on the git submodule setup, daily workflows, and common pitfalls.

## Paying Technical Debt

Before patching around a design problem locally, check
[Paying Technical Debt](technical-debt.md).

The short version:

- fix missing CRDT/parser APIs in the owning submodule,
- keep only one active editor architecture,
- centralize shared logic once,
- isolate any unavoidable workaround in a single helper with a comment naming
  the missing upstream API.

## Tracking Work

GitHub Issues is the canonical active backlog:

- follow [Task Tracking](task-tracking.md) for issue and plan ownership,
- search [open and closed issues](https://github.com/dowdiness/canopy/issues)
  before claiming work,
- create a plan in [`docs/plans/`](../plans/) from
  [TEMPLATE.md](../plans/TEMPLATE.md) when implementation is non-trivial, then
  link the issue and plan in both directions.

## Working with the Parser

The parser lives in `deps/loom/examples/lambda/`. The framework is in
`deps/loom/loom/`. When modifying:

- Check error recovery behavior with malformed input
- Test incremental parsing with loom's test suites
- Benchmark performance with `cd deps/loom/examples/lambda && moon bench --release`

## Working with the CRDT

The CRDT implementation is split across two modules:

**Core CRDT library (`deps/event-graph-walker/`):**
Causal graph (graph ops, eg-walker traversal, version vectors), operation log,
FugueMax sequence CRDT, branch system with merge, and document model.
See `deps/event-graph-walker/README.md` for the full package map.

**Application layer (`modules/canopy`):**
- `modules/canopy/editor/sync_editor*.mbt` - Active editor facade and parser/sync/undo orchestration
- `modules/canopy/editor/text_diff.mbt` - Text diffing utilities
- `deps/loom/text-change/` - Shared leaf contiguous text-change module

The shared `text-change` module now lives in the `deps/loom` submodule so parser
and editor packages resolve the same leaf dependency.

When adding features, consult:
- [event-graph-walker/README.md](../../deps/event-graph-walker/README.md)

## Web Development

The web demo is a Waku application served through Cloudflare Workers.
Canonical routes: `/`, `/ml`, `/json`, `/markdown`, `/journey`, `/posts`, `/memo`, `/resume`, `/genui`.
Legacy `.html` URLs return permanent redirects to their canonical route (except `/index.html`, which renders the Hub without redirect).

```bash
# From the apps/web/ directory
cd apps/web
npm install
npm run dev        # Start Waku dev server (http://localhost:3000)
npm run build      # Build Waku for production
npm run preview    # Preview production build
```

### Updating Web JavaScript

After making changes to MoonBit code that affects the web interface:

```bash
# From the repo root
just build-js
```

## Git Commit Process

Only create commits when requested by the user. When asked to commit:

1. Run `git status` and `git diff` to see changes
2. Review changes and draft commit message
3. Add relevant files to staging area
4. Create the commit using the active host's configured attribution; do not
   attribute another host or model.
5. Run `git status` after commit to verify

**Important:**
- Never use `git commit --amend` unless user explicitly requests it
- Never push unless explicitly requested
- Never use `-i` flag (interactive mode not supported)

## Pull Request Process

Follow [Required Implementation PR Order](#required-implementation-pr-order)
and the [PR template](../../.github/PULL_REQUEST_TEMPLATE.md). Summarize the
whole branch, include or link the single [reuse record](api-reuse.md), and
verify the current candidate was pushed normally before opening the PR.
Write multiline PR text to a file and pass it with `--body-file` when using
`gh`. Return the PR URL after creation. Before merge, follow the exact CI gate
rules in [Merge Gate](#merge-gate).

## Merge Gate

**NEVER merge PRs until the required CI gate is green.** Run `gh pr checks <NUMBER>` and show the raw output — do not summarize or paraphrase. STOP if any check is `pending` or `fail`, or, when the workflow defines it, if `All Checks Passed` is not `pass`. The sole failure exception is an external `CodeRabbit` status whose raw reason is exactly `Review rate limited`: treat it as non-gating only when every repository-owned required check is `pass`, no check is pending, and the PR is otherwise mergeable. This exception does not cover CodeRabbit analysis failures or review findings. A `skipped` job is acceptable only when it is listed in the `needs` of `.github/workflows/ci.yml`'s `All Checks Passed` job and that aggregate job passes; the aggregate intentionally accepts path-filtered jobs whose result is `success` or `skipped`. Do not treat an unaggregated skipped check as green, and do not claim CI is green without verifying the aggregate and raw statuses.

## Common Commands

These are command references, not a mandatory checklist for every change.
Run from the repository root unless a command changes directory. Choose the
scope using [Validation Scope](#validation-scope). The workspace membership
and CI matrices remain authoritative for which modules and suites are covered.

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
Proof packages are standalone modules with `"proof-enabled": true`. Run `moon prove` from within the proof package directory. Requires Why3 1.7.2 and z3 4.13.x on PATH (`eval $(opam env)`). See [docs/development/formal-verification.md](formal-verification.md) for setup and decision guide.

### Benchmarks
```bash
moon bench --release                # Always use --release
cd deps/event-graph-walker && moon bench --release
cd deps/loom/examples/lambda && moon bench --release
```
