# Changelog

All notable changes to `dowdiness/btree` are documented in this file.

## [Unreleased]

### Compatibility

- Restore the public `Eq`, `Debug`, and `Show` extension methods on `BTree`,
  `BTreeNode`, `FindResult`, `LeafContext`, and `Splice`.
- Point current-checkout compiler guidance to the authoritative repository
  `.moonbit-toolchain` pin; the `0.3.0` release compiler requirement below
  remains historical.

## [0.3.0] - 2026-11-18

### Breaking changes

- Adopt published `dowdiness/rle@0.4.0`: custom `BTreeElem` implementations
  must change `Sliceable::slice` from `Result[Self, RleError]` to
  `Self raise RleError`. Return successful elements directly and raise the
  same errors instead of returning `Ok` / `Err`.
- Target MoonBit compiler/core `0.10.21+06da1ed44`; older compilers are no
  longer supported. Formatter-generated signatures use `Int32` (the explicit
  spelling of the previous `Int` alias) and `#derive` attributes.

### Changed

- Update QuickCheck to published `0.15.1` and migrate property-test shrinking
  to `moonbitlang/core/quickcheck/shrink` without changing generators or
  shrink algorithms.
- Preserve the infallible BTree range/view API and invariant-failure boundary:
  internal slicing now uses `try!` for typed raised failures instead of
  unwrapping a `Result`. No recovery fallback or error suppression is added.
- Migrate both the production and independent scalar-proof modules to the
  pinned toolchain. Tree algorithms and scalar proof obligations are unchanged.

## [0.2.0] - 2026-07-30

### Breaking changes

- `BTree.root`, `BTree.min_degree`, and `BTree.size` are no longer public
  fields. Callers must use the constructors (`BTree::new`,
  `BTree::from_sorted`), query methods (`size()`, `span()`, `is_empty()`,
  `find()`, `get_at()`), and mutation methods (`init_root`,
  `mutate_for_insert`, `mutate_for_delete`, `delete_range`,
  `normalize_boundary_at`) instead of direct field access ([dowdiness/canopy#1000](https://github.com/dowdiness/canopy/issues/1000)).
- `LeafContext.children` is removed. Callers should use the parent-local
  `left_neighbor()` / `right_neighbor()` snapshots and the callback `Splice`
  contract (`start_idx`, `end_idx`, `new_leaves`) instead of inspecting the
  live children array ([dowdiness/canopy#1000](https://github.com/dowdiness/canopy/issues/1000)).

### Added

- Add `BTree::normalize_boundary_at`, a path-local operation that merges the
  complete mergeable closure around one exact logical leaf boundary, including
  boundaries whose leaves have different immediate parents ([dowdiness/canopy#1032](https://github.com/dowdiness/canopy/issues/1032)).
- Add deterministic, model-based property, distribution, and benchmark
  coverage for boundary normalization across tree heights and minimum degrees.

### Fixed

- Reject cumulative span overflow during construction (including
  `from_sorted`) and callback mutations. No invalid root is published;
  callback-mutation rejection leaves tree contents unchanged, excluding
  external side effects performed by the callback ([dowdiness/canopy#1010](https://github.com/dowdiness/canopy/issues/1010)).
- Preserve B+ tree occupancy for arbitrary-cardinality callback splices
  ([dowdiness/canopy#1026](https://github.com/dowdiness/canopy/issues/1026)).
- Restore the empty-tree lifecycle after a delete-shaped
  `mutate_for_insert` splice removes the final leaf ([dowdiness/canopy#1009](https://github.com/dowdiness/canopy/issues/1009)).

### Hardening

- `min_degree` is normalized to the inclusive interval
  `[2, @int.MAX_VALUE / 2]` by both `new` and `from_sorted`.
- Non-positive leaf spans are rejected: `init_root` aborts with
  `BTree::init_root: leaf span must be positive`; `from_sorted` aborts with
  `BTree::from_sorted: leaf spans must be positive`; callback splice spans
  abort with `BTree splice: leaf spans must be positive`.
- Repeated `init_root` on an already-initialized tree aborts with
  `BTree::init_root: tree is already initialized` instead of replacing its
  contents ([dowdiness/canopy#1000](https://github.com/dowdiness/canopy/issues/1000)).

### Dependencies

- `dowdiness/rle` bumped from `0.2.0` to `0.2.2`.
- `moonbitlang/quickcheck` bumped from `0.11.2` to `0.14.0`.

### Documentation

- Clarify that `LeafContext` neighbor values are immediate-parent snapshots,
  not logical predecessor or successor lookups across parent boundaries.
