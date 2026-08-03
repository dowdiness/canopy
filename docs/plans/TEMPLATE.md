# Plan Template

Use this template for any non-trivial task that should be executable by a coding
agent across sessions.

Keep one plan file per task. Link the plan from the canonical GitHub issue and
link the issue from the plan — the links are reciprocal and required in both
directions. If the task is complete or superseded, move the plan to
`docs/archive/` and record the outcome in the issue.

```md
# <Task Title>

## GitHub Issue

Canonical issue: <https://github.com/dowdiness/canopy/issues/N>

The issue and this plan MUST link each other (reciprocal link): the issue
points to this plan, and this plan points back to the issue above. A shared
queue issue is not closed when this plan completes unless the whole issue is
done.

## Why

Brief problem statement. State the current pain clearly and concretely.

## Scope

In:
- `path/to/file_a`
- `path/to/file_b`

Out:
- unrelated subsystem x
- optional follow-up y

## Current State

- Link the exact code/docs that define today's behavior.
- Note known constraints or invariants.

## Desired State

- Describe the end state in observable terms.
- Prefer outcomes over implementation preferences.

## Steps

1. First change.
2. Second change.
3. Validation / cleanup.

## Acceptance Criteria

- [ ] Concrete observable behavior or invariant.
- [ ] Required call sites migrated.
- [ ] Docs updated if public behavior or workflow changed.

## Validation

```bash
moon check
moon test
```

Add any submodule- or frontend-specific commands that are required for this
task.

## Risks

- Migration risk, performance risk, or known ambiguity.

## Notes

- Optional implementation notes.
- Link related GitHub issues, PRs, or archived plans.
```
