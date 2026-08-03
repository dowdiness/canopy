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

### GitHub Issues

Use [GitHub Issues](https://github.com/dowdiness/canopy/issues) as the canonical
active backlog. Every active task must have one issue that owns:

- the problem and why it matters,
- prioritization and current status,
- an observable exit condition,
- links to its implementation plan and pull request when they exist.

Search open and closed issues before creating one. A recorded intention in an
archived document is not an active task until current evidence justifies an
issue. Use issue state, assignees, linked pull requests, and repository labels
instead of maintaining status in a Markdown backlog.

### `docs/plans/*.md`

Use one plan file per non-trivial task. The issue owns backlog status; the plan
is the canonical implementation spec for coding agents and should define:

- exact scope,
- out-of-scope boundaries,
- current state references,
- desired end state,
- ordered steps,
- acceptance criteria,
- validation commands.

Link the issue and plan in both directions. If a task is complete or no longer
active, move its plan to `docs/archive/`; keep the issue as the durable status
and discussion record.

### Archived backlog snapshots

Files such as `docs/archive/TODO-snapshot-2026-08-03.md` preserve historical
intent only. They must not carry active status or be treated as an execution
queue. Issue [#1124](https://github.com/dowdiness/canopy/issues/1124) owns the
one-time triage of that snapshot.

### `docs/development/technical-debt.md`

Use `technical-debt.md` for policy, not for per-task execution details.

It should answer:

- where debt should be fixed,
- how to decide the owning seam,
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

Open or identify the GitHub issue. For a task that fits one session and needs no
design discussion, the issue itself is sufficient when it states the problem,
scope, and observable exit condition.

### Medium or large task

1. Open or identify the GitHub issue.
2. Create `docs/plans/<date>-<slug>.md` from [TEMPLATE.md](../plans/TEMPLATE.md).
3. Link the issue and plan in both directions.
4. Execute against the plan and attach validation evidence to the pull request.
5. Move the completed plan to `docs/archive/` and close the issue through the
   pull request.

## Writing Good Issues

An executable issue should contain:

- a concrete problem rather than a proposed mechanism,
- current source or documentation evidence,
- explicit in-scope and out-of-scope boundaries,
- an observable exit condition,
- the canonical plan link when implementation needs a separate plan.

Avoid vague requests, unrelated umbrella lists, implementation diaries, and
duplicate issues for work already tracked elsewhere.

## Writing Good Plan Docs

Use [TEMPLATE.md](../plans/TEMPLATE.md).

Additional guidance:

- Put "Out:" in every plan.
- Link concrete source files in "Current State".
- Keep "Acceptance Criteria" behavioral.
- Put benchmark commands in "Validation" when performance matters.
- Record open questions explicitly instead of burying them in prose.

## Status Conventions

GitHub owns active status:

- open issue — recognized work,
- `ready-for-agent` label — scoped and executable without unresolved product
  decisions,
- assignee or linked work-in-progress pull request — execution in progress,
- blocked label or issue comment — waiting on a named external condition,
- closed issue — completed, rejected, duplicated, or superseded with the reason
  recorded.

Plan documents may describe execution progress, but must link to the issue
rather than create a second backlog status.

## Source Of Truth Rule

For any active task:

- the GitHub issue owns backlog membership, priority, and status,
- one plan may own the non-trivial implementation spec,
- the pull request owns the reviewed diff and validation evidence,
- archived documents preserve history only.

Do not maintain parallel active status tables in repository Markdown. When an
issue, plan, and pull request coexist, link them instead of copying their
contents.
