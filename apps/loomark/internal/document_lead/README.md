# Document lead interpretation

This package owns the total derived-name analysis and a bounded Document-lead
extractor. An unnamed or safely non-derivable source returns an empty string.
Catalog reconciliation and Export use `derive_name(...).text()`; the opaque
`DerivedName` also supports certified pure updates. Equality and debug output
observe only its text, not its private reuse certificate. Prefixes containing
`[` are not certified because later reference definitions can change their
Markdown interpretation. These consumers do not yet use `extract`.

`extract(source : String)` parses the complete source and returns normalized form,
primary text, structured description, and omission flags. Primary text is bounded
to 80 Unicode scalar values and the description to 160. These bounds apply to
retained output, not parser work or temporary allocations. Scalar-safe cuts do
not guarantee preservation of complete grapheme clusters.

Hard parser-failure fallback is covered through its helper, not an induced
failure of the full parser. Recent documents does not consume this extractor
yet.

Contract tests exercise the package interface: lead extraction, bounded
presentation, equality, derived names, and reuse across edits. The one white-box
case covers hard parser-failure fallback because the production parser has no
stable public fixture that induces failure.

Historical Stage 2 phase and scaling measurements are recorded under
[`docs/evidence`](../../../../docs/evidence/). Their one-off measurement harnesses
are available at the commits named by those records rather than maintained as
part of this package. The timings are not additive or a causal attribution of
the whole extraction cost.

The semantic module is complete in PR #1412. Full-source parsing remains a known
execution cost; demand-driven browser integration and its acceptance belong to
PR #1419, while any off-thread execution mechanism requires a separate decision.
Keep full-source parser semantics when investigating cost; do not silently parse
only a prefix.
