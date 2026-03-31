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

### structure-mode: PM block editor completion state
**Source:** TODO.md §10
**Context:** "Test and polish PM block editor, verify lazy-loading." Bridge FFI and model files exist in examples/ideal but completion state is unclear.
**Blocks:** Block editor UX polish
**Evidence:** bridge_ffi.mbt and model.mbt exist, but insufficient evidence to judge done vs in-progress
**Added:** 2026-03-31

### flatproj-interleaved: storage strategy for let/expr interleaving
**Source:** TODO.md §10
**Context:** ModuleItem FlatProj storage change caused 2x regression. Alternative approach (helper methods on existing FlatProj) is noted but not started. Needs decision on whether to pursue fix or accept regression.
**Blocks:** Grammar: interleaved let/expr support
**Evidence:** No plan file, no implementation, alternative approach documented but not started
**Added:** 2026-03-31

---

## Recently Resolved

_(empty — move decided items here temporarily, then to docs/decisions/)_
