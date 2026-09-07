# Documentation Doctrine

How we write docs to prevent staleness.

## The Problem

Docs that mix principles with implementation details become stale the moment code changes. Nobody updates "FugueTree uses HashMap" when someone replaces it with Arrays — the code is the source of truth for that. Architecture docs that reference specific types, fields, or struct definitions rot within weeks.

## The Doctrine

### Architecture docs — principles only

`docs/architecture/` contains philosophies, invariants, tradeoffs, and decision rationale. These are stable because they describe *why*, not *how*.

**Do:**
- "We use an append-only tree so ancestry information is permanent"
- "Ground truth is the text CRDT; the AST is derived via incremental parsing"
- "Delete is a tombstone flag, not structural removal — this preserves concurrent operation references"

**Don't:**
- "FugueTree has a `jump_ancestors : JumpAncestors` field"
- "The LCA index uses Euler Tour + Sparse Table"
- "Item struct has 12 fields including `mut deleted_ts : Int`"

If an architecture doc needs to reference code, link to the file — don't inline the definition. The file is always current; the inlined copy is immediately stale.

### Plans — implementation details welcome

`docs/plans/` is the right place for struct definitions, code examples, performance targets, and specific file/line references. Plans are designed to be ephemeral:

1. Written before implementation with concrete details
2. Executed task by task
3. Deleted or moved to `docs/archive/` when implementation is complete
4. If retained in the archive, marked with a terminal status and outcome at the top

Follow [Completing a plan](task-tracking.md#completing-a-plan) to choose deletion
or archiving, preserve current requirements, and repair incoming links.
Archived plans are historical: they describe the implementation at that time
and must not be treated as current guidance.

### Code describes the current implementation

For current implementation details, read the code:

- **Struct definitions** → `.mbti` interface files or source
- **API surface** → `pkg.generated.mbti`
- **Performance** → `moon bench --release`
- **Implemented behavior** → source and tests for the properties they cover

Never duplicate this information in long-lived docs. It will diverge.

### Document roles and conflicts

Reading order does not establish authority. Use each source for the question
it owns:

- Accepted product requirements, component contracts, and architectural
  decisions describe intended behaviour and constraints.
- Code and manifests describe what is implemented and configured. Tests and
  CI provide evidence for the properties and environments they check; passing
  tests alone does not establish compliance with every product requirement.
- Proposals and research provide options and evidence. They become requirements
  only through an explicit decision; their presence in the repository is not
  adoption.
- Performance reports describe measurements at a particular date and under
  stated conditions, not guarantees for the current implementation.
- GitHub Issues own active work status, as defined in [Task Tracking](task-tracking.md).
  Archived documents preserve history, not an execution queue.

Read the status and scope of relevant decisions, including partial
supersession. A newer date alone does not override an earlier requirement.
When documentation misdescribes current implementation details, correct that
description. When code differs from an accepted requirement, investigate the
mismatch instead of declaring the requirement wrong. Resolve conflicting
applicable requirements before basing a change on them; do not silently pick
the newest file or the current implementation.

### Navigation has one job

Use references or symlinks for shared content instead of embedding copies.
Identify duplication before adding another source of truth.

The root documentation index routes readers by purpose and affected component.
It should explain when a linked guide is needed, not repeat that guide's rules
or commands. Detailed indexes belong with the material they describe. A useful
cross-link may appear in more than one place; duplicated policy text creates
competing sources of truth.

Link existing component READMEs and context documents rather than copying their
requirements into `docs/`. Keep accepted decisions separate from exploratory
design in navigation, and identify research, measurements, and history as such.

### Performance docs — date and context

Performance numbers are snapshots. Every performance document must include:

- **Date** of measurement
- **What changed since last measurement** (or "baseline — first measurement")
- **Scale** (n=1000, n=10000, etc.)
- **Environment** (WSL2, native, etc.)

When a major optimization lands, old performance docs are not updated — they're left as historical records with their dates. New measurements go in new files.

## Document Types Summary

| Type | Location | Contains | Lifespan | Staleness risk |
|------|----------|----------|----------|----------------|
| Architecture | `docs/architecture/` | Principles, invariants, tradeoffs | Permanent | Low (no impl details) |
| Plans | `docs/plans/` | Struct defs, code, file paths, perf targets | Until completion | Removed on completion |
| Archive | `docs/archive/` | Completed plans, old measurements | Permanent (historical) | N/A (explicitly past) |
| Performance | `docs/performance/` | Dated benchmark results | Permanent (snapshot) | Low (dated, not updated) |
| Active backlog | GitHub Issues | Prioritized work and status | Until closure | Medium (re-validate claims) |

## Rules

1. **Architecture docs never reference specific types, fields, or line numbers.** Link to files instead.
2. **Completed plans leave `docs/plans/`.** Delete or archive them in the same
   change that completes implementation, following the task-tracking policy.
3. **Performance claims in issues include when they were measured.** Stale numbers lead to wasted optimization effort.
4. **Distinguish intended and implemented behaviour.** Code is authoritative for
   current implementation details; use [document roles and conflicts](#document-roles-and-conflicts)
   when a requirement and the implementation disagree.
