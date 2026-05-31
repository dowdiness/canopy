// Scope annotation for binder coloring in the tree view.
// Rabbita-local — does not modify ViewNode (framework genericity contract).
//
// Architecture:
//   build_scope_map(editor, companion) → Map[NodeId, ScopeAnnotation]
//     Uses the canonical lambda @scope graph as the single source of binding
//     truth. References and usage lists come from @scope.references keyed by
//     DeclId, so shadowing is handled by declaration identity rather than
//     name-only membership.
//
//   UI representation decision (scope-binder-node-id plan step 5): keep the
//     existing NodeId-keyed outline highlight model. Lambda binders use their
//     real Lam node id; module binders use stable UI-only synthetic keys because
//     module binder names still have source ranges, not outline rows.
//     Source/binding resolution still comes from @scope.
//
//   compute_highlight_set(selected_id, scope_map) → HashSet[NodeId]
//     Given a clicked/navigated node, returns the set of NodeIds to highlight:
//     binder key + all its usages. Uniform for both lambda and module bindings.
//
// Data flow:
//   FlatProj + registry + SourceMap → @scope.build → @scope.references
//     → scope_map → view_outline_node → compute_highlight_set
//   Nested block Modules are overlaid by building @scope graphs for each nested
//   Module subtree; the overlay still consumes @scope.references by DeclId and
//   does not perform name-stack resolution locally.

///|
/// Annotation for one node: its binder key, whether it's a definition site,
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
/// UI-only key for a module binder in the NodeId-keyed outline highlight map.
/// This is deliberately separate from @scope's source-location contract:
/// bindings are resolved by DeclId/@scope.references; this key only lets the
/// existing highlight data structure represent a binder that has no ProjNode.
fn module_binder_ui_key(
  module_node_id : @canopy_core.NodeId,
  def_index : Int,
) -> @canopy_core.NodeId {
  let sum = module_node_id.0 + def_index
  let pair = sum * (sum + 1) / 2 + def_index
  @canopy_core.NodeId::from_int(-(pair + 1))
}

///|
/// Convert a @scope declaration to the NodeId-compatible UI key used by the
/// outline highlight map.
fn scope_binder_ui_key(
  graph : @scope.ScopeGraph,
  decl : @scope.Decl,
) -> @canopy_core.NodeId {
  match decl.kind {
    @scope.DeclKind::LamParam(lam_id~) => lam_id
    @scope.DeclKind::ModuleDef(def_index~) =>
      module_binder_ui_key(graph.module_node_id, def_index)
  }
}

///|
/// Merge one canonical @scope graph into the UI scope_map.
fn add_scope_graph_annotations(
  scope_map : Map[@canopy_core.NodeId, ScopeAnnotation],
  graph : @scope.ScopeGraph,
) -> Unit {
  for decl in graph.decls {
    let binder_id = scope_binder_ui_key(graph, decl)
    let color_index = binder_color_index(decl.name)
    let usage_ids = @scope.references(graph, decl.id)
    scope_map[binder_id] = {
      binder_id: Some(binder_id),
      is_definition: true,
      color_index,
      usage_ids: [],
    }
    for usage_id in usage_ids {
      scope_map[usage_id] = {
        binder_id: Some(binder_id),
        is_definition: false,
        color_index,
        usage_ids: [],
      }
    }
  }
}

///|
/// Build and merge a canonical @scope graph rooted at one Module node.
fn add_module_scope_annotations(
  node : @canopy_core.ProjNode[@ast.Term],
  source_map : @canopy_core.SourceMap,
  scope_map : Map[@canopy_core.NodeId, ScopeAnnotation],
) -> Unit {
  let registry : Map[@canopy_core.NodeId, @canopy_core.ProjNode[@ast.Term]] = {}
  @canopy_core.collect_registry(node, registry)
  if registry.is_empty() {
    return
  }
  let graph = @scope.build(
    @lambda_proj.FlatProj::from_proj_node(node),
    registry,
    source_map,
  )
  add_scope_graph_annotations(scope_map, graph)
}

///|
/// Overlay @scope annotations for block Module subtrees. The top-level graph
/// ignores local block definitions; building a graph rooted at each Module lets
/// @scope own local declaration identity too. Pre-order traversal is important:
/// inner Module graphs run after outer graphs, so innermost declarations
/// overwrite outer annotations for references they actually resolve.
fn add_nested_module_scope_annotations(
  node : @canopy_core.ProjNode[@ast.Term],
  source_map : @canopy_core.SourceMap,
  scope_map : Map[@canopy_core.NodeId, ScopeAnnotation],
) -> Unit {
  match node.kind {
    @ast.Term::Module(_, _) =>
      add_module_scope_annotations(node, source_map, scope_map)
    _ => ()
  }
  for child in node.children {
    add_nested_module_scope_annotations(child, source_map, scope_map)
  }
}

///|
/// Rebuild binder usage lists from the final reference annotations. This removes
/// stale outer-graph references after a nested Module graph overwrites a Var with
/// a more local declaration.
fn rebuild_usage_lists(
  scope_map : Map[@canopy_core.NodeId, ScopeAnnotation],
) -> Unit {
  let pairs : Array[(@canopy_core.NodeId, @canopy_core.NodeId)] = []
  for node_id, ann in scope_map {
    if ann.is_definition {
      ann.usage_ids.clear()
    } else if ann.binder_id is Some(binder_id) {
      pairs.push((node_id, binder_id))
    }
  }
  for pair in pairs {
    let (usage_id, binder_id) = pair
    match scope_map.get(binder_id) {
      Some(binder_ann) if binder_ann.is_definition =>
        binder_ann.usage_ids.push(usage_id)
      _ => ()
    }
  }
}

///|
/// Build scope_map from canonical lambda @scope graphs.
fn build_scope_map(
  editor : @editor.SyncEditor[@ast.Term],
  companion : @lambda.LambdaCompanion,
) -> Map[@canopy_core.NodeId, ScopeAnnotation] {
  let scope_map : Map[@canopy_core.NodeId, ScopeAnnotation] = {}
  guard editor.get_proj_node() is Some(proj_root) else { return scope_map }
  guard companion.get_flat_proj() is Some(flat_proj) else { return scope_map }
  let registry = editor.get_registry()
  if registry.is_empty() {
    return scope_map
  }
  let source_map = editor.get_source_map()
  let graph = @scope.build(flat_proj, registry, source_map)
  add_scope_graph_annotations(scope_map, graph)
  add_nested_module_scope_annotations(proj_root, source_map, scope_map)
  rebuild_usage_lists(scope_map)
  scope_map
}

///|
/// Compute the set of NodeIds to highlight when a node is selected.
/// Returns empty set for non-identifiers (clear highlights).
fn compute_highlight_set(
  selected_id : @canopy_core.NodeId,
  scope_map : Map[@canopy_core.NodeId, ScopeAnnotation],
) -> @immut/hashset.HashSet[@canopy_core.NodeId] {
  let mut hs = @immut/hashset.new()
  match scope_map.get(selected_id) {
    None => hs
    Some(ann) => {
      // Include the binder and all its usages.
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
      // If this IS a binder, include self + usages.
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
