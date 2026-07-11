# Incremental Parser Implementation Plan

## Overview

Transform the current Lambda Calculus parser into an incremental parser using the Wagner-Graham LR incremental parsing algorithm (1998). The parser will integrate with the CRDT module to maintain synchronized parse trees across replicas during collaborative editing.

## Requirements Summary

- **Use Case**: CRDT integration for collaborative editing
- **Algorithm**: Wagner-Graham LR approach (basis for Tree-sitter)
- **Error Handling**: Error recovery with partial trees
- **API Compatibility**: Breaking changes acceptable

## Background: Wagner-Graham Algorithm

Based on the seminal paper ["Efficient and Flexible Incremental Parsing"](https://dl.acm.org/doi/10.1145/293677.293678) by Tim A. Wagner and Susan L. Graham (1998), this algorithm:

1. **Maintains a parse tree** that can be efficiently updated when text changes
2. **Identifies unchanged regions** and reuses their parse subtrees
3. **Reparses only affected regions** using damage/repair techniques
4. **Uses LR parsing** with sentential forms for optimal incremental updates
5. **Achieves O(|affected region|)** time complexity for updates

The algorithm is the foundation for [Tree-sitter](https://github.com/tree-sitter/tree-sitter), a widely-adopted incremental parser used in VSCode, Neovim, and other editors.

## Current Parser Analysis

### Architecture
- **Type**: Two-phase pipeline (Lexer → Parser)
- **Style**: Recursive descent with mutual recursion
- **State**: Minimal (position in token array)
- **AST**: Immutable tree structure
- **Errors**: All-or-nothing, no recovery

### Strengths for Incremental Conversion
1. Functional-style state management
2. Simple state structure (only position)
3. Clean lexer/parser separation
4. Immutable AST (easy to cache/reuse)
5. No side effects (pure parsing)

### Current Limitations
1. Eager tokenization (entire input upfront)
2. No caching or memoization
3. No source position tracking in AST
4. No error recovery
5. Cannot return partial results
6. No node identity for tracking

## Implementation Strategy

### Phase 1: Add Source Tracking and Node Identity

**Objective**: Augment AST nodes with source positions and unique identifiers.

**Files to Modify**:
- [parser/term.mbt](../parser/term.mbt)
- [parser/parser.mbt](../parser/parser.mbt)
- [parser/lexer.mbt](../parser/lexer.mbt)

**Changes**:

1. **Add source range to tokens** (`token.mbt`):
```moonbit
pub struct TokenInfo {
  token : Token
  start : Int    // Start byte offset in source
  end : Int      // End byte offset in source
} derive(Show, Eq)
```

2. **Create positioned term structure** (`term.mbt`):
```moonbit
pub struct TermNode {
  kind : TermKind
  start : Int          // Source start position
  end : Int            // Source end position
  node_id : Int        // Unique node identifier
  children : Array[TermNode]  // For uniform tree traversal
} derive(Show)

pub enum TermKind {
  Int(Int)
  Var(String)
  Lam(String)          // Parameter name, body is in children[0]
  App                  // Left in children[0], right in children[1]
  Bop(Bop)            // Op type, operands in children
  If                   // Condition, then, else in children
  Error(String)        // NEW: Error node for recovery
}
```

3. **Update lexer to track positions**:
- Modify `tokenize_helper` to record start/end positions
- Return `Array[TokenInfo]` instead of `Array[Token]`
- Track byte offsets during scanning

4. **Update parser to build positioned nodes**:
- Track source positions during parsing
- Generate unique node IDs (use counter or hash)
- Construct `TermNode` with position info

**Validation**: Parser still produces correct trees, now with position data.

---

### Phase 2: Implement Token Cache

**Objective**: Cache tokenization results by source ranges to avoid re-lexing unchanged text.

**Files to Create**:
- `parser/token_cache.mbt`

**Files to Modify**:
- [parser/lexer.mbt](../parser/lexer.mbt)

**Data Structures**:

```moonbit
pub struct TokenCache {
  // Map source ranges to cached token arrays
  cache : @immut/hashmap.HashMap[CacheKey, CachedTokens]
  mut version : Int  // Incremented on each edit
}

struct CacheKey {
  source_hash : Int  // Hash of source content
  start : Int
  end : Int
} derive(Eq, Hash)

struct CachedTokens {
  tokens : Array[TokenInfo]
  version : Int  // Version when cached
}
```

**Algorithm**:

1. **On tokenize with cache**:
   - Check if range is cached and valid
   - If cached: return cached tokens (adjusting positions if needed)
   - If not cached: tokenize and cache result

2. **On edit**:
   - Invalidate cache entries overlapping edit range
   - Keep entries before and after edit (adjust positions)
   - Increment version

3. **Cache management**:
   - Bounded size (evict old entries)
   - LRU or recency-based eviction

**Implementation Steps**:

1. Create `TokenCache` structure
2. Add `tokenize_with_cache(source, cache, start, end)` function
3. Implement cache invalidation on edits
4. Add position adjustment for cached tokens

**Validation**: Tokenization produces same results with/without cache.

---

### Phase 3: Implement Parse Tree Caching and Damage Tracking

**Objective**: Cache parse subtrees and identify which parts need reparsing after edits.

**Files to Create**:
- `parser/parse_cache.mbt`
- `parser/edit.mbt`
- `parser/damage.mbt`

**Data Structures**:

```moonbit
// Represents an edit to the source
pub struct Edit {
  start : Int       // Start position in old source
  old_end : Int     // End position in old source
  new_end : Int     // End position in new source
  // Derived:
  deleted_length : Int  // old_end - start
  inserted_length : Int // new_end - start
}

// Tracks damaged (needs reparsing) ranges
pub struct DamageTracker {
  damaged_ranges : Array[Range]  // Sorted, non-overlapping ranges
}

struct Range {
  start : Int
  end : Int
} derive(Eq, Show)

// Caches parse results by token range
pub struct ParseCache {
  cache : @immut/hashmap.HashMap[ParseCacheKey, CachedNode]
  mut version : Int
}

struct ParseCacheKey {
  token_fingerprint : Int  // Hash of token sequence
  start_token : Int        // Token array index
  end_token : Int
} derive(Eq, Hash)

struct CachedNode {
  node : TermNode
  version : Int
}
```

**Wagner-Graham Damage Tracking Algorithm**:

1. **Initialize damage tracker** with edit range:
   ```moonbit
   let damage = DamageTracker::new(edit)
   ```

2. **Expand damage based on parse tree**:
   - Start at edited range
   - Walk up parse tree to find "stable boundaries"
   - Stable boundary = node whose children are all before/after edit
   - Damage includes all nodes that overlap or contain edit

3. **Identify reusable subtrees**:
   - Nodes completely outside damaged range can be reused
   - Nodes with children in both damaged and undamaged regions need reparsing
   - Leaf nodes in damaged range must be reparsed

**Implementation Steps**:

1. **Edit tracking**:
   ```moonbit
   pub fn Edit::new(start: Int, old_end: Int, new_end: Int) -> Edit
   pub fn Edit::apply_to_position(self, pos: Int) -> Int
   ```

2. **Damage tracking**:
   ```moonbit
   pub fn DamageTracker::new(edit: Edit) -> DamageTracker
   pub fn DamageTracker::expand_for_tree(self, tree: TermNode) -> Unit
   pub fn DamageTracker::is_damaged(self, range: Range) -> Bool
   ```

3. **Parse cache**:
   ```moonbit
   pub fn ParseCache::new() -> ParseCache
   pub fn ParseCache::get(self, key: ParseCacheKey) -> TermNode?
   pub fn ParseCache::insert(self, key: ParseCacheKey, node: TermNode)
   pub fn ParseCache::invalidate_range(self, range: Range)
   ```

**Validation**: Damage tracking correctly identifies affected ranges.

---

### Phase 4: Implement Incremental Re-parsing

**Objective**: Reparse only damaged regions, reusing cached subtrees.

**Files to Create**:
- `parser/incremental_parser.mbt`

**Files to Modify**:
- [parser/parser.mbt](../parser/parser.mbt)

**Data Structures**:

```moonbit
pub struct IncrementalParser {
  source : String
  tree : TermNode?           // Current parse tree
  token_cache : TokenCache
  parse_cache : ParseCache
  mut node_id_counter : Int
}
```

**Wagner-Graham Incremental Parsing Algorithm**:

1. **On initialization**:
   ```moonbit
   let parser = IncrementalParser::new(source)
   let tree = parser.parse()  // Initial full parse
   ```

2. **On edit**:
   ```moonbit
   pub fn IncrementalParser::edit(
     self,
     edit: Edit,
     new_source: String
   ) -> TermNode {
     // Step 1: Update source
     self.source = new_source

     // Step 2: Adjust old tree positions
     let adjusted_tree = self.adjust_tree_positions(self.tree, edit)

     // Step 3: Identify damaged range
     let damage = DamageTracker::new(edit)
     damage.expand_for_tree(adjusted_tree)

     // Step 4: Invalidate caches in damaged range
     self.token_cache.invalidate_range(damage.range())
     self.parse_cache.invalidate_range(damage.range())

     // Step 5: Reparse damaged region
     let new_tree = self.reparse_with_reuse(
       adjusted_tree,
       damage,
       edit.start,
       edit.new_end
     )

     self.tree = new_tree
     new_tree
   }
   ```

3. **Position adjustment** (from Wagner-Graham):
   ```moonbit
   fn adjust_tree_positions(
     tree: TermNode,
     edit: Edit
   ) -> TermNode {
     // Recursively update node positions based on edit
     if tree.end <= edit.start {
       // Node is before edit, no change
       tree
     } else if tree.start >= edit.old_end {
       // Node is after edit, shift by delta
       let delta = edit.inserted_length - edit.deleted_length
       tree.with_positions(tree.start + delta, tree.end + delta)
     } else {
       // Node overlaps edit, mark as damaged
       tree.with_damaged(true)
     }
   }
   ```

4. **Reparse with reuse**:
   ```moonbit
   fn reparse_with_reuse(
     old_tree: TermNode,
     damage: DamageTracker,
     start: Int,
     end: Int
   ) -> TermNode {
     // Check if this range is damaged
     if not damage.is_damaged(Range::new(start, end)) {
       // Reuse cached node
       return old_tree
     }

     // Check parse cache
     match self.parse_cache.get_for_range(start, end) {
       Some(cached) => return cached
       None => ()
     }

     // Must reparse this region
     let tokens = self.tokenize_range(start, end)
     let node = self.parse_tokens(tokens, start, end)

     // Cache result
     self.parse_cache.insert(node)

     node
   }
   ```

**Implementation Steps**:

1. Create `IncrementalParser` structure
2. Implement `parse()` for initial full parse
3. Implement `edit()` for incremental updates
4. Implement position adjustment algorithm
5. Implement reparse with cache checking
6. Add helper methods for range-based parsing

**Validation**: Incremental edits produce same tree as full reparse.

---

### Phase 5: Error Recovery

**Objective**: Continue parsing after errors, return partial trees with error nodes.

**Files to Modify**:
- [parser/parser.mbt](../parser/parser.mbt)
- [parser/term.mbt](../parser/term.mbt)

**Error Recovery Strategies**:

1. **Error nodes in AST** (already added in Phase 1):
   ```moonbit
   TermKind::Error(String)  // Error message
   ```

2. **Panic mode recovery**:
   - On parse error, skip tokens until synchronization point
   - Synchronization points: `;`, newline, closing `)`
   - Insert error node in tree
   - Continue parsing from sync point

3. **Error recovery points**:
   ```moonbit
   fn parse_with_recovery(
     parser: Parser,
     parse_fn: (Parser) -> (Parser, TermNode) raise
   ) -> (Parser, TermNode) {
     try {
       parse_fn(parser)
     } catch {
       ParseError((msg, token)) => {
         // Create error node
         let error_node = TermNode::error(msg, parser.position)

         // Advance to sync point
         let parser = skip_to_sync_point(parser)

         (parser, error_node)
       }
     }
   }
   ```

4. **Synchronization points** for Lambda Calculus:
   - After `)` (closing parenthesis)
   - Before λ/\ (new lambda)
   - Before `if` (new conditional)
   - At EOF

**Implementation Steps**:

1. Add `TermNode::error()` constructor
2. Implement `skip_to_sync_point()`
3. Wrap parse functions with error recovery
4. Add tests for error recovery

**Validation**: Parser continues after errors, produces partial trees.

---

### Phase 6: CRDT Integration

**Objective**: Integrate incremental parser with CRDT TreeDocument.

**Files to Create**:
- `parser/crdt_integration.mbt`

**Files to Modify**:
- `editor/tree_document.mbt` (from CST integration plan)

**Integration Architecture**:

```moonbit
pub struct ParsedDocument {
  crdt_doc : TreeDocument      // CRDT document
  parser : IncrementalParser   // Incremental parser
  source : String              // Current source text
}
```

**CRDT Integration Algorithm**:

1. **Initialize parsed document**:
   ```moonbit
   pub fn ParsedDocument::new(source: String, agent_id: String) -> ParsedDocument {
     // Parse initial source
     let parser = IncrementalParser::new(source)
     let ast = parser.parse()

     // Convert AST to CRDT tree
     let crdt_doc = TreeDocument::new(agent_id)
     let root = ast_to_crdt(crdt_doc, ast)

     { crdt_doc, parser, source }
   }
   ```

2. **Apply local edit**:
   ```moonbit
   pub fn ParsedDocument::edit(
     self,
     edit: Edit,
     new_source: String
   ) -> Array[Op] {
     // Update source
     self.source = new_source

     // Incrementally reparse
     let new_ast = self.parser.edit(edit, new_source)

     // Convert AST changes to CRDT operations
     let ops = ast_diff_to_crdt_ops(self.crdt_doc, new_ast)

     ops
   }
   ```

3. **Apply remote operations**:
   ```moonbit
   pub fn ParsedDocument::apply_remote(
     self,
     ops: Array[Op]
   ) -> Unit {
     // Apply CRDT operations
     self.crdt_doc.merge_remote(ops, [])

     // Reconstruct source from CRDT tree
     self.source = crdt_to_source(self.crdt_doc)

     // Reparse (could optimize to use CRDT structure)
     let ast = self.parser.parse_full(self.source)
   }
   ```

4. **AST to CRDT conversion**:
   ```moonbit
   fn ast_to_crdt(
     doc: TreeDocument,
     ast: TermNode,
     parent_lv: Int = -1
   ) -> Int {
     // Create CRDT node for AST node
     let lv = doc.insert_child(
       parent_lv,
       0,
       term_kind_to_string(ast.kind),
       ast.text_value()
     )

     // Set attributes
     let attrs = term_to_attributes(ast)
     doc.update_attributes(lv, attrs)

     // Recursively convert children
     for child in ast.children {
       ast_to_crdt(doc, child, lv)
     }

     lv
   }
   ```

**Mapping Strategy**:

- **AST TermKind** → **CRDT node_type**:
  - `Int(n)` → `"int_literal"`, text_value = n.to_string()
  - `Var(name)` → `"variable"`, text_value = name
  - `Lam(param)` → `"lambda"`, attributes["param"] = param
  - `App` → `"application"`
  - `Bop(op)` → `"binary_op"`, attributes["op"] = op
  - `If` → `"if_expr"`
  - `Error(msg)` → `"error"`, text_value = msg

- **Position tracking**: Store `start` and `end` as CRDT attributes

**Implementation Steps**:

1. Create `ParsedDocument` structure
2. Implement `ast_to_crdt()` conversion
3. Implement `crdt_to_source()` reconstruction
4. Implement AST diffing for incremental CRDT updates
5. Add tests for CRDT synchronization

**Validation**: CRDT trees stay synchronized across replicas with incremental parsing.

---

### Phase 7: Optimization and Performance

**Objective**: Optimize parser performance for real-time editing.

**Optimizations**:

1. **Parallel tokenization**:
   - Tokenize unchanged regions in parallel
   - Use work-stealing for token cache lookups

2. **Lazy subtree expansion**:
   - Don't parse entire file initially
   - Parse visible regions first
   - Parse on-demand for code folding, navigation

3. **Cache tuning**:
   - Adjust cache sizes based on document size
   - Profile cache hit rates
   - Implement cache eviction policies

4. **Position indexing**:
   - Build position → node index
   - Enable O(log n) node lookup by position
   - Use for cursor position → AST node queries

5. **Incremental tokenization**:
   - Don't re-tokenize entire damaged range
   - Tokenize only new/changed text
   - Splice token arrays

**Implementation Steps**:

1. Add performance benchmarks
2. Profile hot paths
3. Implement targeted optimizations
4. Measure cache effectiveness

**Validation**: Parser handles real-time editing (< 16ms for typical edits).

---

## Implementation Phases Summary

| Phase | Objective | Complexity |
|-------|-----------|------------|
| 1 | Source tracking & node identity | Medium |
| 2 | Token cache | Medium |
| 3 | Parse cache & damage tracking | High |
| 4 | Incremental re-parsing | High |
| 5 | Error recovery | Medium |
| 6 | CRDT integration | Medium-High |
| 7 | Optimization | Medium |

---

## Critical Files

### Must Create
1. `parser/token_cache.mbt` - Token caching
2. `parser/parse_cache.mbt` - Parse result caching
3. `parser/edit.mbt` - Edit representation
4. `parser/damage.mbt` - Damage tracking
5. `parser/incremental_parser.mbt` - Main incremental parser
6. `parser/crdt_integration.mbt` - CRDT integration

### Must Modify
7. `parser/term.mbt` - Add positioned nodes, error nodes
8. `parser/token.mbt` - Add TokenInfo with positions
9. `parser/lexer.mbt` - Track positions, support caching
10. `parser/parser.mbt` - Error recovery, cache integration
11. `editor/tree_document.mbt` - CRDT integration (from CST plan)

---

## Testing Strategy

### Unit Tests

1. **Position tracking**:
   - Verify nodes have correct source positions
   - Test position adjustment after edits

2. **Token cache**:
   - Cache hits for unchanged regions
   - Cache invalidation on edits
   - Position adjustment for cached tokens

3. **Damage tracking**:
   - Correct damage range identification
   - Stable boundary detection
   - Damage expansion algorithm

4. **Incremental parsing**:
   - Same result as full reparse
   - Correct tree reuse
   - Position consistency

5. **Error recovery**:
   - Partial trees with error nodes
   - Continued parsing after errors
   - Sync point detection

### Integration Tests

1. **Edit sequences**:
   - Series of edits produce correct final tree
   - Cumulative position adjustments

2. **CRDT synchronization**:
   - Two replicas with different edit sequences converge
   - Parse trees stay consistent

3. **Performance**:
   - Incremental parse < 16ms for typical edits
   - Cache hit rate > 80% for realistic editing
   - Memory usage bounded

### Property-Based Tests

1. **Incremental = Full parse**:
   - For any edit sequence, incremental result = full reparse

2. **Position invariants**:
   - All nodes have valid positions
   - Child positions within parent positions
   - No overlapping siblings

---

## References

- **Wagner & Graham (1998)**: [Efficient and Flexible Incremental Parsing](https://dl.acm.org/doi/10.1145/293677.293678)
- **Tree-sitter**: [GitHub repository](https://github.com/tree-sitter/tree-sitter) - practical implementation
- **Strumenta article**: [Incremental Parsing Using Tree-sitter](https://tomassetti.me/incremental-parsing-using-tree-sitter/)

---

## Future Enhancements

1. **GLR support**: Handle ambiguous grammars like Tree-sitter
2. **Concrete syntax tree**: Preserve whitespace, comments
3. **Language Server Protocol**: Expose via LSP for IDE integration
4. **Streaming edits**: Handle multiple concurrent edits
5. **Persistent data structures**: Use rope for source text
6. **Query language**: Tree-sitter style syntax queries

---

## Success Criteria

1. ✓ Parser handles incremental edits in < 16ms
2. ✓ Cache hit rate > 80% for typical editing patterns
3. ✓ Error recovery produces usable partial trees
4. ✓ CRDT trees stay synchronized across replicas
5. ✓ Memory usage scales with document size
6. ✓ Same correctness as full reparse

---

**Estimated Complexity**: High (major architectural change)
**Risk Level**: Medium (well-understood algorithm, clear references)
**Innovation**: Combining incremental parsing with CRDT for collaborative editing
