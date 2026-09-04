# PROTOTYPE: Rabbita Document-lead graph probe

This throwaway browser probe asks whether the proposed two-layer graph behaves
as expected in the actual Rabbita runtime:

```text
Val[Vector[LeadSource]]
  -> app-scoped assoc_by(DocumentId)
       -> project content identity          pure lead nodes
       -> combine lead + presentation state recent inputs
  -> visibility.switch_by
  -> visible assoc_by(DocumentId)           rendered row nodes
```

Counters and a lifecycle log record component construction, lead extraction,
row rendering, and scope disposal. Probe-only local subscriptions observe scope
cleanup; production lead nodes remain pure and would not contain them.

Run from the repository root:

```sh
just prototype-loomark-document-lead-rabbita
```

Then open the printed URL. Suggested walkthrough:

1. Initial Hidden state: all counters remain zero.
2. **Show**: two pure branches, two extractions, two row branches, and one
   visible branch appear.
3. **Hide**: row and visible branches dispose; pure branches remain.
4. **Show** again: row branches rebuild without another extraction.
5. While visible, **Change A status only**: A's row rerenders, but extraction
   remains unchanged.
6. **Hide**, **Change A content**, **Refresh counters**: extraction remains
   unchanged.
7. **Show**: only A extracts again.
8. **Hide**, **Delete B**, **Refresh counters**: B's pure branch remains.
9. **Show**: B's pure branch disposes before only A is rendered.

## Verdict

Observed in the Rabbita browser runtime:

- Hidden startup built no keyed branches and ran no extraction.
- First Show built two pure branches, extracted A and B, built two row branches,
  and built one visible branch.
- Hide disposed both row branches and the visible branch while disposing no pure
  branch.
- An unchanged reopen rebuilt both rows without another extraction.
- Changing only A's presentation status rerendered A without extracting it.
- Changing A's content while hidden ran no extraction; the next Show extracted
  only A.
- Deleting B while hidden did not dispose its pure branch; the next Show disposed
  B before rendering only A.

The observed behavior matches the proposed two-layer topology. It validates the
Rabbita demand, reuse, orthogonal-input suppression, and delayed
keyed-reconciliation assumptions needed for an implementation plan.

This probe deliberately excludes Markdown parsing, responsive layout, Autosave,
and production Sidebar integration. It belongs only on
`prototype/loomark-document-lead-cache` and must not be merged into main.
