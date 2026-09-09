# Recent documents

This package is the deep Recent-documents presentation module. It owns the
navigation, New action, rows, Delete confirmation, bounded lead labels, and
Create/Select/Delete/Cancel/Confirm intents. `app` supplies resolved `Seed`
values, maps intents back to its existing reducer, and does not assemble the
feature graph or interpret Recent-document HTML.

`build` creates an outer `assoc_by` keyed by document ID before switching on the
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
not production acceptance or a grapheme-cluster policy. Labels and tooltips use only the bounded primary. The module derives duplicate
ordinals from those bounded labels, so rows do not render or disambiguate with a
Catalog label or full source. Task icons are driven by IR-backed task-marker ranges;
checkbox-looking text in code remains literal.

The compiled non-minified JS browser test instruments extraction only in its
test copy. It observes two initial calls, still two after selection and a hidden
edit, three after changed and unchanged reopen, and four after a visible edit.
`inDispatch: false` establishes a dispatch boundary only—not a separate task or
a bound on synchronous extraction time. Full-source cold and quiet-path cost,
including possible first-paint delay, remains unresolved.

See the [authoritative implementation plan](../../../../docs/plans/2026-09-04-loomark-demand-driven-document-lead.md#current-deep-module-connection)
for acceptance gates and remaining stages.
