///|
/// A text span replacement: replace source_text[start : start+delete_len] with inserted.
pub(all) struct SpanEdit {
  start : Int
  delete_len : Int
  inserted : String
} derive(Show, Eq)

///|
/// Return a placeholder Term for a given Term kind (for Delete replacement).
fn placeholder_term_for_kind(kind : @ast.Term) -> @ast.Term {
  match kind {
    @ast.Term::Int(_) => @ast.Term::Int(0)
    @ast.Term::Var(_) => @ast.Term::Var("a")
    @ast.Term::Lam(_, _) => @ast.Term::Lam("x", @ast.Term::Var("x"))
    @ast.Term::App(_, _) =>
      @ast.Term::App(@ast.Term::Var("f"), @ast.Term::Var("x"))
    @ast.Term::Bop(_, _, _) =>
      @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Int(0), @ast.Term::Int(0))
    @ast.Term::If(_, _, _) =>
      @ast.Term::If(@ast.Term::Int(0), @ast.Term::Int(0), @ast.Term::Int(0))
    _ => @ast.Term::Var("a")
  }
}

///|
/// Find the start position of the "let " keyword by scanning backwards
/// from a known position in the source text.
fn find_let_start(source_text : String, from : Int) -> Int {
  let mut pos = from
  while pos > 0 {
    pos = pos - 1
    if pos + 3 < source_text.length() &&
      source_text[pos] == 'l' &&
      source_text[pos + 1] == 'e' &&
      source_text[pos + 2] == 't' &&
      source_text[pos + 3] == ' ' {
      return pos
    }
  }
  pos
}

///|
/// Get the text range of a binding line: from "let " to end of init expression.
/// Returns (let_start, init_end).
fn get_binding_text_range(
  source_text : String,
  source_map : SourceMap,
  def : (String, ProjNode, Int, NodeId),
) -> Result[(Int, Int), String] {
  let init_node = def.1
  let init_range = match source_map.get_range(init_node.id()) {
    Some(r) => r
    None => return Err("Init node not in source map")
  }
  let let_start = find_let_start(source_text, init_range.start)
  Ok((let_start, init_range.end))
}

