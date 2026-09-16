///|
fn test_background_target() -> CanvasContextTarget {
  Background(insert_at=try! ScreenPoint::from_xy(x=0.0, y=0.0))
}

///|
fn test_context_prepare(
  handle : Int,
  target : CanvasContextTarget,
) -> CanvasContextPreparedMenu raise {
  match
    build_context_menu(handle, {
      anchor: @context_menu.Point(x=10.0F, y=20.0F),
      target,
    }) {
    Ok(prepared) => prepared
    Err(problem) => fail(problem.message())
  }
}

///|
fn test_context_runtime(handle : Int) -> CanvasRuntime raise {
  match canvas_backing(handle) {
    Some(Runtime(runtime)) => runtime
    _ => fail("expected a runtime canvas")
  }
}

///|
fn test_context_open(
  prepared : CanvasContextPreparedMenu,
) -> CanvasContextMenuModel {
  {
    context_menu: @context_menu.Model::new(id="test-menu").open(
      anchor=prepared.anchor,
      items=prepared.items[:],
    ),
    problem: None,
  }
}

///|
fn test_context_binding(
  handle : Int,
  on_change? : () -> Unit = () => (),
  on_source_result? : (String) -> Unit = _ => (),
) -> CanvasContextMenuBinding {
  { handle, on_change, on_source_result, }
}

///|
fn test_select_node(
  runtime : CanvasRuntime,
  id : NodeId,
  additive? : Bool = false,
) -> Unit {
  let node = contract_state_node(runtime.state_peek(), id)
  let (x, y) = contract_screen_point(
    runtime.render_state().viewport,
    node.position().x(),
    node.position().y(),
  )
  ignore(runtime.pointer_down(Some(id), x, y))
  runtime.pointer_up(id.to_string(), "", additive)
}

///|
test "background menu stays catalog-only without a multi-selection" {
  let handle = create_canvas()
  let prepared = test_context_prepare(handle, test_background_target())
  assert_true(
    prepared.items.iter().all(item => item.operation is RuntimeAdd(_)),
  )
  let runtime = test_context_runtime(handle)
  let before = runtime.state_peek().nodes.length()
  guard apply_menu_operation(prepared.items[0].operation) is RuntimeApplied else {
    fail("catalog operation must be executable")
  }
  assert_eq(runtime.state_peek().nodes.length(), before + 1)
  assert_eq(runtime.action_log_snapshot().length(), 1)
}

///|
test "arrangement acts on the captured selection, not its replacement" {
  let handle = create_canvas()
  let runtime = test_context_runtime(handle)
  let node1 = NodeId("1")
  let node2 = NodeId("2")
  test_select_node(runtime, node1)
  test_select_node(runtime, node2, additive=true)

  let prepared = test_context_prepare(handle, test_background_target())
  guard prepared.items[0].operation is RuntimeArrange(_) else {
    fail("a multi-selection should offer arrangement")
  }
  test_select_node(runtime, NodeId("3"))
  guard apply_menu_operation(prepared.items[0].operation) is RuntimeApplied else {
    fail("captured arrangement should survive replacement of current selection")
  }
  match runtime.action_log_snapshot().last().unwrap().action() {
    MoveNodes(positions) => assert_eq(positions.map(p => p.id), [node1, node2])
    _ => fail("expected a recorded arrangement")
  }
}

///|
test "background menu hides arrange on a source-backed graph" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  let prepared = test_context_prepare(handle, test_background_target())
  assert_true(prepared.items.iter().all(item => item.operation is SourceAdd(_)))
  guard apply_menu_operation(prepared.items[0].operation)
    is SourceApplied(result) else {
    fail("source catalog operation should apply")
  }
  assert_true(result.source.contains("timer = timer()"))
  assert_eq(result.action_count, 1)
  destroy_source_graph(handle)
}

///|
test "insertion preserves the world point captured before viewport changes" {
  let handle = create_canvas()
  let runtime = test_context_runtime(handle)
  let screen = try! ScreenPoint::from_xy(x=400.0, y=300.0)
  let expected = try! runtime.state_peek().viewport.screen_to_world(screen)
  let prepared = test_context_prepare(handle, Background(insert_at=screen))
  runtime.zoom(-200.0, 0, false, 100.0, 100.0)
  guard apply_menu_operation(prepared.items[0].operation) is RuntimeApplied else {
    fail("expected insertion")
  }
  match runtime.action_log_snapshot().last().unwrap().action() {
    AddNode(node) => assert_eq(node.position(), expected)
    _ => fail("expected one insertion")
  }
}

///|
test "expired edge preparation and execution are explicit failures" {
  let handle = create_canvas()
  let runtime = test_context_runtime(handle)
  let edge = runtime.state_peek().edges[0].id
  let prepared = test_context_prepare(handle, Edge(edge))
  assert_true(runtime.disconnect_edge(edge))
  guard apply_menu_operation(prepared.items[0].operation)
    is Failed(TargetExpired) else {
    fail("removed edge must not report success")
  }
  assert_eq(runtime.action_log_snapshot().length(), 1)
  guard build_context_menu(handle, {
      anchor: @context_menu.Point(x=0.0F, y=0.0F),
      target: Edge(edge),
    })
    is Err(TargetExpired) else {
    fail("removed edge must not produce a fabricated disconnect menu")
  }
}

