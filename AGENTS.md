# Canopy — Agent Guidance

Incremental projectional editor with CRDT collaboration, built in MoonBit.

For MoonBit work, read `~/.claude/moonbit-base.md` for shared language guidance.
Other tasks do not need to load it.

## Instruction Scope

Use the shared MoonBit guidance for MoonBit work. Canopy's validation workflow
below overrides its per-file `moon check` and blanket workspace validation
instructions. Validate a coherent change in the affected packages; do not run
MoonBit checks for documentation-only edits. Complete the applicable hooks and
required CI, and repeat checks when changes or failures invalidate the evidence.

Tool-specific instructions apply only in their named host. Use the current
host's available tools and agent roles when working outside that host.

## Commands and Validation

Use [Workflow](docs/development/workflow.md) for setup, build, web, proof, and
benchmark commands. `moon.work` defines workspace membership; `lefthook.yml`
and `.github/workflows/ci.yml` define the local and CI gates. Run the applicable
checks for the affected packages and review generated interfaces for unintended
API or trait-bound changes.

## Submodule Workflow

`git submodule update --remote` pulls latest; stage only the pointers that
actually moved (`git add <changed-submodules>`). When editing a submodule, commit
and **push it to its own remote before** committing the parent pointer or opening
a parent PR — CI fails if the referenced submodule commit isn't on its remote.
Use PRs for submodule changes; never push to a submodule's main without asking.

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

Repository hooks run nothing after individual edits. Before commit, Lefthook runs targeted `moon fmt` and `moon info`; if either changes files, review and stage them before retrying the commit. Before push, Lefthook checks and tests affected packages and routes documentation, tooling, web, and submodule changes to their existing lightweight contracts. Workspace builds and browser E2E remain GitHub CI responsibilities. For packages with `"proof-enabled": true`, run `moon prove` from the proof package directory before push. After `moon info`, check `git diff *.mbti` for unintended trait bound changes — widening a bound is an API regression even if all current consumers satisfy it. See [docs/development/task-tracking.md](docs/development/task-tracking.md) for tracking workflow.

<!-- textlint-enable slopless/word-repetition -->

### Required Implementation Order

Before an implementation PR, read and follow
[Workflow: Required Implementation PR Order](docs/development/workflow.md#required-implementation-pr-order).
It owns the base/worktree, submodule, regression, review, and push sequence.
For Markdown stabilization, also use its conditional boundary matrix.

The current candidate must pass the normal pre-push gate before opening or
updating a PR; required GitHub CI remains the merge authority.

### Existing API First Rule

Before introducing definitions or low-level data manipulation, search existing
project APIs and the actual MoonBit core APIs for the data shape involved.
Use [the API map](docs/api-map.md) as an index and confirm the owning APIs.
Read [API Reuse](docs/development/api-reuse.md) for search tools and the record
format. Reuse evidence across related edits; revisit it when contracts,
dependencies, or requirements change.

Keep one concise reuse record per logical change in the PR or a linked note.
The final response may reference it. Do not repeat unchanged candidate lists
or require a fixed candidate count. Pure docs/config changes need no record.
This reporting scope overrides broader reporting requirements in shared
MoonBit guidance.

### MoonBit Implementation Policy

Prefer declarative decisions, existing core operations, views, owning-type
methods/constructors, and arrow callbacks. Follow the detailed conventions in
[API Reuse](docs/development/api-reuse.md#prefer-declarative-moonbit).
Account for mutation in the same reuse record, grouping shared justifications;
use it for builders, true state machines, interop, or measured performance.

### Functional Core / Imperative Shell

Keep domain decisions deterministic and effect wiring in a thin shell. Do not
expose internal mutable collections from validated results. Follow the
[repository design principle](docs/architecture/functional-core-imperative-shell.md)
when designing stateful or integration-heavy changes.

## Architecture Conventions

- When adding shared content, use symlinks or references to a single source of truth. Never embed copies of shared files — flag the duplication problem first.
- **Cross-package struct construction:** MoonBit's `pub struct` fields are read-only from outside the defining package. To construct or mutate fields cross-package, the struct must be `pub(all)` or have a named constructor. Verify this before planning any cross-package type migration.
- **Test ownership:** Each package tests its own logic only. Trust imported libraries' correctness by interface contract. When migrating code between packages, delete tests that now test the wrong module — track upstream test debt in the imported package's backlog.

## Model Routing

Delegate bounded, independent work when it improves quality or saves time.
Choose review scope by risk, following
[Workflow: Review Scope](docs/development/workflow.md#review-scope).

Use the active host's available roles. For pi delegation, read
[Agent Environments: Pi Delegation Roles](docs/development/agent-environments.md#pi-delegation-roles).

Delegation requires clear scope — if you can't list the files to touch, research
first. Use the `/delegate` skill for the handoff format and task templates, and
`/parallel-review` or `moonbit-reviewer`/`reviewer` for review as appropriate.

Do not run editing-capable agents (`mechanic`, `worker`, or any agent with
edit/write access) in parallel in the same worktree. Parallel delegation is for
read-only reconnaissance/review unless separate worktrees are explicitly
arranged.

## Code Review Expectations

- Verify API usage against actual definitions and check affected callers and
  preserved semantics. Use the review scope in the development workflow.
- Cite the repository file and section when claiming that a change violates a
  Canopy rule. Distinguish repository requirements, adopted external standards,
  reviewer recommendations, and personal preferences. Do not score a
  recommendation or preference as a repository violation; label it clearly.
- Run the affected format/check/test gates before pushing, as described in
  Quality & Edit Workflow. GitHub CI owns full-workspace validation.

## Git & PR Workflow

- After rebase operations, verify files are in the correct directories
- When asked to 'commit remaining files', interpret generously even if phrasing is unclear
- Never merge before required CI is complete and passing. Before merging,
  follow [Workflow: Merge Gate](docs/development/workflow.md#merge-gate) for raw
  status verification and the exact rules for skips and external statuses.
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

## Cursor Cloud specific instructions

Only when working in the provisioned Cursor Cloud VM, read
[Agent Environments: Cursor Cloud](docs/development/agent-environments.md#cursor-cloud-specific-instructions)
for snapshot setup, shell environment, and web development caveats.
