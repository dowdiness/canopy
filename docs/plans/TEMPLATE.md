# Plan Template

Use this template for any non-trivial task that should be executable by a coding
agent across sessions.

Keep one plan file per task. If the task is complete or superseded, move the
plan to `docs/archive/` and leave a short note in the originating issue or
TODO item.

```md
# <Task Title>

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
