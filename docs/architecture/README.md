# Architecture Documentation

Documentation for the CRDT collaborative editor architecture.

## Contents

- **[Module Structure](modules.md)** - Monorepo organization with git submodules
- **[Projectional Editing](PROJECTIONAL_EDITING.md)** - Projectional editing architecture plan
- **[Incremental Hylomorphism](Incremental-Hylomorphism.md)** - Theoretical foundations: cata/ana asymmetry, structural independence principles, memoized algebras, hylomorphism chains
- **[Anamorphism Discipline](anamorphism-discipline.md)** - Actionable design guide: four properties, boundary audit, anti-patterns
- **[Multi-Representation System](multi-representation-system.md)** - How the Printable trait family (Show, Debug, Source, Pretty) solves the expression problem for output formats; two families of renderers; ViewMode framework concept
- **[Vision: The Projectional Bridge](vision-projectional-bridge.md)** - Why Canopy exists: bridging the gap from syntax through semantics and intent to the user's mental model; the unity of computer
- **[Structure-Format Research](structure-format-research.md)** - PL research survey (Trees That Grow, Cofree, Finally Tagless, MLIR, Attributed Grammars, Ornaments), the semantic model approach, and bottom-up execution strategy with top-down vision
- **[Product Vision](product-vision.md)** - The full product: write, auto-structure, surface. One input, three storage layers (linking, clustering, pattern detection), three output models (while writing, when asked, proactively). How the code editor is the vertical slice proving every layer

## Quick Overview

The project implements the **eg-walker CRDT algorithm** with the following key components:

1. **Causal graph** - Tracks dependencies between operations
2. **Event graph walker** - Traverses operations in topological (causal) order
3. **FugueMax tree** - CRDT data structure for the actual sequence
4. **Version vectors** - Compact frontier representation for efficient network synchronization
5. **Branch system** - Efficiently checkout document state at any frontier

## Key Concepts

### Character-Level Operations

Operations work at the character level. Multi-character inserts should be split into individual character operations:

```moonbit
// CORRECT: Split into individual characters
for i = 0; i < text.length(); i = i + 1 {
  let ch = text[i:i + 1].to_string()
  let op = doc.insert(position + i, ch)
}
```

See `event-graph-walker/branch/branch_test.mbt` for examples.

### Version Vectors for Sync

Version vectors provide O(agents) comparison instead of O(operations):

```moonbit
// Create version vector from frontier
let vv = VersionVector::from_frontier(graph, frontier)

// Compare to detect synchronization state
if local_vv <= remote_vv {
  // Local is behind, need to pull
} else if remote_vv <= local_vv {
  // Already synchronized
} else {
  // Concurrent edits, need to merge
}
```

## References

- [eg-walker paper](https://arxiv.org/abs/2409.14252) - Original algorithm description
- [event-graph-walker README](../../event-graph-walker/README.md) - Module documentation
