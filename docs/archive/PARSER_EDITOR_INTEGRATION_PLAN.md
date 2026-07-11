# Parser-CRDT Editor Integration Plan

## Overview

Integrate the incremental Wagner-Graham parser with the CRDT text editor to enable **collaborative Lambda Calculus code editing** with synchronized parse trees across replicas.

## Status: Incremental Parser Complete ✅

The incremental parser implementation (Phases 1-6) is **complete** with 125 tests passing:
- ✅ Source position tracking and node identity
- ✅ Token and parse caching
- ✅ Wagner-Graham damage tracking
- ✅ Incremental reparsing
- ✅ Error recovery with partial trees
- ✅ Conceptual CRDT integration (AST ↔ CRDT conversion)

**Missing**: Integration with the actual CRDT editor system.

## Requirements

**Goals:**
- **Integration Level**: Full CST integration (long-term), pragmatic prototype (short-term)
- **Use Case**: Collaborative code editing with conflict resolution
- **Compatibility**: Maintain backward compatibility with existing Editor API

## Current Architecture Analysis

### Parser System (`parser/`)
- **IncrementalParser**: Wagner-Graham algorithm with O(damaged region) reparsing
- **AST**: TermNode with positions, node IDs, error recovery
- **CRDT Integration**: `crdt_integration.mbt` with AST ↔ CRDTNode conversion
- **Performance**: Sub-microsecond parsing (benchmarked)

### Editor System (`editor/`)
- **Editor**: User-facing API with cursor tracking
- **Document**: Orchestrates FugueTree + OpLog + CausalGraph
- **FugueTree**: Sequence CRDT with FugueMax ordering
- **Text-focused**: Position-based insert/delete operations

### Gap
Parser and editor are **separate systems**. Parser has conceptual CRDT conversion but doesn't connect to actual FugueTree/OpLog/CausalGraph infrastructure.

## Pragmatic Integration Strategy

### Architecture Decision: **Wrapper Pattern**

Create `ParsedEditor` that wraps both `Editor` (CRDT text) and `IncrementalParser` (AST):

```
┌──────────────────────────────────────┐
│        ParsedEditor (NEW)             │
├──────────────────────────────────────┤
│  editor: Editor  │  parser: Parser   │
│  (CRDT text)     │  (AST)            │
├──────────────────────────────────────┤
│  Synchronization via text diffing     │
└──────────────────────────────────────┘
```

**Rationale:**
- **Backward compatible**: Editor API unchanged
- **Simple**: No modifications to FugueTree or OpLog
- **Evolvable**: Can migrate to full CST later
- **Fast to implement**: Minimal changes required

### Synchronization Strategy: **Text Diff + Incremental Reparse**

**After local edit:**
1. Editor.insert/delete updates CRDT text
2. Set `parse_dirty = true`
3. On `get_ast()`: compute Edit from old→new text, incrementally reparse

**After remote merge:**
1. Editor.merge_remote updates CRDT text
2. Set `parse_dirty = true`
3. On `get_ast()`: compute Edit from old→new text, incrementally reparse

**Key Insight:** Use text convergence (guaranteed by CRDT) as synchronization point, then parse converged text.

## Implementation Phases

### Phase 1: Text Diffing Utility

**Create:** `editor/text_diff.mbt`

**Purpose:** Compute `Edit` from old/new text for incremental reparsing.

**Key Function:**
```moonbit
pub fn compute_edit(old_text : String, new_text : String) -> @parser.Edit {
  // Find longest common prefix
  let prefix_len = find_common_prefix(old_text, new_text)

  // Find longest common suffix
  let old_suffix = old_text[prefix_len:]
  let new_suffix = new_text[prefix_len:]
  let suffix_len = find_common_suffix(old_suffix, new_suffix)

  @parser.Edit::new(
    start: prefix_len,
    old_end: old_text.length() - suffix_len,
    new_end: new_text.length() - suffix_len
  )
}

fn find_common_prefix(s1 : String, s2 : String) -> Int {
  let mut i = 0
  let min_len = if s1.length() < s2.length() { s1.length() } else { s2.length() }
  while i < min_len && s1[i] == s2[i] {
    i = i + 1
  }
  i
}

fn find_common_suffix(s1 : String, s2 : String) -> Int {
  let mut i = 0
  let len1 = s1.length()
  let len2 = s2.length()
  let min_len = if len1 < len2 { len1 } else { len2 }
  while i < min_len && s1[len1 - 1 - i] == s2[len2 - 1 - i] {
    i = i + 1
  }
  i
}
```

