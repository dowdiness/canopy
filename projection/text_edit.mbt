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
  let _ = flat_proj
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
      // Find the def entry matching this binding_node_id
      let mut def_index = -1
      for i, def in flat_proj.defs {
        if def.3 == binding_node_id {
          def_index = i
        }
      }
      if def_index < 0 {
        return Err(
          "Binding not found: " + binding_node_id.to_string(),
        )
      }
      let init_node = flat_proj.defs[def_index].1
      let init_range = match source_map.get_range(init_node.id()) {
        Some(r) => r
        None => return Err("Init node not in source map")
      }
      // Scan backwards from init_range.start to find "let " keyword
      let mut let_start = init_range.start
      while let_start > 0 {
        let_start = let_start - 1
        if let_start + 3 < source_text.length() &&
          source_text[let_start] == 'l' &&
          source_text[let_start + 1] == 'e' &&
          source_text[let_start + 2] == 't' &&
          source_text[let_start + 3] == ' ' {
          break
        }
      }
      // Compute deletion end: include the trailing newline
      let binding_end = init_range.end
      let delete_end = if binding_end < source_text.length() &&
        source_text[binding_end] == '\n' {
        binding_end + 1
      } else {
        // No trailing newline — if there's a leading newline, consume it instead
        if let_start > 0 && source_text[let_start - 1] == '\n' {
          // Adjust start to consume the preceding newline
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
  }
}
