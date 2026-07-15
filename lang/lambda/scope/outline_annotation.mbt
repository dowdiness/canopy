///|
/// Annotation for one node: its binder key, whether it's a definition site,
/// deterministic color, and (for binders) the list of usage NodeIds.
pub struct ScopeAnnotation {
  binder_id : @core.NodeId?
  is_definition : Bool
  color_index : Int
  usage_ids : Array[@core.NodeId]
}

///|
/// Deterministic color index from binder name. Stable across edits.
/// Returns a value in 0..7 (8-hue palette).
pub fn binder_color_index(name : String) -> Int {
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
/// Convert a declaration to the NodeId-compatible UI key used by the
/// outline highlight map. Module declarations now point at real LetDef nodes.
pub fn scope_binder_ui_key(decl : Decl) -> @core.NodeId {
  match decl.kind {
    DeclKind::LamParam(lam_id~) => lam_id
    DeclKind::ModuleDef(_) => decl.node_id
  }
}

///|
/// Merge one canonical scope graph into the UI scope_map.
pub fn add_scope_graph_annotations(
  scope_map : Map[@core.NodeId, ScopeAnnotation],
  graph : ScopeGraph,
) -> Unit {
  for decl in graph.decls {
    let binder_id = scope_binder_ui_key(decl)
    let color_index = binder_color_index(decl.name)
    let usage_ids = references(graph, decl.id)
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
/// Build and merge a canonical scope graph rooted at one Module node.
pub fn add_module_scope_annotations(
  node : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  scope_map : Map[@core.NodeId, ScopeAnnotation],
) -> Unit {
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
  @core.collect_registry(node, registry)
  if registry.is_empty() {
    return
  }
  let graph = build(registry, source_map)
  add_scope_graph_annotations(scope_map, graph)
}

///|
/// Overlay scope annotations for block Module subtrees. The top-level graph
/// ignores local block definitions; building a graph rooted at each Module lets
/// scope own local declaration identity too. Pre-order traversal is important:
/// inner Module graphs run after outer graphs, so innermost declarations
/// overwrite outer annotations for references they actually resolve.
pub fn add_nested_module_scope_annotations(
  node : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  scope_map : Map[@core.NodeId, ScopeAnnotation],
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
pub fn rebuild_usage_lists(
  scope_map : Map[@core.NodeId, ScopeAnnotation],
) -> Unit {
  let pairs : Array[(@core.NodeId, @core.NodeId)] = []
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
/// Build scope_map from canonical lambda scope graphs.
/// Pure: takes projection data, not a SyncEditor.
pub fn build_scope_map(
  proj_root : @core.ProjNode[@ast.Term],
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  source_map : @core.SourceMap,
) -> Map[@core.NodeId, ScopeAnnotation] {
  let scope_map : Map[@core.NodeId, ScopeAnnotation] = Map([])
  if registry.is_empty() {
    return scope_map
  }
  let graph = build(registry, source_map)
  add_scope_graph_annotations(scope_map, graph)
  add_nested_module_scope_annotations(proj_root, source_map, scope_map)
  rebuild_usage_lists(scope_map)
  scope_map
}

///|
/// Compute the set of NodeIds to highlight when a node is selected.
/// Returns empty set for non-identifiers (clear highlights).
pub fn compute_highlight_set(
  selected_id : @core.NodeId,
  scope_map : Map[@core.NodeId, ScopeAnnotation],
) -> @immut/hashset.HashSet[@core.NodeId] {
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
