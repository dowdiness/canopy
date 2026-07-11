// Layer 2 caimeox differential oracle deferred to follow-up — see
// docs/superpowers/specs/2026-05-30-lambda-scope-graph-design.md.
//
// Deferred because integrating CAIMEOX/scope_graph would add a third-party
// dependency to moon.mod.json (it is not a current dep — see moon.mod.json)
// mid-PR, and this repo treats new external deps as a CI/build-fragility risk.
// Layer 2 is explicitly non-blocking: Layer 1 (graph_wbtest) + Layer 3
// (scope_equivalence_wbtest) are the shipping gates, and both pass. The
// differential oracle lands as a separate follow-up PR if/when the dependency
// is vetted.
