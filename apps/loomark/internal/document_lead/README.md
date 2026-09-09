# Document lead interpretation

This package owns the existing fail-closed derived-name analysis and a provisional
bounded Document-lead extractor. A successful unnamed analysis returns an empty
string; failure remains distinct. Catalog reconciliation and Export use
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

Contract tests exercise the package interface: lead extraction, bounded
presentation, equality, derived names, and reuse across edits. The one white-box
case covers hard parser-failure fallback because the production parser has no
stable public fixture that induces failure.

Historical Stage 2 phase measurements are recorded in
[`docs/evidence/2026-09-05-loomark-document-lead-stage2-measurement/README.md`](../../../../docs/evidence/2026-09-05-loomark-document-lead-stage2-measurement/README.md).
The exploratory decomposition harness is not part of the maintained contract
test suite. The isolated scaling runner remains reproducible from `apps/loomark`:

```sh
NEW_MOON_MOD=0 moon test internal/document_lead --target js --release
timeout 1200s python3 scripts/run-loomark-stage2-scaling.py \
  --cold-reps 3 --warmups 20 --samples 20 --timeout 300 \
  > /tmp/isolated-capture.log
```

Those timings are not additive or a causal attribution of the whole extraction
cost. Cold extraction cost still blocks stage acceptance and UI integration.

Keep full-source parser semantics when investigating cost; do not silently parse
only a prefix. See the implementation plan linked from Issue #1411 for acceptance
gates.
