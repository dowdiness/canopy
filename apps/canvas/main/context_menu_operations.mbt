///|
const ARRANGE_GAP : Double = 16.0

///|
priv struct CanvasContextRuntimeTarget {
  handle : Int
} derive(Eq)

///|
priv struct CanvasContextSourceTarget {
  handle : Int
} derive(Eq)

///|
priv struct CanvasContextRuntimeAdd {
  target : CanvasContextRuntimeTarget
  kind : String
  position : WorldPoint
} derive(Eq)

///|
priv struct CanvasContextRuntimeArrange {
  target : CanvasContextRuntimeTarget
  first : NodeId
  second : NodeId
  rest : Array[NodeId]
} derive(Eq)

///|
priv struct CanvasContextRuntimeDisconnect {
  target : CanvasContextRuntimeTarget
  edge : EdgeId
} derive(Eq)

///|
priv struct CanvasContextSourceAdd {
  target : CanvasContextSourceTarget
  binding_base : String
  constructor_name : String
} derive(Eq)

///|
priv struct CanvasContextSourceDisconnect {
  owner : CanvasContextSourceTarget
  source : NodeId
  source_port : String
  target : NodeId
  target_port : String
  edge : EdgeId
} derive(Eq)

///|
priv enum CanvasContextOperation {
  RuntimeAdd(CanvasContextRuntimeAdd)
  RuntimeArrange(CanvasContextRuntimeArrange)
  RuntimeDisconnect(CanvasContextRuntimeDisconnect)
  SourceAdd(CanvasContextSourceAdd)
  SourceDisconnect(CanvasContextSourceDisconnect)
} derive(Eq)

///|
priv struct CanvasContextMenuItem {
  operation : CanvasContextOperation
  label : String
  description : String
} derive(Eq)

///|
priv struct CanvasContextPreparedMenu {
  anchor : @context_menu.Point
  items : Array[CanvasContextMenuItem]
}

///|
priv enum CanvasContextProblem {
  TargetExpired
  Rejected(String)
} derive(Eq)

///|
fn CanvasContextProblem::message(self : CanvasContextProblem) -> String {
  match self {
    TargetExpired => "The menu target is no longer available. Reopen the menu."
    Rejected(message) => message
  }
}

///|
priv enum CanvasContextOutcome {
  RuntimeApplied
  SourceApplied(SourceGraphOperationResultJson)
  SourceRejected(SourceGraphOperationResultJson, selection_changed~ : Bool)
  Failed(CanvasContextProblem)
}

///|
fn find_edge_endpoints(
  state : CanvasState,
  edge_id : EdgeId,
) -> (NodeId, String, NodeId, String)? {
  match state.edges.search_by(fn(edge) { edge.id == edge_id }) {
    Some(index) => {
      let edge = state.edges[index]
      Some((edge.source, edge.source_port, edge.target, edge.target_port))
    }
    None => None
  }
}

///|
fn build_context_menu(
  canvas_handle : Int,
  request : CanvasContextRequest,
) -> Result[CanvasContextPreparedMenu, CanvasContextProblem] {
  match request.target {
    Background(insert_at~) =>
      match canvas_backing(canvas_handle) {
        Some(Runtime(runtime)) => {
          let state = runtime.state_peek()
          let position = state.viewport.screen_to_world(insert_at) catch {
            @spatial.CoordinateError::NonFinite =>
              return Err(
                Rejected("context menu anchor is not a finite world point"),
              )
          }
          runtime.clear_selected_edge()
          let items : Array[CanvasContextMenuItem] = workflow_node_catalog().map(fn(
              item,
            ) {
              {
                operation: RuntimeAdd({
                  target: { handle: canvas_handle, },
                  kind: item.key,
                  position,
                }),
                label: item.label,
                description: item.description,
              }
            },
          )
          let selected = runtime.peek_selection().selected_nodes
          if selected.length() >= 2 {
            let ids = selected[2:].to_owned()
            items.insert(0, {
              operation: RuntimeArrange({
                target: { handle: canvas_handle, },
                first: selected[0],
                second: selected[1],
                rest: ids,
              }),
              label: "Arrange compactly",
              description: "Pack the selection into a compact strip",
            })
          }
          Ok({ anchor: request.anchor, items, })
        }
        Some(Source(graph)) => {
          graph.clear_selected_edge()
          let items : Array[CanvasContextMenuItem] = workflow_node_catalog().map(fn(
              item,
            ) {
              {
                operation: SourceAdd({
                  target: { handle: canvas_handle, },
                  binding_base: item.key,
                  constructor_name: item.key,
                }),
                label: item.label,
                description: item.description,
              }
            },
          )
          Ok({ anchor: request.anchor, items, })
        }
        None => Err(TargetExpired)
      }
    Edge(edge_id) =>
      match canvas_backing(canvas_handle) {
        Some(Runtime(runtime)) =>
          match find_edge_endpoints(runtime.state_peek(), edge_id) {
            Some((source, source_port, target, target_port)) => {
              runtime.select_edge(edge_id)
              Ok({
                anchor: request.anchor,
                items: [
                  {
                    operation: RuntimeDisconnect({
                      target: { handle: canvas_handle, },
                      edge: edge_id,
                    }),
                    label: "Disconnect edge",
                    description: source.to_string() +
                    "." +
                    source_port +
                    " → " +
                    target.to_string() +
                    "." +
                    target_port,
                  },
                ],
              })
            }
            None => Err(TargetExpired)
          }
        Some(Source(graph)) =>
          match
            find_edge_endpoints(source_graph_base_canvas_state(graph), edge_id) {
            Some((source, source_port, target, target_port)) => {
              graph.select_edge(edge_id)
              Ok({
                anchor: request.anchor,
                items: [
                  {
                    operation: SourceDisconnect({
                      owner: { handle: canvas_handle, },
                      source,
                      source_port,
                      target,
                      target_port,
                      edge: edge_id,
                    }),
                    label: "Disconnect edge",
                    description: source.to_string() +
                    "." +
                    source_port +
                    " → " +
                    target.to_string() +
                    "." +
                    target_port,
                  },
                ],
              })
            }
            None => Err(TargetExpired)
          }
        None => Err(TargetExpired)
      }
  }
}

