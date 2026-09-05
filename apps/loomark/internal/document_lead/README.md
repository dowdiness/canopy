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

JS release measurements from the current fixtures in `lead_wbtest.mbt`:

| Case | Mean | Standard deviation |
|---|---:|---:|
| Large mixed Markdown source | 879.70 ms | 67.66 ms |
| Distinct large source | 165.13 ms | 7.67 ms |
| Equality of short bounded results | 21.81 ns | 2.99 ns |

These numbers are not a speedup claim or a maximum-latency guarantee. The equality
case does not characterize maximum-budget comparisons. Cold extraction cost
blocks stage acceptance and UI integration until evaluated. Output-size reporting,
maximum-budget comparison cases, and a collection of separate mixed-size sources
remain measurement work; the mixed-Markdown case above is one source.

Reproduce from `apps/loomark`:

```sh
NEW_MOON_MOD=0 moon test internal/document_lead --target js --release
NEW_MOON_MOD=0 moon bench internal/document_lead --target js --release
```

Keep full-source parser semantics when investigating cost; do not silently parse
only a prefix. See the implementation plan linked from Issue #1411 for acceptance
gates.
