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
3. Archived to `docs/archive/completed-phases/` on completion
4. Marked with `**Status:** Complete` at the top

Staleness is a non-issue because archived docs are explicitly historical. If someone reads an archived plan, they know it describes the state at implementation time, not the current state.

### Code is the source of truth

For current implementation details, read the code:

- **Struct definitions** → `.mbti` interface files or source
- **API surface** → `pkg.generated.mbti`
- **Performance** → `moon bench --release`
- **Behavior** → tests

Never duplicate this information in long-lived docs. It will diverge.

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
| Plans | `docs/plans/` | Struct defs, code, file paths, perf targets | Until completion | None (archived) |
| Archive | `docs/archive/` | Completed plans, old measurements | Permanent (historical) | N/A (explicitly past) |
| Performance | `docs/performance/` | Dated benchmark results | Permanent (snapshot) | Low (dated, not updated) |
| TODO | `docs/TODO.md` | Prioritized work items with status | Ongoing | Medium (re-validate perf claims) |

## Rules

1. **Architecture docs never reference specific types, fields, or line numbers.** Link to files instead.
2. **Plans are archived on completion.** Same commit that marks the last task done.
3. **Performance claims in TODOs include when they were measured.** Stale numbers lead to wasted optimization effort.
4. **Code is the source of truth.** If a doc and the code disagree, the doc is wrong.
