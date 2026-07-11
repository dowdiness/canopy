# Decisions Needed

Items requiring human judgment. Populated by `/moonbit-housekeeping triage`, resolved by moving to `docs/decisions/`.

**How to use:**
1. Review items below when starting a session or during weekly cleanup
2. Add your decision as a comment or update the item
3. When decided, create `docs/decisions/YYYY-MM-DD-<topic>.md` and remove from this file
4. Triage will add new items and flag resolved ones on next run

---

## Pending

### flat-tiny-node: batch vs amortized threshold for small nodes
**Source:** TODO.md §3
**Context:** JSON 20-member flat edit is 2x slower than batch mode. Three options documented:
- (a) batch-reparse fallback below a size threshold
- (b) amortized threshold that adjusts per-node
- (c) accept the tradeoff (marked "known tradeoff, not a framework bug")
**Blocks:** Nothing directly — performance optimization
**Evidence:** No plan file, no implementation started, TODO presents options without decision
**Added:** 2026-03-31

### interleaved-module-items: storage strategy for let/expr interleaving
**Source:** TODO.md §9
**Context:** The parser/AST can model interleaved module items, but the projection/editor representation still needs a deliberate design now that Lambda uses generic `ProjNode` module rows only.
**Blocks:** Grammar: interleaved let/expr support
**Evidence:** No plan file and no implementation started.
**Added:** 2026-03-31

---

## Recently Resolved

### structure-mode: PM block editor completion state
**Resolved:** 2026-07-11 — see `docs/decisions/2026-07-11-structure-mode-completion-state.md`.
Structure mode is complete and actively maintained (two E2E suites, verified
lazy-loading, seven-way-split update handler). The 2026-03-31 "unclear"
judgment was stale.
