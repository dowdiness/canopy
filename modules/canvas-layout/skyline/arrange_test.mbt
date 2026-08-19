///|
fn node_id(n : Int) -> @graph_model.NodeId {
  @graph_model.NodeId(n.to_string())
}

///|
fn world(x : Double, y : Double) -> @spatial.WorldPoint {
  try! @spatial.WorldPoint::from_xy(x~, y~)
}

///|
fn sized_node(
  id : Int,
  x : Double,
  y : Double,
  width~ : Double,
  height~ : Double,
) -> @graph_model.CanvasNode {
  let base = @graph_model.make_workflow_node(
    node_id(id),
    @graph_model.WorkflowNodeKind::TimerTrigger,
    world(x, y),
  )
  @graph_model.CanvasNode::from_parts(
    id=base.id,
    position=base.position(),
    size=try! @graph_model.NodeSize::from_wh(width~, height~),
    kind=base.kind,
    title=base.title,
    subtitle=base.subtitle,
    inputs=base.inputs,
    outputs=base.outputs,
    configured=base.configured,
  )
}

///|
test "empty selection yields an empty plan" {
  let plan = try! arrange_with_skyline([], region_width=400.0)
  debug_inspect(plan.positions.length(), content="0")
}

///|
test "packs two nodes on one row when the region is wide enough" {
  let nodes = [
    sized_node(1, 100.0, 50.0, width=244.0, height=132.0),
    sized_node(2, 400.0, 80.0, width=260.0, height=148.0),
  ]
  let plan = try! arrange_with_skyline(nodes, region_width=504.0)
  debug_inspect(plan.positions.length(), content="2")
  debug_inspect(
    plan.positions[0].id.to_string(),
    content=(
      #|"1"
    ),
  )
  debug_inspect(plan.positions[0].point.x(), content="100")
  debug_inspect(plan.positions[0].point.y(), content="50")
  debug_inspect(
    plan.positions[1].id.to_string(),
    content=(
      #|"2"
    ),
  )
  debug_inspect(plan.positions[1].point.x(), content="344")
  debug_inspect(plan.positions[1].point.y(), content="50")
}

///|
test "stacks nodes when the region is only wide enough for one" {
  let nodes = [
    sized_node(1, 100.0, 50.0, width=244.0, height=132.0),
    sized_node(2, 400.0, 80.0, width=260.0, height=148.0),
  ]
  let plan = try! arrange_with_skyline(nodes, region_width=300.0)
  debug_inspect(plan.positions[0].point.x(), content="100")
  debug_inspect(plan.positions[0].point.y(), content="50")
  debug_inspect(plan.positions[1].point.x(), content="100")
  debug_inspect(plan.positions[1].point.y(), content="182")
}

///|
test "gap is reserved between packed nodes" {
  let nodes = [
    sized_node(1, 0.0, 0.0, width=10.0, height=10.0),
    sized_node(2, 40.0, 5.0, width=10.0, height=10.0),
  ]
  let plan = try! arrange_with_skyline(nodes, region_width=40.0, gap=8.0)
  debug_inspect(plan.positions[0].point.x(), content="0")
  debug_inspect(plan.positions[1].point.x(), content="18")
}

///|
test "rejects a non-positive region width" {
  let result : Result[LayoutPlan, LayoutError] = Ok(
    arrange_with_skyline([], region_width=0.0),
  ) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(InvalidRegionWidth(0))")
}

///|
test "lowers to MoveNodes without inventing a new graph operation" {
  let nodes = [
    sized_node(1, 20.0, 30.0, width=10.0, height=10.0),
    sized_node(2, 80.0, 90.0, width=10.0, height=10.0),
  ]
  let plan = try! arrange_with_skyline(nodes, region_width=40.0)
  debug_inspect(
    plan.to_move_nodes(),
    content=(
      #|MoveNodes(
      #|  [
      #|    { id: NodeId("1"), point: { x: 20, y: 30 } },
      #|    { id: NodeId("2"), point: { x: 30, y: 30 } },
      #|  ],
      #|)
    ),
  )
}

///|
test "MoveNodes apply updates canvas positions from a layout plan" {
  let nodes = [
    sized_node(1, 20.0, 30.0, width=10.0, height=10.0),
    sized_node(2, 80.0, 90.0, width=10.0, height=10.0),
  ]
  let document : @graph_model.CanvasDocument = {
    nodes,
    edges: [],
    next_node_id: 3,
  }
  let state = @graph_model.canvas_state_from_parts(
    document,
    @graph_model.default_viewport(),
    @graph_model.empty_interaction(),
    [],
  )
  let plan = try! arrange_with_skyline(nodes, region_width=40.0)
  let next = @graph_model.apply_action(state, plan.to_move_nodes())
  let first = @graph_model.find_node(next.nodes, node_id(1)).unwrap()
  let second = @graph_model.find_node(next.nodes, node_id(2)).unwrap()
  debug_inspect(first.position().x(), content="20")
  debug_inspect(first.position().y(), content="30")
  debug_inspect(second.position().x(), content="30")
  debug_inspect(second.position().y(), content="30")
}

///|
test "compact region is twice the widest node plus gap" {
  let nodes = [
    sized_node(1, 0.0, 0.0, width=244.0, height=132.0),
    sized_node(2, 0.0, 0.0, width=260.0, height=148.0),
  ]
  debug_inspect(try! compact_region_width(nodes, gap=16.0), content="552")
}

///|
test "compact region rejects an empty selection" {
  let result : Result[Double, LayoutError] = Ok(
    compact_region_width([], gap=16.0),
  ) catch {
    error => Err(error)
  }
  debug_inspect(result, content="Err(InvalidRegionWidth(0))")
}

///|
test "too-wide item reports packed widths" {
  let nodes = [sized_node(1, 0.0, 0.0, width=100.0, height=10.0)]
  let result : Result[LayoutPlan, LayoutError] = Ok(
    arrange_with_skyline(nodes, region_width=10.0),
  ) catch {
    error => Err(error)
  }
  debug_inspect(
    result,
    content="Err(ItemTooWide(item_width=1600, bin_width=160))",
  )
}

///|
test "compact region fits two nodes after length quantization" {
  let nodes = [
    sized_node(1, 0.0, 0.0, width=10.1, height=10.0),
    sized_node(2, 80.0, 0.0, width=10.1, height=10.0),
  ]
  let region = try! compact_region_width(nodes, gap=8.0)
  let plan = try! arrange_with_skyline(nodes, region_width=region, gap=8.0)
  debug_inspect(plan.positions[0].point.x(), content="0")
  debug_inspect(plan.positions[0].point.y(), content="0")
  debug_inspect(plan.positions[1].point.x(), content="18.125")
  debug_inspect(plan.positions[1].point.y(), content="0")
}
