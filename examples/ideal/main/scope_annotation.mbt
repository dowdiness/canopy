// Scope annotation for binder coloring in the compact tree view.
// Rabbita-local — does not modify ViewNode (framework genericity contract).

///|
/// Annotation for one node: its binder, whether it's a definition site,
/// deterministic color, and (for binders) the list of usage NodeIds.
struct ScopeAnnotation {
  binder_id : @proj.NodeId?
  is_definition : Bool
  color_index : Int
  usage_ids : Array[@proj.NodeId]
}

///|
/// Deterministic color index from binder name. Stable across edits.
/// Returns a value in 0..7 (8-hue palette).
fn binder_color_index(name : String) -> Int {
  let mut h = 0
  loop name.view() {
    [] => ()
    [ch, .. rest] => {
      h = h * 31 + ch.to_int()
      continue rest
    }
  }
  if h < 0 {
    h = -h
  }
  h % 8
}

///|
/// Build scope_map for all identifier nodes in the projection tree.
/// Uses existing resolve_binder/find_usages from lang/lambda/edits/scope.mbt.
fn build_scope_map(
  editor : @editor.SyncEditor[@ast.Term],
) -> Map[@proj.NodeId, ScopeAnnotation] {
  let scope_map : Map[@proj.NodeId, ScopeAnnotation] = {}
  let proj_root = match editor.get_proj_node() {
    Some(r) => r
    None => return scope_map
  }
  let source_map = editor.get_source_map()
  let flat_proj = @lambda_proj.FlatProj::from_proj_node(proj_root)
  let registry = build_registry(proj_root)
  // Walk tree to annotate Var and Lam nodes
  annotate_tree(proj_root, flat_proj, registry, source_map, scope_map)
  // Second pass: populate usage_ids by collecting vars that point to each binder
  backfill_usages(scope_map, flat_proj, registry)
  scope_map
}

///|
/// Walk ProjNode tree and annotate Var and Lam nodes.
fn annotate_tree(
  node : @canopy_core.ProjNode[@ast.Term],
  flat_proj : @lambda_proj.FlatProj,
  registry : Map[@proj.NodeId, @canopy_core.ProjNode[@ast.Term]],
  source_map : @canopy_core.SourceMap,
  scope_map : Map[@proj.NodeId, ScopeAnnotation],
) -> Unit {
  let node_id = node.id()
  match node.kind {
    Var(name) =>
      if !scope_map.contains(node_id) {
        let binding = @lambda_edits.resolve_binder(
          node_id, name, flat_proj, registry, source_map,
        )
        match binding {
          Some(site) =>
            match site {
              @lambda_edits.LamBinder(lam_id~) => {
                // Lambda-bound: link to the Lam node for highlight tracking
                let lam_name = match registry.get(lam_id) {
                  Some(lam_node) =>
                    match lam_node.kind {
                      Lam(param_name, _) => param_name
                      _ => name
                    }
                  None => name
                }
                scope_map[node_id] = {
                  binder_id: Some(lam_id),
                  is_definition: false,
                  color_index: binder_color_index(lam_name),
                  usage_ids: [],
                }
              }
              @lambda_edits.ModuleBinder(..) =>
                // Module-bound: color by name, no binder_id link.
                // Using init NodeId as binder_id would collide with the
                // Lam node at the root of the init expression.
                scope_map[node_id] = {
                  binder_id: None,
                  is_definition: false,
                  color_index: binder_color_index(name),
                  usage_ids: [],
                }
            }
          None => () // Free variable — no annotation
        }
      }
    Lam(param_name, _) =>
      if !scope_map.contains(node_id) {
        let cidx = binder_color_index(param_name)
        scope_map[node_id] = {
          binder_id: Some(node_id),
          is_definition: true,
          color_index: cidx,
          usage_ids: [], // Will be populated by backfill_lam_usages
        }
      }
    _ => ()
  }
  for child in node.children {
    annotate_tree(child, flat_proj, registry, source_map, scope_map)
  }
}

///|
/// Second pass: for each Var that points to a Lam binder,
/// add the Var's NodeId to the binder's usage_ids.
/// Module-bound vars have binder_id=None and are skipped.
fn backfill_usages(
  scope_map : Map[@proj.NodeId, ScopeAnnotation],
  _flat_proj : @lambda_proj.FlatProj,
  _registry : Map[@proj.NodeId, @canopy_core.ProjNode[@ast.Term]],
) -> Unit {
  // Collect var → binder pairs first to avoid mutation during iteration
  let pairs : Array[(@proj.NodeId, @proj.NodeId)] = []
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
/// Build a NodeId → ProjNode registry for the tree.
fn build_registry(
  root : @canopy_core.ProjNode[@ast.Term],
) -> Map[@proj.NodeId, @canopy_core.ProjNode[@ast.Term]] {
  let registry : Map[@proj.NodeId, @canopy_core.ProjNode[@ast.Term]] = {}
  fn walk(node : @canopy_core.ProjNode[@ast.Term]) {
    registry[node.id()] = node
    for child in node.children {
      walk(child)
    }
  }
  walk(root)
  registry
}

///|
/// Compute the set of NodeIds to highlight when a node is selected.
/// Returns empty set for non-identifiers (clear highlights — D7).
fn compute_highlight_set(
  selected_id : @proj.NodeId,
  scope_map : Map[@proj.NodeId, ScopeAnnotation],
) -> @immut/hashset.HashSet[@proj.NodeId] {
  let mut hs = @immut/hashset.HashSet::new()
  match scope_map.get(selected_id) {
    None => hs // Non-identifier: empty set → clear highlights
    Some(ann) => {
      // Include the binder
      match ann.binder_id {
        Some(bid) => {
          hs = hs.add(bid)
          // Get binder's usages
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
