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
These operations trigger a full round-trip: they modify the ProjNode tree, unparse to text, and update the CRDT.

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
- **Drop (`source_id`, `target_id`, `position`)**: Perform the move. This effectively deletes the source and inserts it at the target location.

## Operational Workflow: The Round-Trip

When a structural edit is performed:
1.  The `TreeEditOp` is applied to the current `ProjNode` tree.
2.  The resulting `ProjNode` is unparsed back into a Lambda Calculus string.
3.  The `SyncEditor` performs a diff between the old and new text.
4.  Minimal CRDT operations are generated and applied to the `TextState`.
5.  The incremental parser reparses the text, and the `SourceMap` reconciles the new AST with existing `NodeId`s to preserve UI state.
