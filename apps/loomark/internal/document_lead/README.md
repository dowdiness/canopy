# Document lead interpretation

This package owns the existing fail-closed derived-name analysis and a provisional
bounded Document-lead extractor. Catalog reconciliation and Export use
`derive_name`; they do not yet use `extract`.

`extract` parses the complete source and returns normalized form, primary text,
structured description, and omission flags. Explicit positive limits count Unicode
scalar values. They bound retained output, not parser work or temporary allocations.
No numeric defaults or visible/accessibility omission wording are accepted yet.
Scalar-safe cuts do not guarantee preservation of complete grapheme clusters.

## Stage 2 checkpoint, not acceptance

Numeric budgets and omission behavior still require browser comparison. Hard
parser-failure fallback is covered through its helper, not an induced failure of
the full parser. The full product fixture and accessibility matrix remains an
acceptance task. Recent documents does not consume this extractor yet.

Stage 2 measurement evidence, including exact fixture identities, independently
isolated phase timings, output sizes, and split equality cases, is recorded in
[`docs/evidence/2026-09-05-loomark-document-lead-stage2-measurement/README.md`](../../../../docs/evidence/2026-09-05-loomark-document-lead-stage2-measurement/README.md).
Those timings are not additive or a causal attribution of the whole extraction
cost. The CST number measures only the cheap wrapper conversion, not deep
conversion. Cold extraction cost still blocks stage acceptance and UI integration.

Reproduce from `apps/loomark`:

```sh
NEW_MOON_MOD=0 moon test internal/document_lead --target js --release
NEW_MOON_MOD=0 moon bench internal/document_lead --target js --release
```

Keep full-source parser semantics when investigating cost; do not silently parse
only a prefix. See the implementation plan linked from Issue #1411 for acceptance
gates.