**Testing:**
- Insert at start: `"abc" → "xabc"` ⇒ `Edit(0, 0, 1)`
- Insert at end: `"abc" → "abcx"` ⇒ `Edit(3, 3, 4)`
- Delete: `"abc" → "ac"` ⇒ `Edit(1, 2, 1)`
- Replace: `"abc" → "aXc"` ⇒ `Edit(1, 2, 2)`

### Phase 2: ParsedEditor Wrapper

**Create:** `editor/parsed_editor.mbt`

**Structure:**
```moonbit
pub struct ParsedEditor {
  editor : Editor                    // CRDT text editor
  parser : @parser.IncrementalParser // Incremental parser
  mut ast : @parser.TermNode?        // Cached AST
  mut parse_dirty : Bool             // Reparse needed?
  mut cached_text : String           // For computing Edit
}

pub fn ParsedEditor::new(agent_id : String) -> ParsedEditor {
  let editor = Editor::new(agent_id)
  let parser = @parser.IncrementalParser::new("")
  {
    editor,
    parser,
    ast: None,
    parse_dirty: true,
    cached_text: ""
  }
}

// Pass-through editing (mark dirty)
pub fn ParsedEditor::insert(self : ParsedEditor, text : String) -> Unit {
  self.editor.insert(text)
  self.parse_dirty = true
}

pub fn ParsedEditor::delete(self : ParsedEditor) -> Bool {
  let result = self.editor.delete()
  if result { self.parse_dirty = true }
  result
}

pub fn ParsedEditor::backspace(self : ParsedEditor) -> Bool {
  let result = self.editor.backspace()
  if result { self.parse_dirty = true }
  result
}

// Lazy AST access
pub fn ParsedEditor::get_ast(self : ParsedEditor) -> @parser.TermNode raise {
  if self.parse_dirty {
    self.reparse()
  }
  match self.ast {
    Some(ast) => ast
    None => abort("No valid parse tree")
  }
}

// Incremental reparse using text diff
fn ParsedEditor::reparse(self : ParsedEditor) -> Unit raise {
  let old_text = self.cached_text
  let new_text = self.editor.get_text()

  if old_text.length() == 0 {
    // Initial parse
    let ast = self.parser.parse()
    self.ast = Some(ast)
  } else {
    // Incremental reparse
    let edit = compute_edit(old_text, new_text)
    let ast = self.parser.edit(edit, new_text)
    self.ast = Some(ast)
  }

  self.cached_text = new_text
  self.parse_dirty = false
}

// Merge with automatic reparse
pub fn ParsedEditor::merge_remote(
  self : ParsedEditor,
  ops : Array[@oplog.Op],
  frontier : Array[Int]
) -> Unit {
  self.editor.merge_remote(ops, frontier)
  self.parse_dirty = true
}

// Helper methods
pub fn ParsedEditor::get_text(self : ParsedEditor) -> String {
  self.editor.get_text()
}

pub fn ParsedEditor::is_parse_valid(self : ParsedEditor) -> Bool {
  match self.ast {
    Some(ast) => not @parser.has_errors(ast)
    None => false
  }
}

pub fn ParsedEditor::get_operations(self : ParsedEditor) -> Array[@oplog.Op] {
  self.editor.document.oplog.operations
}

pub fn ParsedEditor::get_frontier(self : ParsedEditor) -> Array[Int] {
  self.editor.document.oplog.graph.frontier
}
```

### Phase 3: Collaboration Testing

**Create:** `editor/parsed_editor_test.mbt`

**Test Scenarios:**

```moonbit
test "concurrent edits converge to same AST" {
  let pe1 = ParsedEditor::new("agent1")
  let pe2 = ParsedEditor::new("agent2")

  // Initial: "x"
  pe1.insert("x")
  pe2.merge_remote(pe1.get_operations(), pe1.get_frontier())

  // Concurrent: pe1 adds " + 1", pe2 adds " - 2"
  pe1.insert(" + 1")
  pe2.insert(" - 2")

  // Merge
  pe1.merge_remote(pe2.get_operations(), pe2.get_frontier())
  pe2.merge_remote(pe1.get_operations(), pe1.get_frontier())

  // Verify text and AST convergence
  assert_eq!(pe1.get_text(), pe2.get_text())

  let ast1 = pe1.get_ast()
  let ast2 = pe2.get_ast()
  assert_eq!(@parser.print_term_node(ast1), @parser.print_term_node(ast2))
}

test "collaborative lambda editing" {
  let pe1 = ParsedEditor::new("agent1")
  let pe2 = ParsedEditor::new("agent2")

  // Agent 1 creates lambda skeleton
  pe1.insert("λx.")
  pe2.merge_remote(pe1.get_operations(), pe1.get_frontier())

  // Concurrent body edits
  pe1.insert("x + 1")
  pe2.insert("x - 1")

  // Merge and verify both valid
  pe1.merge_remote(pe2.get_operations(), pe2.get_frontier())
  pe2.merge_remote(pe1.get_operations(), pe1.get_frontier())

  assert_eq!(pe1.get_text(), pe2.get_text())
  assert!(pe1.is_parse_valid())
  assert!(pe2.is_parse_valid())
}

test "parse error handling" {
  let pe = ParsedEditor::new("agent1")
  pe.insert("λ.")  // Invalid: missing parameter

  let ast = pe.get_ast()
  inspect!(ast.kind, content="Error(_)")
}
```