///|
test "disposed source graph cannot execute a previously prepared operation" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)")
  let prepared = test_context_prepare(handle, test_background_target())
  destroy_source_graph(handle)
  guard apply_menu_operation(prepared.items[0].operation)
    is Failed(TargetExpired) else {
    fail("disposed graph must not accept an operation")
  }
}

///|
async test "choosing an item closes the menu and ignores further activation" {
  let handle = create_canvas()
  let runtime = test_context_runtime(handle)
  let prepared = test_context_prepare(handle, test_background_target())
  let initial = test_context_open(prepared)
  let activation = menu_intent(initial, @context_menu.Activate(0))
  let binding = test_context_binding(handle)
  let emit = @cmd.Emit(_ => @rabbita.none)
  let (closed, first) = context_menu_update(binding, initial, activation, emit)
  let (_, duplicate) = context_menu_update(binding, closed, activation, emit)
  @rabbita_testing.run_cmd(first)
  @rabbita_testing.run_cmd(duplicate)
  assert_eq(runtime.action_log_snapshot().length(), 1)
  assert_false(closed.context_menu.is_open())
}

///|
async test "source rejection is visible and does not send a success notification" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)")
  let prepared = test_context_prepare(handle, test_background_target())
  set_source_graph_source(handle, "osc = sine(")
  let before = get_source_graph_source(handle)
  let outcome = apply_menu_operation(prepared.items[0].operation)
  guard outcome is SourceRejected(_, ..) else {
    fail("invalid source must reject insertion")
  }
  let changes = @ref.Ref(0)
  let reports = @ref.Ref(0)
  let binding = test_context_binding(handle, on_change=() => changes.val += 1, on_source_result=_ => {
    reports.val += 1
  })
  let closed = context_menu_model()
  let (failed, command) = context_menu_update(
    binding,
    closed,
    Completed(outcome),
    @cmd.Emit(_ => @rabbita.none),
  )
  @rabbita_testing.run_cmd(command)
  assert_true(failed.problem is Some(Rejected(_)))
  assert_eq(changes.val, 0)
  assert_eq(reports.val, 1)
  assert_eq(get_source_graph_source(handle), before)
  destroy_source_graph(handle)
}

///|
async test "a rejected opening leaves the original menu action usable" {
  let handle = create_canvas()
  let runtime = test_context_runtime(handle)
  let edge = runtime.state_peek().edges[0].id
  let initial = test_context_open(test_context_prepare(handle, Edge(edge)))
  let (rejected, _) = context_menu_update(
    test_context_binding(handle),
    initial,
    Request(Err(Rejected("invalid coordinate"))),
    @cmd.Emit(_ => @rabbita.none),
  )
  assert_true(rejected.problem is Some(Rejected(_)))
  assert_eq(runtime.selected_edge(), Some(edge))
  assert_eq(runtime.action_log_snapshot().length(), 0)
  let (_, activate) = context_menu_update(
    test_context_binding(handle),
    rejected,
    menu_intent(initial, @context_menu.Activate(0)),
    @cmd.Emit(_ => @rabbita.none),
  )
  @rabbita_testing.run_cmd(activate)
  assert_false(runtime.state_peek().edges.iter().any(item => item.id == edge))
  assert_eq(runtime.action_log_snapshot().length(), 1)
}

///|
async test "rejected source disconnect clears selection without claiming an edit" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  assert_true(source_graph_connect_sample_result(handle).applied)
  let graph = source_graph_by_handle(handle).unwrap()
  let edge = source_graph_base_canvas_state(graph).edges[0].id
  let prepared = test_context_prepare(handle, Edge(edge))
  set_source_graph_source(handle, "osc = sine(")
  let before = graph.source
  let outcome = apply_menu_operation(prepared.items[0].operation)
  guard outcome is SourceRejected(result, ..) else {
    fail("invalid source must reject disconnection")
  }
  assert_false(result.applied)
  assert_true(graph.selected_edge is None)
  assert_eq(graph.source, before)
  assert_eq(graph.action_log.length(), 1)
  let renders = @ref.Ref(0)
  let reports = @ref.Ref(0)
  let binding = test_context_binding(handle, on_change=() => renders.val += 1, on_source_result=_ => {
    reports.val += 1
  })
  let model = context_menu_model()
  let (_, command) = context_menu_update(
    binding,
    model,
    Completed(outcome),
    @cmd.Emit(_ => @rabbita.none),
  )
  @rabbita_testing.run_cmd(command)
  assert_eq(renders.val, 1)
  assert_eq(reports.val, 1)
  destroy_source_graph(handle)
}
