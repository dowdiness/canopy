// Scope annotation for binder coloring in the tree view.
// Rabbita-local — does not modify ViewNode (framework genericity contract).
//
// Architecture:
//   build_scope_map(editor) → Map[NodeId, ScopeAnnotation]
//     Uses walk_scope: a single recursive walk over the ProjNode tree with
//     a scope stack, following the same scoping rules as free_vars.mbt:
//       - Module defs: sequential scope (each def visible to subsequent defs + body)
//       - Lam params: lexical scope (visible in the body)
//       - Nested blocks: handled naturally by the scope stack
//     No dependency on FlatProj or resolve_binder.
//
//   compute_highlight_set(selected_id, scope_map) → HashSet[NodeId]
//     Given a clicked/navigated node, returns the set of NodeIds to highlight:
//     binder + all its usages. Uniform for both lambda and module bindings.
//
//   backfill_usages(scope_map)
//     Second pass: for each Var → binder link, adds the Var to the binder's
//     usage_ids list. This enables binder → usages lookup in highlight_set.
//
// Data flow:
//   ProjNode tree → walk_scope (scope stack) → scope_map → view_outline_node
//                                                        → compute_highlight_set

///|
/// Annotation for one node: its binder, whether it's a definition site,
/// deterministic color, and (for binders) the list of usage NodeIds.
struct ScopeAnnotation {
  binder_id : @canopy_core.NodeId?
  is_definition : Bool
  color_index : Int
  usage_ids : Array[@canopy_core.NodeId]
}

///|
/// Deterministic color index from binder name. Stable across edits.
/// Returns a value in 0..7 (8-hue palette).
fn binder_color_index(name : String) -> Int {
  let mut h = 0
  for ch in name {
    h = h * 31 + ch.to_int()
  }
  if h < 0 {
    h = -h
  }
  h % 8
}

///|
/// A scope entry: a name bound to a binder NodeId.
struct ScopeEntry {
  name : String
  binder_node_id : @canopy_core.NodeId
  binder_name : String
}

///|
/// Build scope_map by walking the ProjNode tree with a scope stack.
/// Follows the same scoping rules as free_vars: sequential scope for Module
/// defs, lexical scope for Lam params. Handles nested blocks correctly.
fn build_scope_map(
  editor : @editor.SyncEditor[@ast.Term],
) -> Map[@canopy_core.NodeId, ScopeAnnotation] {
  let scope_map : Map[@canopy_core.NodeId, ScopeAnnotation] = {}
  let proj_root = match editor.get_proj_node() {
    Some(r) => r
    None => return scope_map
  }
  // Walk the ProjNode tree with an empty scope stack
  let scope : Array[ScopeEntry] = []
  walk_scope(proj_root, scope, scope_map)
  // Backfill: for each var that points to a binder, add var to binder's usage_ids
  backfill_usages(scope_map)
  scope_map
}