### Phase 4: Public API Integration

**Modify:** `crdt.mbt`

**Add Exports:**
```moonbit
// ParsedEditor API
pub type ParsedEditor = @editor.ParsedEditor
pub type TermNode = @parser.TermNode

pub let new_parsed_editor : (String) -> ParsedEditor = @editor.ParsedEditor::new
pub let parsed_insert : (ParsedEditor, String) -> Unit = @editor.ParsedEditor::insert
pub let parsed_delete : (ParsedEditor) -> Bool = @editor.ParsedEditor::delete
pub let parsed_get_ast : (ParsedEditor) -> TermNode = @editor.ParsedEditor::get_ast
pub let parsed_get_text : (ParsedEditor) -> String = @editor.ParsedEditor::get_text
pub let parsed_merge_remote : (ParsedEditor, Array[Op], Array[Int]) -> Unit =
  @editor.ParsedEditor::merge_remote
```

**Note:** Existing Editor exports remain unchanged (backward compatible).

## Critical Files

### Files to Create (3 files)

1. **`editor/text_diff.mbt`** (~100 LOC)
   - `compute_edit()` - Compute Edit from text diff
   - `find_common_prefix()` - Find common prefix length
   - `find_common_suffix()` - Find common suffix length

2. **`editor/parsed_editor.mbt`** (~200 LOC)
   - `ParsedEditor` struct - Main integration class
   - Pass-through methods - insert, delete, backspace
   - `reparse()` - Incremental reparse after edits
   - `merge_remote()` - Handle remote operations
   - Helper methods - get_ast, is_parse_valid, etc.

3. **`editor/parsed_editor_test.mbt`** (~150 LOC)
   - Unit tests for local editing
   - Integration tests for collaboration
   - Convergence tests
   - Error handling tests

### Files to Modify (1 file)

4. **`crdt.mbt`** (add ~10 lines)
   - Export ParsedEditor types and functions
   - Maintain backward compatibility

## Performance Characteristics

**Time Complexity:**
- Local edit: O(1) dirty flag + O(damaged region) on get_ast()
- Remote merge: O(ops) CRDT + O(1) dirty flag
- Text diff: O(n) worst case, O(changed region) typical
- Incremental parse: O(damaged region) via Wagner-Graham

**Space Complexity:**
- Overhead: ~3x text size (editor text + cached text + AST)
- Acceptable for Lambda expressions

## Evolution Path to Full CST

This prototype enables **incremental migration**:

**Phase 1 (This Prototype)** ✓
- Text-based CRDT + separate AST layer
- Lazy incremental parsing
- Text convergence guarantees AST convergence

**Phase 2 (Future: CST Items)**
- Implement CST_INTEGRATION_PLAN.md Phase 1-3
- Add polymorphic Item.content: `Text | CSTNode`
- Store AST nodes as CRDT items

**Phase 3 (Future: Tree Operations)**
- Direct node insertion/deletion
- Attribute merging
- Full structural editing

**Phase 4 (Future: Advanced)**
- Schema validation
- Structural conflict resolution
- Refactoring operations

## Success Criteria

**Functional:**
- ✓ Collaborative Lambda Calculus editing works
- ✓ Parse trees stay synchronized across replicas
- ✓ Incremental parsing faster than full reparse
- ✓ Error recovery handles invalid syntax

**Quality:**
- ✓ All tests pass
- ✓ Backward compatible with Editor API
- ✓ Clean architecture for CST migration

**Performance:**
- ✓ Parse time < 100ms for typical expressions
- ✓ Merge + reparse < 200ms

## References

- **Wagner & Graham (1998)**: [Efficient and Flexible Incremental Parsing](https://dl.acm.org/doi/10.1145/293677.293678)
- **Tree-sitter**: [Incremental parsing implementation](https://github.com/tree-sitter/tree-sitter)
- **CST Integration Plan**: `docs/CST_INTEGRATION_PLAN.md` (future full integration)
- **Incremental Parser Plan**: `docs/INCREMENTAL_PARSER_PLAN.md` (completed)
