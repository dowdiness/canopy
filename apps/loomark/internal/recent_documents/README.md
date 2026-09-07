# Recent documents draft connection

This package owns Recent-documents rows, the feature-local keyed graph, and its
Select/Delete intents. `app` supplies resolved `Seed` values, maps intents back
to its existing reducer, and continues to own the New header action and legacy
Delete dialog.

`view` creates an outer `assoc_by` keyed by document ID before switching on the
opaque Sidebar provider's `visible()` value. That pure branch projects the
accepted lead source, derives a `DocumentLead`, then combines it with row
metadata. The visible branch owns a second keyed projection for row HTML, so
hidden rows are not rendered while unchanged pure leads can be reused on
reopen.

A seed without an accepted lead renders the generic accessible identity
`Document`; it remains selectable, but Delete is disabled. A current untouched
New entry remains a selected temporary row with no Delete action. Once a lead is
known, typing retains it until the app accepts a matching quiet source.

Rows use the provisional `DocumentLeadLimits` of 80 Unicode scalar values for
the primary and 160 for the description, with two-line clamps. Those limits are
not production acceptance or a grapheme-cluster policy. Labels and tooltips use
only the bounded primary and optional seed ordinal; rows do not render a Catalog
label or full source. Task icons are driven by IR-backed task-marker ranges;
checkbox-looking text in code remains literal.

The compiled non-minified JS browser test instruments extraction only in its
test copy. It observes two initial calls, still two after selection and a hidden
edit, three after changed and unchanged reopen, and four after a visible edit.
`inDispatch: false` establishes a dispatch boundary only—not a separate task or
a bound on synchronous extraction time. Full-source cold and quiet-path cost,
including possible first-paint delay, remains unresolved.

See the [authoritative implementation plan](../../../../docs/plans/2026-09-04-loomark-demand-driven-document-lead.md#current-draft-connection-slice)
for acceptance gates and remaining stages.
