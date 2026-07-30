# Changelog

All notable changes to `dowdiness/btree` are documented in this file.

## [0.2.0] - Unreleased

### Added

- Add `BTree::normalize_boundary_at`, a path-local operation that merges the
  complete mergeable closure around one exact logical leaf boundary, including
  boundaries whose leaves have different immediate parents.
- Add deterministic, model-based property, distribution, and benchmark
  coverage for boundary normalization across tree heights and minimum degrees.

### Fixed

- Reject cumulative span overflow before publishing a mutated tree.
- Preserve B+ tree occupancy for arbitrary-cardinality callback splices.
- Restore the empty-tree lifecycle after a delete-shaped
  `mutate_for_insert` splice removes the final leaf.

### Documentation

- Clarify that `LeafContext` neighbor values are immediate-parent snapshots,
  not logical predecessor or successor lookups across parent boundaries.

Package publication remains pending explicit maintainer approval after the
corresponding changes merge.
