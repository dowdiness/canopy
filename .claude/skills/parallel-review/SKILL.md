# Parallel Pre-Merge Code Review

Spawns 4 specialized review agents simultaneously before merging a PR.

## Usage
`/parallel-review` — run before any PR merge.

## Prompt Template
```
Before I merge this PR, run a parallel code review. Spawn these agents
simultaneously:

Agent 1 (Correctness): Run all tests, check for compilation errors, verify
no stale references or double-wrapped types.

Agent 2 (API Design): Check all public exports — are types re-exported that
library consumers need? Are there any dead code deletions that remove
future-needed interfaces?

Agent 3 (Doc Drift): Compare docs/design.md, README, and roadmap against the
actual code changes in this branch — flag any inconsistencies.

Agent 4 (CI Readiness): Verify benchmarks actually run (not skipped), check
that test counts in docs match reality.

Compile all findings into a single review summary with severity levels.
```

## Agents

| Agent | Focus | Commands |
|-------|-------|----------|
| **Correctness** | Tests, compilation, type safety | `moon check`, `moon test` |
| **API Design** | Public exports, re-exports, dead code | `moon ide analyze <pkg>/` for public API + usage counts, `moon ide find-references` for cross-package usage |
| **Doc Drift** | Docs vs code consistency | `moon ide find-references` for symbol verification, compare design docs against changed files |
| **CI Readiness** | Benchmarks not skipped, doc test counts accurate | Check CI config, run `moon test` and count |

## Output Format

Each agent reports findings with severity:
- **BLOCKER** — must fix before merge
- **WARNING** — should fix, can merge with note
- **INFO** — low priority, track in TODO

Final summary lists all findings grouped by severity.

## Guardrails

- Never declare CI green if any check was skipped or failed
- Never mark a type as "unused" without checking `.mbti` files and public re-exports
- Doc counts must be verified against actual `moon test` output, not estimated
