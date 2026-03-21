// Action context detection and TreeEditOp builder for the structural editing overlay.
// Bridges the UI layer (string-based node IDs, action IDs) to the projection layer
// (typed NodeId, TreeEditOp, NodeContext).

///|
/// Detect the action context for a selected node.
/// Parses the node ID string, looks up the node in the editor's projection,
/// checks if it's a let-binding init, and finds the enclosing Module node.
fn detect_action_context(
  editor : @editor.SyncEditor,
  selected_node : String,
) -> NodeActionContext? {
  let node_id_int = @strconv.parse_int(selected_node) catch { _ => return None }
  let nid = @proj.NodeId::from_int(node_id_int)
  let node = match editor.get_node(nid) {
    Some(n) => n
    None => return None
  }
  let flat_proj = match editor.get_flat_proj() {
    Some(fp) => fp
    None => return None
  }
  // Check if this node is a let-binding init expression
  let (is_let_binding, binding_node_id, binding_def_index) = match
    @proj.find_binding_for_init(nid, flat_proj) {
    Some((bid, idx)) => (true, Some(bid), Some(idx))
    None => (false, None, None)
  }
  // Find the Module node — it's the root ProjNode
  let module_node_id = match editor.get_proj_node() {
    Some(root) =>
      match root.kind {
        @ast.Term::Module(_, _) => Some(root.id())
        _ => None
      }
    None => None
  }
  Some({
    node_id: nid,
    kind: node.kind,
    is_let_binding,
    binding_node_id,
    binding_def_index,
    module_node_id,
  })
}

///|
/// Convert a NodeActionContext to a @proj.NodeContext for action filtering.
fn to_proj_context(ctx : NodeActionContext) -> @proj.NodeContext {
  match
    (
      ctx.is_let_binding,
      ctx.binding_node_id,
      ctx.binding_def_index,
      ctx.module_node_id,
    ) {
    (true, Some(bid), Some(idx), Some(mid)) =>
      @proj.NodeContext::new_binding(
        binding_node_id=bid,
        binding_def_index=idx,
        module_node_id=mid,
      )
    _ => @proj.NodeContext::new()
  }
}

///|
/// Get submenu choices for an action that requires a choice.
/// Returns array of (label, value) pairs, empty if no submenu needed.
fn get_submenu_choices(
  action_id : String,
  kind : @ast.Term,
) -> Array[(String, String)] {
  match action_id {
    "change_op" | "wrap_bop" => [("Plus", "Plus"), ("Minus", "Minus")]
    "unwrap" =>
      match kind {
        @ast.Term::Bop(_, _, _) => [("left", "0"), ("right", "1")]
        @ast.Term::If(_, _, _) =>
          [("cond", "0"), ("then", "1"), ("else", "2")]
        @ast.Term::App(_, _) => [("fn", "0"), ("arg", "1")]
        _ => [("body", "0")]
      }
    _ => []
  }
}

///|
/// Parse a Bop choice string to a @ast.Bop value.
fn parse_bop(choice : String) -> @ast.Bop? {
  match choice {
    "Plus" => Some(@ast.Bop::Plus)
    "Minus" => Some(@ast.Bop::Minus)
    _ => None
  }
}

///|
/// Map an action ID + context + optional choice/name to a concrete TreeEditOp.
/// Returns Ok(None) when a name prompt is needed first (i.e. action requires
/// user text input and no name was provided).
/// Returns Err for invalid action IDs or missing required parameters.
fn build_tree_edit_op(
  action_id : String,
  ctx : NodeActionContext,
  choice : String,
  name : String,
) -> Result[@proj.TreeEditOp?, String] {
  let node_id = ctx.node_id
  match action_id {
    "delete" => Ok(Some(@proj.Delete(node_id~)))
    "extract_to_let" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(@proj.ExtractToLet(node_id~, var_name=name)))
      }
    "inline" => Ok(Some(@proj.InlineDefinition(node_id~)))
    "rename" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(@proj.Rename(node_id~, new_name=name)))
      }
    "unwrap" => {
      let keep_child_index = match choice {
        "0" => 0
        "1" => 1
        "2" => 2
        _ => return Err("Invalid unwrap choice: " + choice)
      }
      Ok(Some(@proj.Unwrap(node_id~, keep_child_index~)))
    }
    "swap" => Ok(Some(@proj.SwapChildren(node_id~)))
    "change_op" => {
      let new_op = match parse_bop(choice) {
        Some(op) => op
        None => return Err("Invalid operator choice: " + choice)
      }
      Ok(Some(@proj.ChangeOperator(node_id~, new_op~)))
    }
    "wrap_lambda" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(@proj.WrapInLambda(node_id~, var_name=name)))
      }
    "wrap_if" => Ok(Some(@proj.WrapInIf(node_id~)))
    "wrap_bop" => {
      let op = match parse_bop(choice) {
        Some(op) => op
        None => return Err("Invalid operator choice: " + choice)
      }
      Ok(Some(@proj.WrapInBop(node_id~, op~)))
    }
    "wrap_app" => Ok(Some(@proj.WrapInApp(node_id~)))
    "binding_rename" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(@proj.Rename(node_id~, new_name=name)))
      }
    "binding_duplicate" =>
      match ctx.binding_node_id {
        Some(binding_node_id) =>
          Ok(Some(@proj.DuplicateBinding(binding_node_id~)))
        None => Err("No binding node ID for binding_duplicate")
      }
    "binding_move_up" =>
      match ctx.binding_node_id {
        Some(binding_node_id) => Ok(Some(@proj.MoveBindingUp(binding_node_id~)))
        None => Err("No binding node ID for binding_move_up")
      }
    "binding_move_down" =>
      match ctx.binding_node_id {
        Some(binding_node_id) =>
          Ok(Some(@proj.MoveBindingDown(binding_node_id~)))
        None => Err("No binding node ID for binding_move_down")
      }
    "binding_inline_all" =>
      match ctx.binding_node_id {
        Some(binding_node_id) =>
          Ok(Some(@proj.InlineAllUsages(binding_node_id~)))
        None => Err("No binding node ID for binding_inline_all")
      }
    "binding_delete" =>
      match ctx.binding_node_id {
        Some(binding_node_id) => Ok(Some(@proj.DeleteBinding(binding_node_id~)))
        None => Err("No binding node ID for binding_delete")
      }
    "add_binding" =>
      match ctx.module_node_id {
        Some(module_node_id) => Ok(Some(@proj.AddBinding(module_node_id~)))
        None => Err("No module node ID for add_binding")
      }
    _ => Err("Unknown action: " + action_id)
  }
}
