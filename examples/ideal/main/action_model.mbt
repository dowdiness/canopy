// Action context detection and TreeEditOp builder for the structural editing overlay.
// Bridges the UI layer (string-based node IDs, action IDs) to the projection layer
// (typed NodeId, TreeEditOp, NodeContext).

///|
/// Detect the action context for a selected node.
/// Parses the node ID string, looks up the node in the editor's projection,
/// checks if it's a let-binding init, and finds the enclosing Module node.
fn detect_action_context(
  editor : @editor.SyncEditor[@ast.Term],
  companion : @lambda.LambdaCompanion,
  selected_node : String,
) -> NodeActionContext? {
  let nid = match parse_node_id(selected_node) {
    Some(id) => id
    None => return None
  }
  let node = match editor.get_node(nid) {
    Some(n) => n
    None => return None
  }
  let flat_proj = match companion.get_flat_proj() {
    Some(fp) => fp
    None => return None
  }
  // Check if this node is a let-binding init expression
  let (is_let_binding, binding_node_id, binding_def_index) = match
    @lambda_edits.find_binding_for_init(nid, flat_proj) {
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
/// Convert a NodeActionContext to a @lambda_edits.NodeContext for action filtering.
fn to_proj_context(ctx : NodeActionContext) -> @lambda_edits.NodeContext {
  match
    (
      ctx.is_let_binding,
      ctx.binding_node_id,
      ctx.binding_def_index,
      ctx.module_node_id,
    ) {
    (true, Some(bid), Some(idx), Some(mid)) =>
      @lambda_edits.NodeContext::new_binding(
        binding_node_id=bid,
        binding_def_index=idx,
        module_node_id=mid,
      )
    _ => @lambda_edits.NodeContext::new()
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
    "change_op" | "wrap_bop" => [("+ (plus)", "Plus"), ("- (minus)", "Minus")]
    "unwrap" =>
      match kind {
        @ast.Term::Bop(_, _, _) =>
          [("Keep left operand", "0"), ("Keep right operand", "1")]
        @ast.Term::If(_, _, _) =>
          [
            ("Keep condition", "0"),
            ("Keep then branch", "1"),
            ("Keep else branch", "2"),
          ]
        @ast.Term::App(_, _) => [("Keep function", "0"), ("Keep argument", "1")]
        _ => [("Keep body", "0")]
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
) -> Result[@lambda_edits.TreeEditOp?, String] {
  let node_id = ctx.node_id
  match action_id {
    "delete" => Ok(Some(@lambda_edits.Delete(node_id~)))
    "extract_to_let" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(@lambda_edits.ExtractToLet(node_id~, var_name=name)))
      }
    "inline" => Ok(Some(@lambda_edits.InlineDefinition(node_id~)))
    "rename" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(@lambda_edits.Rename(node_id~, new_name=name)))
      }
    "unwrap" => {
      let keep_child_index = match choice {
        "0" => 0
        "1" => 1
        "2" => 2
        _ => return Err("Select which child to keep")
      }
      Ok(Some(@lambda_edits.Unwrap(node_id~, keep_child_index~)))
    }
    "swap" => Ok(Some(@lambda_edits.SwapChildren(node_id~)))
    "change_op" => {
      let new_op = match parse_bop(choice) {
        Some(op) => op
        None => return Err("Select an operator")
      }
      Ok(Some(@lambda_edits.ChangeOperator(node_id~, new_op~)))
    }
    "wrap_lambda" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(@lambda_edits.WrapInLambda(node_id~, var_name=name)))
      }
    "wrap_if" => Ok(Some(@lambda_edits.WrapInIf(node_id~)))
    "wrap_bop" => {
      let op = match parse_bop(choice) {
        Some(op) => op
        None => return Err("Select an operator")
      }
      Ok(Some(@lambda_edits.WrapInBop(node_id~, op~)))
    }
    "wrap_app" => Ok(Some(@lambda_edits.WrapInApp(node_id~)))
    "binding_rename" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(@lambda_edits.Rename(node_id~, new_name=name)))
      }
    "binding_duplicate" =>
      match ctx.binding_node_id {
        Some(binding_node_id) =>
          Ok(Some(@lambda_edits.DuplicateBinding(binding_node_id~)))
        None => Err("Select a let-binding first")
      }
    "binding_move_up" =>
      match ctx.binding_node_id {
        Some(binding_node_id) =>
          Ok(Some(@lambda_edits.MoveBindingUp(binding_node_id~)))
        None => Err("Select a let-binding first")
      }
    "binding_move_down" =>
      match ctx.binding_node_id {
        Some(binding_node_id) =>
          Ok(Some(@lambda_edits.MoveBindingDown(binding_node_id~)))
        None => Err("Select a let-binding first")
      }
    "binding_inline_all" =>
      match ctx.binding_node_id {
        Some(binding_node_id) =>
          Ok(Some(@lambda_edits.InlineAllUsages(binding_node_id~)))
        None => Err("Select a let-binding first")
      }
    "binding_delete" =>
      match ctx.binding_node_id {
        Some(binding_node_id) =>
          Ok(Some(@lambda_edits.DeleteBinding(binding_node_id~)))
        None => Err("Select a let-binding first")
      }
    "add_binding" =>
      match ctx.module_node_id {
        Some(module_node_id) =>
          Ok(Some(@lambda_edits.AddBinding(module_node_id~)))
        None => Err("No module in scope")
      }
    _ => Err("Unknown action")
  }
}
