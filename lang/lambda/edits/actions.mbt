// Context-sensitive action filtering for structural editing.
// Given a node kind and context, returns the set of available actions.

///|
/// Classification of actions for grouping in the UI.
pub(all) enum ActionGroup {
  Core
  Wrap
  Binding
  Module
} derive(Show, Eq)

///|
/// A structural editing action available on a node.
pub(all) struct Action {
  /// Unique identifier for the action (e.g. "wrap_lambda", "delete")
  id : String
  /// Human-readable label (e.g. "Wrap in λ")
  label : String
  /// Keyboard mnemonic (e.g. "l" for lambda)
  mnemonic : String
  /// Which group this action belongs to
  group : ActionGroup
  /// Whether the action requires user text input (e.g. a variable name)
  needs_input : Bool
} derive(Show, Eq)

///|
/// Context about a node's position in the tree, used to filter actions.
pub(all) struct NodeContext {
  /// Whether this node is the RHS of a let-binding in a Module
  is_let_binding : Bool
  /// The NodeId of the binding node (if is_let_binding)
  binding_node_id : NodeId?
  /// The def index in the Module's defs array (if is_let_binding)
  binding_def_index : Int?
  /// The NodeId of the enclosing Module (if is_let_binding)
  module_node_id : NodeId?
} derive(Show, Eq)

///|
/// Create a default NodeContext (not a binding).
pub fn NodeContext::new() -> NodeContext {
  {
    is_let_binding: false,
    binding_node_id: None,
    binding_def_index: None,
    module_node_id: None,
  }
}

///|
/// Create a NodeContext for a let-binding RHS.
pub fn NodeContext::new_binding(
  binding_node_id~ : NodeId,
  binding_def_index~ : Int,
  module_node_id~ : NodeId,
) -> NodeContext {
  {
    is_let_binding: true,
    binding_node_id: Some(binding_node_id),
    binding_def_index: Some(binding_def_index),
    module_node_id: Some(module_node_id),
  }
}

///|
/// Return the list of available actions for a given node kind and context.
pub fn get_actions_for_node(
  kind : @ast.Term,
  context : NodeContext,
) -> Array[Action] {
  let actions : Array[Action] = []
  match kind {
    @ast.Term::Int(_) => {
      actions.push(extract_to_let)
      actions.push(wrap_lambda)
      actions.push(wrap_if)
      actions.push(wrap_bop)
      actions.push(wrap_app)
      actions.push(delete)
    }
    @ast.Term::Var(_) => {
      actions.push(extract_to_let)
      actions.push(inline)
      actions.push(rename)
      actions.push(wrap_lambda)
      actions.push(wrap_if)
      actions.push(wrap_bop)
      actions.push(wrap_app)
      actions.push(delete)
    }
    @ast.Term::Lam(_, _) => {
      actions.push(extract_to_let)
      actions.push(rename)
      actions.push(unwrap)
      actions.push(wrap_lambda)
      actions.push(wrap_if)
      actions.push(wrap_bop)
      actions.push(wrap_app)
      actions.push(delete)
    }
    @ast.Term::App(_, _) => {
      actions.push(extract_to_let)
      actions.push(unwrap)
      actions.push(wrap_lambda)
      actions.push(wrap_if)
      actions.push(wrap_bop)
      actions.push(wrap_app)
      actions.push(delete)
    }
    @ast.Term::Bop(_, _, _) => {
      actions.push(extract_to_let)
      actions.push(unwrap)
      actions.push(swap)
      actions.push(change_op)
      // No wrap_bop — no self-wrapping
      actions.push(wrap_lambda)
      actions.push(wrap_if)
      actions.push(wrap_app)
      actions.push(delete)
    }
    @ast.Term::If(_, _, _) => {
      actions.push(extract_to_let)
      actions.push(unwrap)
      actions.push(swap)
      // No wrap_if — no self-wrapping
      actions.push(wrap_lambda)
      actions.push(wrap_bop)
      actions.push(wrap_app)
      actions.push(delete)
    }
    @ast.Term::Module(_, _) => actions.push(add_binding)
    @ast.Term::Unit => {
      actions.push(wrap_lambda)
      actions.push(wrap_if)
      actions.push(wrap_bop)
      actions.push(wrap_app)
      actions.push(delete)
    }
    @ast.Term::Error(_) => actions.push(delete)
    @ast.Term::Unbound(_) => actions.push(delete)
  }
  // Add binding-level actions when the node is in a let-binding context
  if context.is_let_binding {
    actions.push(binding_rename)
    actions.push(binding_duplicate)
    actions.push(binding_move_up)
    actions.push(binding_move_down)
    actions.push(binding_inline_all)
    actions.push(binding_delete)
  }
  actions
}

