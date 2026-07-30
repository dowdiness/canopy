# Agent PR-ready Validation Order

Status: completed

Tracking: [GitHub issue #1047](https://github.com/dowdiness/canopy/issues/1047)

## Why

Long implementation trains had the right checks available but no durable rule
for their order. Validation could therefore be reused after HEAD changed, or a
PR could be opened before dependency identity and generated interfaces were
checked on the reviewed commit.

## Scope

In:

- the normative implementation order in `AGENTS.md`
- an executable final gate in `scripts/validate-pr-ready.sh`
- public CLI contract tests
- PR evidence fields and CI wiring

Out:

- Markdown parser or editor behavior
- replacement of the GitHub CI matrix
- automatic commits, pushes, PR creation, or merging

## Desired State

Agents fetch and sync the base, establish a boundary matrix and failing test,
use a targeted edit loop, obtain independent review, and then validate one clean
candidate HEAD. The PR records that HEAD and base. Any later HEAD or fetched-base
change makes the local evidence fail closed.

## Implemented Steps

1. Added one stable phase table for both plan listing and execution, covering
   preflight, dependency, formatting/interface, targeted, full-suite,
   JavaScript, diff, and evidence phases.
2. Kept plan construction deterministic and effect-free; the shell performs
   repository and compiler effects in fail-fast order.
3. Stored successful HEAD/base/target-policy evidence in the ignored
   worktree-local `_build` directory and added a fast evidence verification
   mode.
4. Tested the public CLI through a temporary Git repository, including invalid
   targets, dirty and behind-base state, dependency failure, tracked interface
   mutation, listed/executed order identity, failed-run invalidation, stale
   HEAD/base evidence, and real local submodule origins for reachable, unpushed,
   and fetch-failure cases.
5. Removed the final gate's remaining Bash 4-only dependency and added a
   path-filtered macOS job that runs the CLI fixture and real downstream shell
   graph with system Bash 3.2 while faking compiler work only.
6. Added the contract test to the dependency CI job and exposed the evidence in
   the pull-request template.

## Acceptance Criteria

- [x] Dependency identity runs before generated-interface and compiler gates.
- [x] Affected packages are explicit, or the caller supplies a no-target reason.
- [x] The first failed phase prevents all later commands.
- [x] Full validation requires a clean HEAD containing the configured base.
- [x] Submodule origins are fetched/pruned, and commits match gitlinks and remain
      reachable from the configured origin.
- [x] Evidence becomes stale after HEAD or base-ref movement.
- [x] The shell orchestration contract runs with macOS system Bash 3.2.
- [x] The documented order, executable order, PR template, and CI self-test agree.

## Validation

```bash
./scripts/test-pr-ready-validation.sh
./scripts/check-moon-update-wrapped.sh
shellcheck scripts/check-moon-update-wrapped.sh scripts/validate-pr-ready.sh scripts/test-pr-ready-validation.sh scripts/test-pr-ready-bash32.sh
./scripts/validate-ci-yaml.sh
# macOS CI: /bin/bash ./scripts/test-pr-ready-bash32.sh
./scripts/validate-pr-ready.sh --no-target "shell and documentation workflow only"
./scripts/validate-pr-ready.sh --verify-evidence
```

## Risks

- The local full gate is intentionally expensive; the targeted loop remains the
  fast feedback path.
- Network freshness cannot be proven without a fetch, so `AGENTS.md` requires
  `git fetch origin main` before validation and evidence verification.
- The macOS job proves the real shell graph under Bash 3.2 with compiler work
  faked; it does not claim macOS parity for MoonBit, JavaScript, proof, or
  browser gates.
- The gate mirrors the local core of CI but does not replace isolated matrices,
  browser E2E, proof, or the aggregate required check.

## ADR Decision

No ADR needed: this is execution-policy enforcement for an existing development
workflow, not a product or library architecture decision.