///|
/// Recursive walk over ProjNode tree, maintaining a scope stack.
/// For each Var, looks up the name in the scope stack (innermost first).
/// For each Lam, pushes the param onto the scope stack.
/// For Module, pushes defs in sequential scope order.
fn walk_scope(
  node : @canopy_core.ProjNode[@ast.Term],
  scope : Array[ScopeEntry],
  scope_map : Map[@canopy_core.NodeId, ScopeAnnotation],
) -> Unit {
  let node_id = node.id()
  match node.kind {
    Var(name) => {
      // Look up name in scope stack (last = innermost)
      let mut i = scope.length() - 1
      while i >= 0 {
        if scope[i].name == name {
          let entry = scope[i]
          scope_map[node_id] = {
            binder_id: Some(entry.binder_node_id),
            is_definition: false,
            color_index: binder_color_index(entry.binder_name),
            usage_ids: [],
          }
          break
        }
        i = i - 1
      }
      // If not found, it's a free variable — no annotation
    }
    Lam(param_name, _) => {
      // Register the Lam as a definition site
      let cidx = binder_color_index(param_name)
      scope_map[node_id] = {
        binder_id: Some(node_id),
        is_definition: true,
        color_index: cidx,
        usage_ids: [],
      }
      // Push param onto scope and walk children
      scope.push({ name: param_name, binder_node_id: node_id, binder_name: param_name })
      for child in node.children {
        walk_scope(child, scope, scope_map)
      }
      let _ = scope.unsafe_pop()
      return // Already walked children
    }
    Module(defs, _) => {
      // Sequential scope: each def is visible to subsequent defs and the body.
      // Children are [init_0, init_1, ..., body].
      // defs[i] corresponds to children[i].
      let initial_scope_len = scope.length()
      for i, child in node.children {
        if i < defs.length() {
          // Walk the init expression BEFORE pushing this def's name
          // (a def's init can't reference itself — sequential scope)
          walk_scope(child, scope, scope_map)
          // Push the def name for subsequent defs and the body.
          // Use a synthetic NodeId for the module-def binder to avoid
          // collision with the init expression's own NodeId (which may
          // be a Lam that has its own lambda-binder annotation).
          let def_name = defs[i].0
          let def_binder_id = @canopy_core.NodeId::from_int(
            -(child.node_id + 1),
          )
          scope.push({
            name: def_name,
            binder_node_id: def_binder_id,
            binder_name: def_name,
          })
          // Register synthetic binder as a definition site
          scope_map[def_binder_id] = {
            binder_id: Some(def_binder_id),
            is_definition: true,
            color_index: binder_color_index(def_name),
            usage_ids: [],
          }
        } else {
          // Body expression — all defs are in scope
          walk_scope(child, scope, scope_map)
        }
      }
      // Pop all defs we pushed
      while scope.length() > initial_scope_len {
        let _ = scope.unsafe_pop()
      }
      return // Already walked children
    }
    _ => ()
  }
  // Default: walk children (for App, Bop, If, etc.)
  for child in node.children {
    walk_scope(child, scope, scope_map)
  }
}

///|
/// Second pass: for each Var that points to a binder,
/// add the Var's NodeId to the binder's usage_ids.
fn backfill_usages(scope_map : Map[@canopy_core.NodeId, ScopeAnnotation]) -> Unit {
  let pairs : Array[(@canopy_core.NodeId, @canopy_core.NodeId)] = []
  for node_id, ann in scope_map {
    if !ann.is_definition {
      match ann.binder_id {
        Some(bid) => pairs.push((node_id, bid))
        None => ()
      }
    }
  }
  for pair in pairs {
    let (var_id, binder_id) = pair
    match scope_map.get(binder_id) {
      Some(binder_ann) =>
        if binder_ann.is_definition {
          binder_ann.usage_ids.push(var_id)
        }
      None => ()
    }
  }
}

///|
/// Compute the set of NodeIds to highlight when a node is selected.
/// Returns empty set for non-identifiers (clear highlights).
fn compute_highlight_set(
  selected_id : @canopy_core.NodeId,
  scope_map : Map[@canopy_core.NodeId, ScopeAnnotation],
) -> @immut/hashset.HashSet[@canopy_core.NodeId] {
  let mut hs = @immut/hashset.HashSet::new()
  match scope_map.get(selected_id) {
    None => hs
    Some(ann) => {
      // Include the binder and all its usages
      match ann.binder_id {
        Some(bid) => {
          hs = hs.add(bid)
          match scope_map.get(bid) {
            Some(binder_ann) =>
              for uid in binder_ann.usage_ids {
                hs = hs.add(uid)
              }
            None => ()
          }
        }
        None => ()
      }
      // If this IS a binder, include self + usages
      if ann.is_definition {
        hs = hs.add(selected_id)
        for uid in ann.usage_ids {
          hs = hs.add(uid)
        }
      }
      hs
    }
  }
}
