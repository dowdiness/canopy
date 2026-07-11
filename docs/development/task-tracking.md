# Task Tracking

This repository has a large design/archive history. To keep coding-agent work
reliable, active tasks need a small number of canonical tracking surfaces with
clear ownership.

## Agent Guidance Files

At the repo root:

- `AGENTS.md` is the canonical agent guidance file.
- `CLAUDE.md` is a compatibility symlink to `AGENTS.md` and should not be
  edited directly.

Local and CI validation should preserve the `CLAUDE.md -> AGENTS.md` symlink.

## Canonical Tracking Surfaces

### `docs/TODO.md`

Use `docs/TODO.md` as the active backlog index only.

Each active item should be brief:

- one problem statement,
- one reason it matters,
- one link to the canonical plan or GitHub issue,
- one concrete exit condition if no plan exists yet.

Do not turn `docs/TODO.md` into the full implementation spec.

### `docs/plans/*.md`

Use one plan file per non-trivial task.

A plan is the canonical implementation spec for coding agents. It should define:

- exact scope,
- out-of-scope boundaries,
- current state references,
- desired end state,
- ordered steps,
- acceptance criteria,
- validation commands.

If a task is complete or no longer active, move the plan to `docs/archive/`.

### GitHub Issues

Use GitHub issues for durable backlog tracking, prioritization, and cross-session
visibility.

Open an issue when the work is:

- a bug,
- medium or large in scope,
- likely to span sessions,
- something you want visible outside the repo docs.

Keep implementation detail in the plan doc. Keep prioritization and status in
the issue.

### `docs/development/technical-debt.md`

Use `technical-debt.md` for policy, not for per-task execution details.

It should answer:

- where debt should be fixed,
- how to decide the owning boundary,
- what kinds of compatibility layers should be retired.

It should not become the active backlog.

## Required Structure For Agent-Friendly Tasks

For any task likely to be executed by an agent, always provide:

- exact file paths,
- explicit in-scope list,
- explicit out-of-scope list,
- testable acceptance criteria,
- validation commands,
- one canonical doc or issue to follow.

Agents perform much better when "done" is observable and local.

## Recommended Workflow

### Small task

Use a single `docs/TODO.md` item if the work is small enough to finish in one
session and does not need design discussion.

Example:

```md
- [ ] Update `docs/development/API_REFERENCE.md` constructor signature
  Why: docs drift from live `SyncEditor::new` API.
  Exit: constructor docs match the current exported API.
```

### Medium or large task

1. Open or identify the GitHub issue if needed.
2. Create `docs/plans/<date>-<slug>.md` from [TEMPLATE.md](../plans/TEMPLATE.md).
3. Add a short TODO item linking to that plan.
4. Execute against the plan.
5. Archive the plan when done.

Example:

```md
- [ ] Retire `projection/` backward-compat facade
  Why: ownership is split across facade re-exports and canonical framework/lang packages.
  Plan: `docs/plans/2026-03-29-projection-facade-retirement.md`
  Exit: active callers import canonical packages directly; compatibility aliases removed or explicitly deferred.
```

## Writing Good TODO Items

Prefer this format:

```md
- [ ] <task title>
  Why: <why it matters>
  Plan: <path or GitHub issue>
  Exit: <observable done state>
```

Avoid:

- vague items like "improve parser",
- umbrella items with many unrelated subproblems,
- implementation diaries in `docs/TODO.md`,
- multiple active docs describing the same task differently.

## Writing Good Plan Docs

Use [TEMPLATE.md](../plans/TEMPLATE.md).

Additional guidance:

- Put "Out:" in every plan.
- Link concrete source files in "Current State".
- Keep "Acceptance Criteria" behavioral.
- Put benchmark commands in "Validation" when performance matters.
- Record open questions explicitly instead of burying them in prose.

## Status Conventions

Use consistent status language across docs and issues:

- `backlog` — recognized, not ready
- `ready` — scoped, can be executed
- `in_progress` — active work
- `blocked` — waiting on an external dependency or decision
- `done` — complete and validated

`docs/TODO.md` can continue using checkboxes, but keep the wording above in
issues and plan docs when status needs to be explicit.

## Source Of Truth Rule

For any active task, there must be exactly one canonical implementation spec.

Allowed patterns:

- TODO item only, for a trivial task
- TODO item + plan doc
- GitHub issue + plan doc

Avoid parallel active specs across:

- `docs/TODO.md`,
- an issue body,
- a plan doc,
- a PR description.

If multiple exist, the plan doc wins and the others should link to it.
