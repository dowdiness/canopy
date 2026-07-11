# FFI Coordinator Accessors

Exported FFI functions are boundary code. If an FFI function reads protected
editor state such as parser diagnostics, projection nodes, source maps, flat
projection memos, or other registered protected cells, read it through
`Coordinator::read_protected`.

Direct editor reads are fine inside editor-owned implementation code and tests
that intentionally inspect internals. They are not fine as the first protected
read in exported FFI accessors, because external callers can still hold stale
integer handles after the coordinator has destroyed the editor.

## Why `read_protected`

`read_protected(editor_id, cell)` is the lifecycle gate for protected editor
state:

- verifies the editor id is still registered and alive
- verifies the cell belongs to that editor's protected surface
- catches out-of-band protected-watch disposal before reading
- maps reactive cycle failures to `AbortKind::CycleDetected`
- returns an `AbortReport` with editor, cell, and agent context

By contrast, a direct read such as `h.editor.get_proj_node()` or
`h.editor.get_source_map()` bypasses those checks. After destroy, it can return
stale memoized data, trip a disposed reactive cell, or produce boundary behavior
that differs from the rest of the FFI surface.

## Boundary Pattern

Preserve API-specific parse and validation precedence first, then guard the
protected reads, then delegate to the existing implementation:

```moonbit
match handles.get(handle) {
  Some(h) => {
    let op = parse_user_input(...) // keep existing invalid-input behavior
    let root = match coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
      Ok(Some(root)) => root
      Ok(None) => return "error: no projection"
      Err(report) => {
        println("accessor_name proj read: \{report}")
        return "error: editor unavailable"
      }
    }
    let source_map = match coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
      Ok(sm) => sm
      Err(report) => {
        println("accessor_name source_map read: \{report}")
        return "error: editor unavailable"
      }
    }
    delegate(root, source_map, op)
  }
  None => "error: no editor"
}
```

The exact fallback is part of each exported API's compatibility contract:

- diagnostics and patch arrays usually collapse to `"[]"`.
- JSON tree/projection accessors usually collapse to `"null"`.
- text exports may collapse to `""`.
- edit/action APIs usually return their existing `"error: ..."` shape.

Do not widen the public error model just to expose coordinator reports. Log the
report for debugging and preserve the FFI API's existing fail-closed response
unless a real consumer needs structured lifecycle errors.

## Current Scope

The Phase 1b accessor migration covers the exported Lambda, JSON, and Markdown
FFI paths that consult registered protected cells before producing diagnostics,
views, projections, source maps, semantic overlays, or structural edits.

Remaining direct reads in whitebox tests are intentional: those tests often need
node ids or internal state to set up assertions. For new production FFI exports,
start from the boundary pattern above.
