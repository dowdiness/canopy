# Development Workflow

This guide owns the sequence of implementation, validation, review, and submission.
Use [Testing](testing.md) to design test cases and [Coding Conventions](conventions.md)
to choose how code is written.

## Validation Scope

Use the affected-package edit/check/test loop. Repository hooks run targeted
formatting and interface generation before commit, then the affected checks
and release tests before push. Documentation, tooling, web, and submodule
changes use their applicable lightweight contracts. See
`lefthook.yml` and the
`hook-*` recipes in `justfile` for the local gate.

Do not run workspace checks after every file edit or run MoonBit tests for
pure documentation changes. Repeat validation when changes or failures make
previous evidence stale. Full workspace builds and browser E2E belong to
GitHub CI. Run conditional proof checks from the proof package before push.
If pre-commit `moon fmt` or `moon info` changes files, review and stage them
before retrying the commit. Review generated `.mbti` changes for unintended
API or trait-bound changes: widening a bound is an API regression even if
current consumers satisfy it. For packages with `"proof-enabled": true`, run
`moon prove` from that proof package directory before push.
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
   For Markdown stabilization, use the [conditional matrix](testing.md#markdown-stabilization-boundary-matrix). Pure
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

Verify API usage against definitions, check affected callers, and confirm
semantics are preserved. Cite the repository file and section for any claimed
rule violation; distinguish requirements and adopted standards from reviewer
recommendations or preferences.

Establish scope and the files to touch before delegating; use the `delegate`
skill for handoffs and the applicable review skill or role. Do not run agents
with write access in parallel in the same worktree. Parallel editing requires
separate worktrees; read-only reconnaissance and review may share a worktree.

## Working with Submodules

See [Monorepo & Submodules](monorepo.md) for the full guide on the git submodule setup, daily workflows, and common pitfalls.

## Paying Technical Debt

Before patching around a design problem locally, check
[Paying Technical Debt](technical-debt.md).

## Tracking Work

GitHub Issues is the canonical active backlog:

- follow [Task Tracking](task-tracking.md) for issue and plan ownership,
- search [open and closed issues](https://github.com/dowdiness/canopy/issues)
  before claiming work,
- create a plan in [`docs/plans/`](../plans/) from
  [TEMPLATE.md](../plans/TEMPLATE.md) when implementation is non-trivial, then
  link the issue and plan in both directions.

## Working with the Parser

Before changing parser behaviour, identify its owner through the
[Module / Package Map](module-package-map.md) and the
[Loom README](../../deps/loom/README.md). Follow the owning package's test
instructions and [parser test guidance](testing.md#parser-specific-testing).

## Working with the CRDT

Before changing replicated-state behaviour, read the owning library's
[event-graph-walker README](../../deps/event-graph-walker/README.md) and the
[Canopy module README](../../modules/canopy/README.mbt.md) for the integration
boundary. Use [CRDT test guidance](testing.md#crdt-specific-testing) when
selecting the affected regression cases.

## UI Work

Read [the design context](../../.impeccable.md) before UI or visual work. It
owns the design principles and tokens; do not duplicate their values here.
Prototype the smallest working change, test it in the browser, then iterate
with user feedback before expanding the plan. Do not batch-build tightly
coupled UI through subagents. If the user questions its value, stop expanding
the implementation and validate the direction with them.

## Performance Work

Before optimizing, reproduce the current bottleneck in a microbenchmark.
Profiling data from before earlier optimizations is not current evidence.
Check whether existing batching, caching, or lazy evaluation already addresses
the issue before proposing another optimization.

## Web Development

For changes affecting a web app, follow that app's README for build and
validation steps. For `apps/web`, use its
[validation instructions](../../apps/web/README.md#validation) and
[generated JavaScript instructions](../../apps/web/README.md#generated-javascript).
Prepare the generated artifacts before running consumers that require them.
Other web applications own their own validation instructions. The required
local/CI scope remains defined in [Validation Scope](#validation-scope).

## Git Commit Process

Only create commits when requested by the user.

After a rebase or refactor, inspect `git diff --stat` and verify file paths
before staging. When asked to commit remaining files, consider the full set
of remaining changes within the user's authorized scope.

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

## Execution Guides

Use these instructions when the corresponding step is needed; they are not a
checklist to run for every change.

| Step | Owning guide |
|---|---|
| Clone or initialize submodules | [Monorepo setup](monorepo.md#setup) |
| Run package or workspace tests | [Testing](testing.md#test-coverage) |
| Build generated JavaScript or run the web app | [Web app README](../../apps/web/README.md#validation) |
| Run benchmarks | [Testing: Benchmarking](testing.md#benchmarking) |
| Run conditional proofs | [Formal Verification](formal-verification.md) |
| Investigate CI jobs or artifacts | [CI/CD](../CI_CD.md) and the workflow files it references |
