# Document lead interpretation

This package owns the existing fail-closed derived-name analysis and a provisional
bounded Document-lead extractor. Catalog reconciliation and Export use
`derive_name`; they do not yet use `extract`.

`extract` parses the complete source and returns normalized form, primary text,
structured description, omission flags, and additive task-marker provenance.
Explicit positive limits count Unicode scalar values. They bound retained output,
not parser work or temporary allocations. No numeric defaults or
visible/accessibility omission wording are accepted yet. Scalar-safe cuts do not
guarantee preservation of complete grapheme clusters.

`DocumentLead::task_marker_ranges()` reports the retained description's displayed
task prefixes. Each `DocumentLeadTaskMarkerRange` has an inclusive `start` and
exclusive `end`, measured in UTF-16 code-unit offsets (the convention used by
MoonBit `String` slicing and JavaScript string indices), plus `checked`. A range
covers the list marker and checkbox prefix, not task content. It is produced only
from task items in the Markdown IR: literal text and code examples are not
classified by regex. Ranges whose prefix is cut by description truncation are
omitted. The accessor returns a defensive array copy; the lead retains no CST,
IR, or source text. For a nested list whose first readable descendant supplies
the primary, the recursive description omits that primary but retains later
descendants and their provenance. The focused deep fixture uses a blank line
before the later item: without it, the parser treats the apparent later item as
content retained in the primary, not as a nested remainder.

## Current consumer connection

`internal/recent_documents` is the current draft consumer. It supplies
provisional limits of 80 scalar values for `primary` and 160 for `description`,
and its rows render each value with a two-line clamp. These are neither
production budgets nor a grapheme-cluster policy. The row renderer decorates
only `task_marker_ranges`; it does not infer tasks from description text, so
literal checkbox-looking code remains literal.

## Stage 2 checkpoint, not acceptance

Numeric budgets and omission behavior still require browser comparison. Hard
parser-failure fallback is covered through its helper, not an induced failure of
the full parser. The full product fixture and accessibility matrix remains an
acceptance task. Recent documents consumes the extractor only in the current
draft connection described above.

Stage 2 measurement evidence, including exact fixture identities, independently
isolated phase timings, output sizes, and split equality cases, is recorded in
[`docs/evidence/2026-09-05-loomark-document-lead-stage2-measurement/README.md`](../../../../docs/evidence/2026-09-05-loomark-document-lead-stage2-measurement/README.md).
Those timings are not additive or a causal attribution of the whole extraction
cost. The CST number measures only the cheap wrapper conversion, not deep
conversion. Cold extraction cost still blocks Stage 2 acceptance; the draft UI
connection does not resolve that gate.

Reproduce from `apps/loomark`:

```sh
NEW_MOON_MOD=0 moon test internal/document_lead --target js --release
NEW_MOON_MOD=0 moon bench internal/document_lead --target js --release
```

Keep full-source parser semantics when investigating cost; do not silently parse
only a prefix. See the implementation plan linked from Issue #1411 for acceptance
gates.