///|
/// Translate a TreeEditOp into text span edits using the source map.
/// All TreeEditOp variants are handled — no fallback to the old path.
/// Returns Some([]) for no-op ops (Select, Collapse, etc.).
pub fn compute_text_edit(
  op : TreeEditOp,
  source_text : String,
  source_map : SourceMap,
  registry : Map[NodeId, ProjNode],
  flat_proj : FlatProj,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  match op {
    // No-op operations — these don't modify source text
    Select(..)
    | SelectRange(..)
    | StartEdit(..)
    | CancelEdit
    | StartDrag(..)
    | DragOver(..)
    | Collapse(..)
    | Expand(..) => Ok(Some(([], RestoreCursor)))
    // CommitEdit: replace node span with new user-provided text
    CommitEdit(node_id~, new_value~) =>
      match source_map.get_range(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(range) =>
          Ok(
            Some(
              (
                [
                  {
                    start: range.start,
                    delete_len: range.end - range.start,
                    inserted: new_value,
                  },
                ],
                RestoreCursor,
              ),
            ),
          )
      }
    // Delete: replace node with placeholder, re-rendering parent for normalization.
    // Special case: if parent is error, remove entirely.
    Delete(node_id~) =>
      match source_map.get_range(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(range) => {
          // Find parent of the deleted node
          let mut parent_info : (NodeId, ProjNode, Int)? = None
          for pid, pnode in registry {
            for i, child in pnode.children {
              if NodeId(child.node_id) == node_id {
                parent_info = Some((pid, pnode, i))
              }
            }
          }
          match parent_info {
            Some((parent_id, parent_node, child_index)) =>
              match parent_node.kind {
                @ast.Term::Error(_) =>
                  // Error parent: remove child entirely
                  Ok(
                    Some(
                      (
                        [
                          {
                            start: range.start,
                            delete_len: range.end - range.start,
                            inserted: "",
                          },
                        ],
                        RestoreCursor,
                      ),
                    ),
                  )
                _ => {
                  // Replace child with placeholder in parent, then re-render parent
                  let target = parent_node.children[child_index]
                  let pk = placeholder_term_for_kind(target.kind)
                  // Build new children array with placeholder at child_index
                  let new_children : Array[ProjNode] = []
                  for i, c in parent_node.children {
                    if i == child_index {
                      new_children.push(
                        ProjNode::new(pk, c.start, c.end, c.node_id, []),
                      )
                    } else {
                      new_children.push(c)
                    }
                  }
                  let new_parent_kind = rebuild_kind(
                    parent_node.kind,
                    new_children,
                  )
                  let new_text = @ast.print_term(new_parent_kind)
                  match source_map.get_range(parent_id) {
                    None => {
                      // No parent range — fall back to simple placeholder
                      let placeholder = match registry.get(node_id) {
                        Some(node) => placeholder_text_for_kind(node.kind)
                        None => "a"
                      }
                      Ok(
                        Some(
                          (
                            [
                              {
                                start: range.start,
                                delete_len: range.end - range.start,
                                inserted: placeholder,
                              },
                            ],
                            RestoreCursor,
                          ),
                        ),
                      )
                    }
                    Some(parent_range) =>
                      Ok(
                        Some(
                          (
                            [
                              {
                                start: parent_range.start,
                                delete_len: parent_range.end -
                                parent_range.start,
                                inserted: new_text,
                              },
                            ],
                            RestoreCursor,
                          ),
                        ),
                      )
                  }
                }
              }
            None => {
              // No parent found — this is the root node. Just use placeholder.
              let placeholder = match registry.get(node_id) {
                Some(node) => placeholder_text_for_kind(node.kind)
                None => "a"
              }
              Ok(
                Some(
                  (
                    [
                      {
                        start: range.start,
                        delete_len: range.end - range.start,
                        inserted: placeholder,
                      },
                    ],
                    RestoreCursor,
                  ),
                ),
              )
            }
          }
        }
      }
    // WrapInLambda: wrap node text in a lambda abstraction
    WrapInLambda(node_id~, var_name~) =>
      match source_map.get_range(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(range) => {
          let existing = match registry.get(node_id) {
            Some(node) => @ast.print_term(node.kind)
            None => return Err("Node not found in registry")
          }
          let wrapped = "(λ" + var_name + ". " + existing + ")"
          Ok(
            Some(
              (
                [
                  {
                    start: range.start,
                    delete_len: range.end - range.start,
                    inserted: wrapped,
                  },
                ],
                RestoreCursor,
              ),
            ),
          )
        }
      }
    // WrapInApp: wrap node text in an application
    WrapInApp(node_id~) =>
      match source_map.get_range(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(range) => {
          let existing_kind = match registry.get(node_id) {
            Some(node) => node.kind
            None => return Err("Node not found in registry")
          }
          let wrapped = @ast.print_term(App(existing_kind, Var("a")))
          Ok(
            Some(
              (
                [
                  {
                    start: range.start,
                    delete_len: range.end - range.start,
                    inserted: wrapped,
                  },
                ],
                RestoreCursor,
              ),
            ),
          )
        }
      }
    // InsertChild: insert a new child at the given index
    InsertChild(parent~, index~, kind~) => {
      let placeholder = placeholder_text_for_kind(kind)
      match registry.get(parent) {
        None => Err("Parent not found: " + parent.to_string())
        Some(parent_node) =>
          match source_map.get_range(parent) {
            None => Err("Parent not in source map")
            Some(parent_range) =>
              match parent_node.kind {
                @ast.Term::Module(_, _) => {
                  // Insert a def between existing defs, with trailing newline separator
                  let insert_text = "let x = " + placeholder + "\n"
                  let insert_pos = if index >= parent_node.children.length() {
                    // Insert before the body (last child)
                    let body = parent_node.children[parent_node.children.length() -
                      1]
                    match source_map.get_range(NodeId(body.node_id)) {
                      Some(r) => r.start
                      None => parent_range.end
                    }
                  } else {
                    match
                      source_map.get_range(
                        NodeId(parent_node.children[index].node_id),
                      ) {
                      Some(r) => r.start
                      None => parent_range.start
                    }
                  }
                  Ok(
                    Some(
                      (
                        [
                          {
                            start: insert_pos,
                            delete_len: 0,
                            inserted: insert_text,
                          },
                        ],
                        RestoreCursor,
                      ),
                    ),
                  )
                }
                _ => {
                  // Re-render whole parent with new child inserted
                  let new_child = ProjNode::new(kind, 0, 0, 0, [])
                  let new_parent = insert_child_at(
                    parent_node, index, new_child,
                  )
                  let new_text = @ast.print_term(new_parent.kind)
                  Ok(
                    Some(
                      (
                        [
                          {
                            start: parent_range.start,
                            delete_len: parent_range.end - parent_range.start,
                            inserted: new_text,
                          },
                        ],
                        RestoreCursor,
                      ),
                    ),
                  )
                }
              }
          }
      }
    }
    // Unwrap: replace a node with one of its children
    Unwrap(node_id~, keep_child_index~) =>
      match (source_map.get_range(node_id), registry.get(node_id)) {
        (Some(range), Some(node)) =>
          if keep_child_index >= node.children.length() {
            Err("Child index out of range")
          } else {
            let kept = node.children[keep_child_index]
            let kept_text = @ast.print_term(kept.kind)
            let kept_start = match source_map.get_range(kept.id()) {
              Some(r) => r.start
              None => range.start
            }
            Ok(
              Some(
                (
                  [
                    {
                      start: range.start,
                      delete_len: range.end - range.start,
                      inserted: kept_text,
                    },
                  ],
                  MoveCursor(position=kept_start),
                ),
              ),
            )
          }
        _ => Err("Node not found: " + node_id.to_string())
      }
    // WrapInIf: wrap a node in an if-then-else with placeholder condition
    WrapInIf(node_id~) =>
      match (source_map.get_range(node_id), registry.get(node_id)) {
        (Some(range), Some(node)) => {
          let wrapped = @ast.print_term(If(Int(0), node.kind, Int(0)))
          // "if 0 then ..." — condition placeholder "0" starts at offset 3
          let condition_pos = range.start + 3
          Ok(
            Some(
              (
                [
                  {
                    start: range.start,
                    delete_len: range.end - range.start,
                    inserted: wrapped,
                  },
                ],
                MoveCursor(position=condition_pos),
              ),
            ),
          )
        }
        _ => Err("Node not found: " + node_id.to_string())
      }
    // WrapInBop: wrap a node in a binary operation with placeholder right operand
    WrapInBop(node_id~, op~) =>
      match (source_map.get_range(node_id), registry.get(node_id)) {
        (Some(range), Some(node)) => {
          let wrapped = @ast.print_term(Bop(op, node.kind, Int(0)))
          // "(expr + 0)" — placeholder "0" is at wrapped.length() - 2 from start
          let placeholder_pos = range.start + wrapped.length() - 2
          Ok(
            Some(
              (
                [
                  {
                    start: range.start,
                    delete_len: range.end - range.start,
                    inserted: wrapped,
                  },
                ],
                MoveCursor(position=placeholder_pos),
              ),
            ),
          )
        }
        _ => Err("Node not found: " + node_id.to_string())
      }
    // ChangeOperator: change the operator of a Bop node
    ChangeOperator(node_id~, new_op~) =>
      match (source_map.get_range(node_id), registry.get(node_id)) {
        (Some(range), Some(node)) =>
          match node.kind {
            @ast.Term::Bop(_, l, r) => {
              let new_text = @ast.print_term(Bop(new_op, l, r))
              Ok(
                Some(
                  (
                    [
                      {
                        start: range.start,
                        delete_len: range.end - range.start,
                        inserted: new_text,
                      },
                    ],
                    RestoreCursor,
                  ),
                ),
              )
            }
            _ => Err("ChangeOperator requires Bop node")
          }
        _ => Err("Node not found: " + node_id.to_string())
      }
    // SwapChildren: swap left/right children of Bop, or then/else of If
    SwapChildren(node_id~) =>
      match (source_map.get_range(node_id), registry.get(node_id)) {
        (Some(range), Some(node)) =>
          match node.kind {
            @ast.Term::Bop(op, l, r) => {
              let swapped = @ast.print_term(Bop(op, r, l))
              Ok(
                Some(
                  (
                    [
                      {
                        start: range.start,
                        delete_len: range.end - range.start,
                        inserted: swapped,
                      },
                    ],
                    RestoreCursor,
                  ),
                ),
              )
            }
            @ast.Term::If(c, t, e) => {
              let swapped = @ast.print_term(If(c, e, t))
              Ok(
                Some(
                  (
                    [
                      {
                        start: range.start,
                        delete_len: range.end - range.start,
                        inserted: swapped,
                      },
                    ],
                    RestoreCursor,
                  ),
                ),
              )
            }
            _ => Err("SwapChildren requires Bop or If node")
          }
        _ => Err("Node not found: " + node_id.to_string())
      }
    // DeleteBinding: remove a let binding line from a Module
    DeleteBinding(binding_node_id~) => {
      let mut def_index = -1
      for i, def in flat_proj.defs {
        if def.3 == binding_node_id {
          def_index = i
        }
      }
      if def_index < 0 {
        return Err("Binding not found: " + binding_node_id.to_string())
      }
      let (let_start, binding_end) = match
        get_binding_text_range(
          source_text,
          source_map,
          flat_proj.defs[def_index],
        ) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
      // Include the trailing newline in deletion
      let delete_end = if binding_end < source_text.length() &&
        source_text[binding_end] == '\n' {
        binding_end + 1
      } else if let_start > 0 && source_text[let_start - 1] == '\n' {
        // No trailing newline — consume the preceding newline instead
        return Ok(
          Some(
            (
              [
                {
                  start: let_start - 1,
                  delete_len: binding_end - let_start + 1,
                  inserted: "",
                },
              ],
              RestoreCursor,
            ),
          ),
        )
      } else {
        binding_end
      }
      Ok(
        Some(
          (
            [
              {
                start: let_start,
                delete_len: delete_end - let_start,
                inserted: "",
              },
            ],
            RestoreCursor,
          ),
        ),
      )
    }
    // DuplicateBinding: copy a binding below with _copy suffix on name
    DuplicateBinding(binding_node_id~) => {
      let mut def_index = -1
      for i, def in flat_proj.defs {
        if def.3 == binding_node_id {
          def_index = i
        }
      }
      if def_index < 0 {
        return Err("Binding not found: " + binding_node_id.to_string())
      }
      let def = flat_proj.defs[def_index]
      let (let_start, binding_end) = match
        get_binding_text_range(source_text, source_map, def) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
      // Extract binding text and create copy with _copy suffix on name
      let binding_text = source_text[let_start:binding_end].to_string()
      let new_name = def.0 + "_copy"
      let init_text = @ast.print_term(def.1.kind)
      let new_binding = "let " + new_name + " = " + init_text
      // Insert after the current binding (after newline)
      let insert_pos = if binding_end < source_text.length() &&
        source_text[binding_end] == '\n' {
        binding_end + 1
      } else {
        binding_end
      }
      let _ = binding_text
      let insert_text = if insert_pos == binding_end {
        // No trailing newline — add one before the new binding
        "\n" + new_binding
      } else {
        new_binding + "\n"
      }
      Ok(
        Some(
          (
            [{ start: insert_pos, delete_len: 0, inserted: insert_text }],
            RestoreCursor,
          ),
        ),
      )
    }
    // MoveBindingUp: swap a binding with its predecessor
    MoveBindingUp(binding_node_id~) => {
      let mut def_index = -1
      for i, def in flat_proj.defs {
        if def.3 == binding_node_id {
          def_index = i
        }
      }
      if def_index < 0 {
        return Err("Binding not found: " + binding_node_id.to_string())
      }
      if def_index == 0 {
        return Err("Cannot move first binding up")
      }
      // Scoping guard: check if either name is free in the other's init
      let cur_def = flat_proj.defs[def_index]
      let prev_def = flat_proj.defs[def_index - 1]
      let empty_env : @immut/hashset.HashSet[String] = @immut/hashset.new()
      let cur_fv = free_vars(cur_def.1.kind, empty_env)
      let prev_fv = free_vars(prev_def.1.kind, empty_env)
      if cur_fv.contains(prev_def.0) {
        return Err(
          "Cannot move up: " +
          cur_def.0 +
          " uses " +
          prev_def.0 +
          " in its init",
        )
      }
      if prev_fv.contains(cur_def.0) {
        return Err(
          "Cannot move up: " +
          prev_def.0 +
          " uses " +
          cur_def.0 +
          " in its init",
        )
      }
      if cur_def.0 == prev_def.0 {
        return Err("Cannot swap bindings with the same name")
      }
      // Get text ranges for both bindings
      let (cur_start, cur_end) = match
        get_binding_text_range(source_text, source_map, cur_def) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
      let (prev_start, prev_end) = match
        get_binding_text_range(source_text, source_map, prev_def) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
      // Swap the two binding lines by replacing the combined range
      let prev_text = source_text[prev_start:prev_end].to_string()
      let cur_text = source_text[cur_start:cur_end].to_string()
      // The separator between bindings (typically "\n")
      let separator = source_text[prev_end:cur_start].to_string()
      let swapped = cur_text + separator + prev_text
      Ok(
        Some(
          (
            [
              {
                start: prev_start,
                delete_len: cur_end - prev_start,
                inserted: swapped,
              },
            ],
            RestoreCursor,
          ),
        ),
      )
    }
    // MoveBindingDown: swap a binding with its successor
    MoveBindingDown(binding_node_id~) => {
      let mut def_index = -1
      for i, def in flat_proj.defs {
        if def.3 == binding_node_id {
          def_index = i
        }
      }
      if def_index < 0 {
        return Err("Binding not found: " + binding_node_id.to_string())
      }
      if def_index >= flat_proj.defs.length() - 1 {
        return Err("Cannot move last binding down")
      }
      // Scoping guard: check if either name is free in the other's init
      let cur_def = flat_proj.defs[def_index]
      let next_def = flat_proj.defs[def_index + 1]
      let empty_env : @immut/hashset.HashSet[String] = @immut/hashset.new()
      let cur_fv = free_vars(cur_def.1.kind, empty_env)
      let next_fv = free_vars(next_def.1.kind, empty_env)
      if next_fv.contains(cur_def.0) {
        return Err(
          "Cannot move down: " +
          next_def.0 +
          " uses " +
          cur_def.0 +
          " in its init",
        )
      }
      if cur_fv.contains(next_def.0) {
        return Err(
          "Cannot move down: " +
          cur_def.0 +
          " uses " +
          next_def.0 +
          " in its init",
        )
      }
      if cur_def.0 == next_def.0 {
        return Err("Cannot swap bindings with the same name")
      }
      // Get text ranges for both bindings
      let (cur_start, cur_end) = match
        get_binding_text_range(source_text, source_map, cur_def) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
      let (next_start, next_end) = match
        get_binding_text_range(source_text, source_map, next_def) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
      // Swap the two binding lines by replacing the combined range
      let cur_text = source_text[cur_start:cur_end].to_string()
      let next_text = source_text[next_start:next_end].to_string()
      let separator = source_text[cur_end:next_start].to_string()
      let swapped = next_text + separator + cur_text
      Ok(
        Some(
          (
            [
              {
                start: cur_start,
                delete_len: next_end - cur_start,
                inserted: swapped,
              },
            ],
            RestoreCursor,
          ),
        ),
      )
    }
    // AddBinding: delegate to InsertChild for Module nodes
    AddBinding(module_node_id~) =>
      compute_text_edit(
        InsertChild(
          parent=module_node_id,
          index=flat_proj.defs.length(),
          kind=@ast.Term::Int(0),
        ),
        source_text,
        source_map,
        registry,
        flat_proj,
      )
    // Drop: move a node from source to target position
    Drop(source~, target~, position~) => {
      let source_range = match source_map.get_range(source) {
        Some(r) => r
        None => return Err("Source node not found")
      }
      let target_range = match source_map.get_range(target) {
        Some(r) => r
        None => return Err("Target node not found")
      }
      let source_slice = source_text[source_range.start:source_range.end].to_string()
      let insert_pos = match position {
        Before => target_range.start
        After => target_range.end
        Inside => target_range.start
      }
      Ok(
        Some(
          (
            [
              {
                start: source_range.start,
                delete_len: source_range.end - source_range.start,
                inserted: "",
              },
              { start: insert_pos, delete_len: 0, inserted: source_slice },
            ],
            RestoreCursor,
          ),
        ),
      )
    }
    // ExtractToLet: extract a sub-expression into a new let binding
    ExtractToLet(node_id~, var_name~) => {
      let node = match registry.get(node_id) {
        Some(n) => n
        None => return Err("Node not found")
      }
      let range = match source_map.get_range(node_id) {
        Some(r) => r
        None => return Err("Range not found")
      }
      // Free-var validation: check for lambda-captured variables
      let mut module_env : @immut/hashset.HashSet[String] = @immut/hashset.new()
      // Find which def contains this node (or if it's in the body)
      let mut in_def_index : Int = flat_proj.defs.length() // body sentinel
      for i, def in flat_proj.defs {
        match source_map.get_range(def.1.id()) {
          Some(r) =>
            if range.start >= r.start && range.end <= r.end {
              in_def_index = i
              break
            }
          None => ()
        }
      }
      // Add def names in scope at the extraction site
      let scope_limit = if in_def_index < flat_proj.defs.length() {
        in_def_index
      } else {
        flat_proj.defs.length()
      }
      for i = 0; i < scope_limit; i = i + 1 {
        module_env = module_env.add(flat_proj.defs[i].0)
      }
      // Check for lambda-captured vars
      let lam_env = collect_lam_env(node_id, registry)
      let fv = free_vars(node.kind, module_env)
      let mut captured_var : String? = None
      fv.each(fn(v) { if lam_env.contains(v) { captured_var = Some(v) } })
      if captured_var is Some(_) {
        return Err("Cannot extract: expression captures lambda-bound variables")
      }
      // Build edits
      let expr_text = @ast.print_term(node.kind)
      let let_text = "let " + var_name + " = " + expr_text + "\n"
      if flat_proj.defs.is_empty() && flat_proj.final_expr is Some(_) {
        // No module — wrap: replace expression with "let name = expr\nname"
        let new_text = let_text + var_name
        Ok(
          Some(
            (
              [
                {
                  start: range.start,
                  delete_len: range.end - range.start,
                  inserted: new_text,
                },
              ],
              MoveCursor(position=range.start + let_text.length()),
            ),
          ),
        )
      } else {
        // Has Module — insert let before body, replace expr with var_name
        let body_start = match flat_proj.final_expr {
          Some(body) =>
            match source_map.get_range(body.id()) {
              Some(r) => r.start
              None => source_text.length()
            }
          None => source_text.length()
        }
        // Check if node is within the body (range starts at or after body start).
        // If so, we need a single combined edit to avoid overlapping edits.
        if range.start >= body_start {
          // Node is in the body — produce a single edit:
          // Replace body text from body_start to end with:
          //   "let var = expr\n" + (prefix before node) + var_name + (suffix after node)
          let body_end = match flat_proj.final_expr {
            Some(body) =>
              match source_map.get_range(body.id()) {
                Some(r) => r.end
                None => source_text.length()
              }
            None => source_text.length()
          }
          let prefix = source_text[body_start:range.start].to_string()
          let suffix = source_text[range.end:body_end].to_string()
          let new_body_text = let_text + prefix + var_name + suffix
          Ok(
            Some(
              (
                [
                  {
                    start: body_start,
                    delete_len: body_end - body_start,
                    inserted: new_body_text,
                  },
                ],
                MoveCursor(
                  position=body_start + let_text.length() + prefix.length(),
                ),
              ),
            ),
          )
        } else {
          // Node is in a def — two independent edits at non-overlapping positions
          Ok(
            Some(
              (
                [
                  { start: body_start, delete_len: 0, inserted: let_text },
                  {
                    start: range.start,
                    delete_len: range.end - range.start,
                    inserted: var_name,
                  },
                ],
                MoveCursor(position=range.start),
              ),
            ),
          )
        }
      }
    }
    // InlineDefinition: inline a single Var usage of a module binding
    InlineDefinition(node_id~) => {
      let node = match registry.get(node_id) {
        Some(n) => n
        None => return Err("Node not found: " + node_id.to_string())
      }
      let var_name = match node.kind {
        @ast.Term::Var(name) => name
        _ => return Err("InlineDefinition requires a Var node")
      }
      let range = match source_map.get_range(node_id) {
        Some(r) => r
        None => return Err("Var not in source map")
      }
      // Resolve the binding
      let binder = match resolve_binder(
        node_id, var_name, flat_proj, registry, source_map,
      ) {
        Some(b) => b
        None => return Err("No binding found for variable: " + var_name)
      }
      match binder {
        LamBinder(..) =>
          return Err("Cannot inline lambda-bound variable: " + var_name)
        ModuleBinder(def_index~, ..) => {
          let def = flat_proj.defs[def_index]
          let init_text = @ast.print_term(def.1.kind)
          // Check if this is the sole usage
          let usages = find_usages(
            var_name, def_index + 1, flat_proj, registry,
          )
          if usages.length() <= 1 {
            // Sole usage — inline and delete the binding
            let (let_start, binding_end) = match
              get_binding_text_range(source_text, source_map, def) {
              Ok(r) => r
              Err(e) => return Err(e)
            }
            // Determine delete range for the binding line (including newline)
            let (del_start, del_len) = if binding_end < source_text.length() &&
              source_text[binding_end] == '\n' {
              (let_start, binding_end + 1 - let_start)
            } else if let_start > 0 && source_text[let_start - 1] == '\n' {
              (let_start - 1, binding_end - let_start + 1)
            } else {
              (let_start, binding_end - let_start)
            }
            // If the var range is after the binding, we need to adjust
            // for the deletion. Produce edits in reverse document order.
            if range.start >= binding_end {
              // Var is after binding — two non-overlapping edits
              Ok(
                Some(
                  (
                    [
                      {
                        start: range.start,
                        delete_len: range.end - range.start,
                        inserted: init_text,
                      },
                      {
                        start: del_start,
                        delete_len: del_len,
                        inserted: "",
                      },
                    ],
                    MoveCursor(position=range.start),
                  ),
                ),
              )
            } else {
              // Var is within the binding init — just replace the var
              Ok(
                Some(
                  (
                    [
                      {
                        start: range.start,
                        delete_len: range.end - range.start,
                        inserted: init_text,
                      },
                    ],
                    MoveCursor(position=range.start),
                  ),
                ),
              )
            }
          } else {
            // Multiple usages — just replace this single var
            Ok(
              Some(
                (
                  [
                    {
                      start: range.start,
                      delete_len: range.end - range.start,
                      inserted: init_text,
                    },
                  ],
                  MoveCursor(position=range.start),
                ),
              ),
            )
          }
        }
      }
    }
    // InlineAllUsages: replace all usages of a binding and remove the binding
    InlineAllUsages(binding_node_id~) => {
      // Find the binding
      let mut def_index = -1
      for i, def in flat_proj.defs {
        if def.3 == binding_node_id {
          def_index = i
        }
      }
      if def_index < 0 {
        return Err("Binding not found: " + binding_node_id.to_string())
      }
      let def = flat_proj.defs[def_index]
      let var_name = def.0
      let init_text = @ast.print_term(def.1.kind)
      // Find all usages
      let usage_ids = find_usages(var_name, def_index + 1, flat_proj, registry)
      // Build replacement edits for all usages (reverse document order)
      let edits : Array[SpanEdit] = []
      // Collect usage ranges, sorted by position (descending)
      let usage_ranges : Array[(Int, Int)] = []
      for uid in usage_ids {
        match source_map.get_range(uid) {
          Some(r) => usage_ranges.push((r.start, r.end))
          None => ()
        }
      }
      usage_ranges.sort_by(fn(a, b) { b.0.compare(a.0) })
      for ur in usage_ranges {
        edits.push(
          { start: ur.0, delete_len: ur.1 - ur.0, inserted: init_text },
        )
      }
      // Delete the binding
      let (let_start, binding_end) = match
        get_binding_text_range(source_text, source_map, def) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
      let (del_start, del_len) = if binding_end < source_text.length() &&
        source_text[binding_end] == '\n' {
        (let_start, binding_end + 1 - let_start)
      } else if let_start > 0 && source_text[let_start - 1] == '\n' {
        (let_start - 1, binding_end - let_start + 1)
      } else {
        (let_start, binding_end - let_start)
      }
      edits.push({ start: del_start, delete_len: del_len, inserted: "" })
      Ok(Some((edits, RestoreCursor)))
    }
    // Rename: placeholder — implemented after token span resolution
    Rename(node_id~, new_name~) => {
      let _ = (node_id, new_name)
      Err("Rename not yet implemented in compute_text_edit")
    }
  }
}
