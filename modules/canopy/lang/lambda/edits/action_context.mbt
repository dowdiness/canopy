///|
/// Context for building a TreeEditOp from the action overlay. Builds on
/// NodeContext (used for action filtering) with the node's identity and
/// term kind needed by build_tree_edit_op.
pub(all) struct ActionContext {
  node_id : @core.NodeId
  kind : @ast.Term
  is_let_binding : Bool
  binding_node_id : @core.NodeId?
  binding_def_index : Int?
  module_node_id : @core.NodeId?
}

///|
/// Pure builder: construct an ActionContext from projection data.
/// The SyncEditor-dependent extraction lives in lang/lambda/companion.
pub fn build_action_context(
  node_id~ : @core.NodeId,
  kind~ : @ast.Term,
  definition_index~ : @lambda_proj.DefinitionIndex,
  module_node_id~ : @core.NodeId?,
) -> ActionContext {
  let (is_let_binding, binding_node_id, binding_def_index) = match
    definition_index.binding_for_node(node_id) {
    Some((bid, idx)) => (true, Some(bid), Some(idx))
    None => (false, None, None)
  }
  {
    node_id,
    kind,
    is_let_binding,
    binding_node_id,
    binding_def_index,
    module_node_id,
  }
}

///|
/// Convert an ActionContext to a NodeContext for action filtering.
pub fn to_node_context(ctx : ActionContext) -> NodeContext {
  match
    (
      ctx.is_let_binding,
      ctx.binding_node_id,
      ctx.binding_def_index,
      ctx.module_node_id,
    ) {
    (true, Some(bid), Some(idx), Some(mid)) =>
      NodeContext::new_binding(
        binding_node_id=bid,
        binding_def_index=idx,
        module_node_id=mid,
      )
    _ => NodeContext::new()
  }
}

///|
/// Get submenu choices for an action that requires a choice.
/// Returns array of (label, value) pairs, empty if no submenu needed.
pub fn get_submenu_choices(
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
/// Parse a Bop choice string to an AST Bop value.
pub fn parse_bop(choice : String) -> @ast.Bop? {
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
pub fn build_tree_edit_op(
  action_id : String,
  ctx : ActionContext,
  choice : String,
  name : String,
) -> Result[TreeEditOp?, String] {
  let node_id = ctx.node_id
  match action_id {
    "delete" => Ok(Some(Delete(node_id~)))
    "extract_to_let" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(ExtractToLet(node_id~, var_name=name)))
      }
    "inline" => Ok(Some(InlineDefinition(node_id~)))
    "rename" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(Rename(node_id~, new_name=name)))
      }
    "unwrap" => {
      let keep_child_index = match choice {
        "0" => 0
        "1" => 1
        "2" => 2
        _ => return Err("Select which child to keep")
      }
      Ok(Some(Unwrap(node_id~, keep_child_index~)))
    }
    "swap" => Ok(Some(SwapChildren(node_id~)))
    "change_op" => {
      let new_op = match parse_bop(choice) {
        Some(op) => op
        None => return Err("Select an operator")
      }
      Ok(Some(ChangeOperator(node_id~, new_op~)))
    }
    "wrap_lambda" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(WrapInLambda(node_id~, var_name=name)))
      }
    "wrap_if" => Ok(Some(WrapInIf(node_id~)))
    "wrap_bop" => {
      let op = match parse_bop(choice) {
        Some(op) => op
        None => return Err("Select an operator")
      }
      Ok(Some(WrapInBop(node_id~, op~)))
    }
    "wrap_app" => Ok(Some(WrapInApp(node_id~)))
    "binding_rename" =>
      if name == "" {
        Ok(None)
      } else {
        Ok(Some(Rename(node_id~, new_name=name)))
      }
    "binding_duplicate" =>
      match ctx.binding_node_id {
        Some(binding_node_id) => Ok(Some(DuplicateBinding(binding_node_id~)))
        None => Err("Select a let-binding first")
      }
    "binding_move_up" =>
      match ctx.binding_node_id {
        Some(binding_node_id) => Ok(Some(MoveBindingUp(binding_node_id~)))
        None => Err("Select a let-binding first")
      }
    "binding_move_down" =>
      match ctx.binding_node_id {
        Some(binding_node_id) => Ok(Some(MoveBindingDown(binding_node_id~)))
        None => Err("Select a let-binding first")
      }
    "binding_inline_all" =>
      match ctx.binding_node_id {
        Some(binding_node_id) => Ok(Some(InlineAllUsages(binding_node_id~)))
        None => Err("Select a let-binding first")
      }
    "binding_delete" =>
      match ctx.binding_node_id {
        Some(binding_node_id) => Ok(Some(DeleteBinding(binding_node_id~)))
        None => Err("Select a let-binding first")
      }
    "add_binding" =>
      match ctx.module_node_id {
        Some(module_node_id) => Ok(Some(AddBinding(module_node_id~)))
        None => Err("No module in scope")
      }
    _ => Err("Unknown action")
  }
}