///|
fn arrange_nodes(
  runtime : CanvasRuntime,
  operation : CanvasContextRuntimeArrange,
) -> Result[Unit, CanvasContextProblem] {
  let state = runtime.state_peek()
  let ids = [operation.first, operation.second]
  for id in operation.rest {
    ids.push(id)
  }
  let nodes : Array[CanvasNode] = []
  for id in ids {
    match @graph_model.find_node(state.nodes, id) {
      Some(node) => nodes.push(node)
      None => return Err(TargetExpired)
    }
  }
  try {
    let region_width = @layout.compact_region_width(nodes, gap=ARRANGE_GAP)
    let plan = @layout.arrange_with_skyline(
      nodes,
      region_width~,
      gap=ARRANGE_GAP,
    )
    runtime.sync_commit_state(
      @graph_model.record_action(state, plan.to_move_nodes()),
    )
    Ok(())
  } catch {
    @layout.NonFiniteGeometry | @layout.CoordinateOverflow =>
      Err(Rejected("arrangement geometry is not finite"))
    @layout.InvalidRegionWidth(_)
    | @layout.InvalidGap(_)
    | @layout.ItemTooWide(..)
    | @layout.NoPlacement(..) =>
      Err(Rejected("arrangement could not pack the captured nodes"))
  }
}

///|
fn apply_menu_operation(
  operation : CanvasContextOperation,
) -> CanvasContextOutcome {
  match operation {
    RuntimeAdd(op) =>
      match canvas_backing(op.target.handle) {
        Some(Runtime(runtime)) => {
          let state = runtime.state_peek()
          runtime.sync_document_action_state(
            (runtime.policy.add_node)(state, op.kind, op.position),
          )
          RuntimeApplied
        }
        _ => Failed(TargetExpired)
      }
    RuntimeArrange(op) =>
      match canvas_backing(op.target.handle) {
        Some(Runtime(runtime)) =>
          match arrange_nodes(runtime, op) {
            Ok(_) => RuntimeApplied
            Err(problem) => Failed(problem)
          }
        _ => Failed(TargetExpired)
      }
    RuntimeDisconnect(op) =>
      match canvas_backing(op.target.handle) {
        Some(Runtime(runtime)) =>
          if runtime.disconnect_edge(op.edge) {
            RuntimeApplied
          } else {
            Failed(TargetExpired)
          }
        _ => Failed(TargetExpired)
      }
    SourceAdd(op) =>
      match canvas_backing(op.target.handle) {
        Some(Source(graph)) => {
          let result = graph.insert_unique_result(
            op.binding_base,
            op.constructor_name,
          ) catch {
            Failure::Failure(detail) =>
              return SourceRejected(
                source_graph_result_json_for_graph(graph, false, Some(detail)),
                selection_changed=false,
              )
          }
          if result.applied {
            SourceApplied(result)
          } else {
            SourceRejected(result, selection_changed=false)
          }
        }
        _ => Failed(TargetExpired)
      }
    SourceDisconnect(op) =>
      match canvas_backing(op.owner.handle) {
        Some(Source(graph)) => {
          let live = match
            find_edge_endpoints(source_graph_base_canvas_state(graph), op.edge) {
            Some((source, source_port, target, target_port)) =>
              source == op.source &&
              source_port == op.source_port &&
              target == op.target &&
              target_port == op.target_port
            None => false
          }
          if !live {
            return Failed(TargetExpired)
          }
          // Disconnect consumes ephemeral selection even when source lowering
          // rejects the edit. Report that redraw separately from edit success.
          let selection_changed = graph.selected_edge is Some(_)
          let result = graph.disconnect_edge(op.edge) catch {
            Failure::Failure(detail) =>
              return SourceRejected(
                source_graph_result_json_for_graph(graph, false, Some(detail)),
                selection_changed~,
              )
          }
          if result.applied {
            SourceApplied(result)
          } else {
            SourceRejected(result, selection_changed~)
          }
        }
        _ => Failed(TargetExpired)
      }
  }
}
