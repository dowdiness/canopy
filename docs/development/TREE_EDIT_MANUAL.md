# Tree Editing Manual

This manual describes the structural operations available in the projectional tree editor. All structural edits round-trip through the text CRDT to ensure collaborative consistency.

## Overview

The tree editor provides a way to manipulate the Lambda Calculus AST directly. Each action corresponds to a `TreeEditOp` in the `projection` package.

## Commands Reference

### Selection & Navigation
These operations do not modify the document text.
- **Select (`node_id`)**: Set the active selection to a single node.
- **SelectRange (`start_id`, `end_id`)**: Select a contiguous range of nodes (preorder traversal).
- **Collapse/Expand (`node_id`)**: Toggles the visibility of a subtree in the UI.

### Inline Editing
- **StartEdit (`node_id`)**: Activate the inline text box for a node.
- **CommitEdit (`node_id`, `new_value`)**: Parse the `new_value` and replace the node's content.
  - If `new_value` is a valid expression (e.g., `(x) => x`), the node is replaced by the resulting subtree.
- **CancelEdit**: Exit inline editing without saving changes.

### Structural Refactoring
These operations are planned by the language edit port as typed `SpanEdit`
patches. The generic `Language::apply_edit` path applies those patches through
the text CRDT and then refreshes the projection.

- **Delete (`node_id`)**: Remove a node from the tree.
  - *Example:* Deleting `x` from `f x` results in `f`.
- **WrapInLambda (`node_id`, `var_name`)**: Wrap the selected node in a new lambda abstraction.
  - *Example:* Wrapping `42` with `x` results in `(x) => 42`.
- **WrapInApp (`node_id`)**: Wrap the selected node as the function in an application with a placeholder argument `a`.
  - *Example:* Wrapping `f` results in `(f a)`.
- **InsertChild (`parent_id`, `index`, `kind`)**: Insert a new node of a specific `kind` (e.g., `Int`, `Var`, `Lam`) as a child of the parent.

### Drag and Drop
- **StartDrag (`node_id`)**: Initiate a move operation.
- **DragOver (`target_id`, `position`)**: Preview the drop location (`Before`, `After`, or `Inside`).
- **Drop (`source_id`, `target_id`, `position`)**: Compute and apply a language-owned move.
  - Root-module `LetDef` rows move as complete rows with newline-aware separators.
  - Expression pairs use expression-level move semantics; `Inside` exchanges
    their contents.
  - Mixed `LetDef`/expression pairs and nested binding rows are rejected with
    structured errors.

## Operational Workflow: The Edit Port

When a structural edit is performed:
1. The `TreeEditOp` is sent to the language edit port with the current source
   text, source map, registry, and projection context.
2. The language computes typed `SpanEdit` patches and an optional focus hint.
3. `Language::apply_edit` applies the patches through
   `SyncEditor::apply_span_edits`, recording the change in the CRDT and undo
   history.
4. The incremental parser reparses the text, and the `SourceMap` reconciles the
   new AST with existing `NodeId`s to preserve UI state.
