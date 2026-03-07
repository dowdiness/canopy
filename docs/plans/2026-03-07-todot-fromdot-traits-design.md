# ToDot/FromDot Traits Design

**Date:** 2026-03-07
**Status:** Complete

## Overview

Unify the graphviz and loom/viz modules by introducing `ToDot` and `FromDot` traits in graphviz, using the graphviz `Graph` AST as the interchange format. This enables full round-trip: type -> Graph AST -> DOT string -> Graph AST -> type.

## Approach

Traits live in graphviz (Approach A). loom gains a dependency on graphviz. loom/viz's hand-built DOT string construction is replaced by AST construction through the graphviz parser package.

## Trait Definitions

In `graphviz/lib/parser`, alongside the `Graph` AST:

```moonbit
pub(open) trait ToDot {
  to_graph(Self) -> Graph
}

pub(open) trait FromDot {
  from_graph(Graph) -> Self?
}
```

Convenience functions:

```moonbit
pub fn to_dot_string[T : ToDot](value : T) -> String {
  format_graph(value.to_graph())
}

pub fn from_dot_string[T : FromDot](dot : String) -> T? {
  let graph = parse_dot(dot)?
  T::from_graph(graph)
}
```

## Round-Trip Pipeline

```
Type --[DotNode/ToDot]--> Graph AST --[format_graph]--> DOT String
DOT String --[parse_dot]--> Graph AST --[FromDot]--> DotTreeNode/Type
                                      --[compute_layout]--> GraphLayout --[render_svg]--> SVG
```

## loom/viz Refactoring

Keep `DotNode` as the user-facing trait for tree structures:

```moonbit
pub(open) trait DotNode {
  node_id(Self) -> Int
  label(Self) -> String
  node_attrs(Self) -> String
  children(Self) -> Array[Self]
  edge_label(Self, Int) -> String
}
```

Refactor `to_dot` to go through the graphviz AST:

```moonbit
pub fn to_graph[T : DotNode](root : T) -> @graphviz/lib/parser.Graph {
  // Walk DotNode tree, build Graph AST with Statement nodes + edges
}

pub fn to_dot[T : DotNode](root : T) -> String {
  @graphviz/lib/parser.format_graph(to_graph(root))
}
```

Dark-theme styling (node colors, font) becomes graph/node attributes in the AST instead of hardcoded string concatenation.

## FromDot: DotTreeNode

A concrete round-trip type for tree structures:

```moonbit
pub struct DotTreeNode {
  id : String
  label : String
  attrs : Map[String, String]
  children : Array[DotTreeNode]
  edge_labels : Array[String]
}
```

```moonbit
pub fn from_graph(graph : @graphviz/lib/parser.Graph) -> DotTreeNode? {
  // 1. Collect node IDs + attributes from NodeStmt
  // 2. Collect edges from EdgeStmt (with edge labels)
  // 3. Find root (node with no incoming edges)
  // 4. Build tree recursively from root
}
```

`DotTreeNode` implements both `DotNode` (re-export to DOT) and `FromDot` (import from DOT).

`FromDot` for domain types (like lambda's `Term`) is inherently lossy -- a DOT graph doesn't preserve semantic information like variable binding. Best-effort reconstruction from what the graph encodes.

## Lambda Module Integration

Replace hand-built DOT strings with `DotNode` trait implementation:

```moonbit
pub impl @viz.DotNode for Term with label(self) {
  match self {
    Int(n) => "Int(\{n})"
    Var(s) => "Var(\{s})"
    Lam(s, _) => "Lam(\{s})"
    App(_, _) => "App"
    Bop(op, _, _) => "Bop(\{op})"
    If(_, _, _) => "If"
    Let(s, _, _) => "Let(\{s})"
    Unit => "Unit"
    Error(msg) => "Error(\{msg})"
  }
}
// + node_id, children, node_attrs, edge_label implementations
```

`term_to_dot` becomes a thin wrapper:

```moonbit
pub fn term_to_dot(term : Term) -> String {
  @viz.to_dot(term)
}
```

## Dependency Changes

```
loom/loom/moon.mod.json:     add "antisatori/graphviz": { "path": "../../graphviz" }
loom/loom/src/viz/moon.pkg.json:  add import "antisatori/graphviz/lib/parser"
```

No changes to crdt's moon.mod.json or graphviz's moon.mod.json.

## What Gets Deleted

- ~90 lines of hand-built DOT string construction in `loom/viz/ast_to_dot.mbt`
- ~60 lines of duplicated DOT construction in `lambda/dot_node.mbt`
- `escape_dot_label` helper (graphviz's `format_graph` handles escaping)

## What's Preserved

- `DotNode` trait API (callers unaffected)
- `to_dot[T : DotNode](T) -> String` signature unchanged
- `term_to_dot` public function (becomes thin wrapper)
- Dark-theme styling (encoded as attributes in AST)