// --- Action constants ---

///|
let extract_to_let : Action = {
  id: "extract_to_let",
  label: "Extract to let",
  mnemonic: "e",
  group: Core,
  needs_input: true,
}

///|
let inline : Action = {
  id: "inline",
  label: "Inline",
  mnemonic: "i",
  group: Core,
  needs_input: false,
}

///|
let rename : Action = {
  id: "rename",
  label: "Rename",
  mnemonic: "r",
  group: Core,
  needs_input: true,
}

///|
let unwrap : Action = {
  id: "unwrap",
  label: "Unwrap",
  mnemonic: "u",
  group: Core,
  needs_input: false,
}

///|
let swap : Action = {
  id: "swap",
  label: "Swap children",
  mnemonic: "s",
  group: Core,
  needs_input: false,
}

///|
let change_op : Action = {
  id: "change_op",
  label: "Change operator",
  mnemonic: "o",
  group: Core,
  needs_input: false,
}

///|
let delete : Action = {
  id: "delete",
  label: "Delete",
  mnemonic: "d",
  group: Core,
  needs_input: false,
}

///|
let wrap_lambda : Action = {
  id: "wrap_lambda",
  label: "Wrap in λ",
  mnemonic: "l",
  group: Wrap,
  needs_input: true,
}

///|
let wrap_if : Action = {
  id: "wrap_if",
  label: "Wrap in if",
  mnemonic: "f",
  group: Wrap,
  needs_input: false,
}

///|
let wrap_bop : Action = {
  id: "wrap_bop",
  label: "Wrap in operator",
  mnemonic: "p",
  group: Wrap,
  needs_input: false,
}

///|
let wrap_app : Action = {
  id: "wrap_app",
  label: "Wrap in f(x)",
  mnemonic: "a",
  group: Wrap,
  needs_input: false,
}

///|
let add_binding : Action = {
  id: "add_binding",
  label: "Add binding",
  mnemonic: "b",
  group: Module,
  needs_input: true,
}

///|
let binding_rename : Action = {
  id: "binding_rename",
  label: "Rename binding",
  mnemonic: "R",
  group: Binding,
  needs_input: true,
}

///|
let binding_duplicate : Action = {
  id: "binding_duplicate",
  label: "Duplicate binding",
  mnemonic: "D",
  group: Binding,
  needs_input: false,
}

///|
let binding_move_up : Action = {
  id: "binding_move_up",
  label: "Move binding up",
  mnemonic: "k",
  group: Binding,
  needs_input: false,
}

///|
let binding_move_down : Action = {
  id: "binding_move_down",
  label: "Move binding down",
  mnemonic: "j",
  group: Binding,
  needs_input: false,
}

///|
let binding_inline_all : Action = {
  id: "binding_inline_all",
  label: "Inline all usages",
  mnemonic: "I",
  group: Binding,
  needs_input: false,
}

///|
let binding_delete : Action = {
  id: "binding_delete",
  label: "Delete binding",
  mnemonic: "x",
  group: Binding,
  needs_input: false,
}
