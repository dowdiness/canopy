///|
const GRAPH_DSL_SAMPLE = "osc = sine(freq: 440Hz, wave: \"saw\") -> audio\nfilter = lowpass(input: osc, cutoff: 1200Hz, mode: warm)"

///|
fn ok_graph_doc(
  result : Result[@graph_dsl.GraphDoc, Array[String]],
) -> @graph_dsl.GraphDoc {
  match result {
    Ok(doc) => doc
    Err(messages) =>
      abort("expected graph-dsl projection, got: " + messages.join("; "))
  }
}

///|
fn ok_current_graph_doc(
  result : Result[@graph_dsl.GraphDoc, String],
) -> @graph_dsl.GraphDoc {
  match result {
    Ok(doc) => doc
    Err(message) => abort("expected current graph-dsl projection: " + message)
  }
}

///|
fn ok_last_good(doc : @graph_dsl.GraphDoc?) -> @graph_dsl.GraphDoc {
  match doc {
    Some(doc) => doc
    None => abort("expected last-good graph-dsl projection")
  }
}

///|
fn ok_lowered(
  edit : @graph_dsl.LoweredGraphEdit?,
) -> @graph_dsl.LoweredGraphEdit {
  match edit {
    Some(edit) => edit
    None => abort("expected lowered graph edit")
  }
}

///|
fn operation_result_applied(json_text : String) -> Bool {
  let json = @json.parse(json_text) catch {
    _ => abort("expected operation result JSON")
  }
  match json {
    Json::Object(fields) =>
      match fields.get("applied") {
        Some(Json::True) => true
        Some(Json::False) => false
        _ => abort("expected operation result applied flag")
      }
    _ => abort("expected operation result object")
  }
}

///|
fn operation_result_message(json_text : String) -> String? {
  let json = @json.parse(json_text) catch {
    _ => abort("expected operation result JSON")
  }
  match json {
    Json::Object(fields) =>
      match fields.get("message") {
        Some(Json::String(message)) => Some(message)
        None => None
        _ => abort("expected operation result message string")
      }
    _ => abort("expected operation result object")
  }
}

///|
fn render_selected_nodes(json_text : String) -> Array[String] {
  let json = @json.parse(json_text) catch {
    _ => abort("expected render state JSON")
  }
  match json {
    Json::Object(fields) =>
      match fields.get("selected_nodes") {
        Some(value) =>
          @json.from_json(value) catch {
            _ => abort("expected selected_nodes array")
          }
        None => abort("expected selected_nodes field")
      }
    _ => abort("expected render state object")
  }
}

///|
/// Current graph doc behind a registered handle.
fn handle_doc(handle : Int) -> @graph_dsl.GraphDoc {
  match source_graph_by_handle(handle) {
    Some(graph) => ok_current_graph_doc(graph.attachment.current_result())
    None => abort("expected source graph handle")
  }
}

///|
/// Tracker token (`NodeId`) for a binding behind a handle. Tokens are not
/// positionally predictable, so tests fetch them rather than hard-code them.
fn handle_token(handle : Int, binding : String) -> NodeId {
  required_canvas_id_for_binding(handle_doc(handle), binding)
}

///|
fn handle_token_str(handle : Int, binding : String) -> String {
  handle_token(handle, binding).to_string()
}

///|
fn ok_operation_log(json_text : String) -> Array[GraphOperation] {
  let json = @json.parse(json_text) catch {
    _ => abort("expected operation log JSON")
  }
  @json.from_json(json) catch {
    _ => abort("expected GraphOperation array")
  }
}

///|
fn graph_node_id(doc : @graph_dsl.GraphDoc, binding : String) -> String {
  match doc.find_node(binding) {
    Some(node) => node.id()
    None => abort("missing graph node: " + binding)
  }
}

///|
fn required_canvas_id_for_binding(
  doc : @graph_dsl.GraphDoc,
  binding : String,
) -> NodeId {
  match canvas_id_for_binding(doc, binding) {
    Some(id) => id
    None => abort("missing graph binding: " + binding)
  }
}

///|
test "graph-dsl projection maps into the canvas graph view model" {
  let doc = ok_graph_doc(@graph_dsl.project_graph_source(GRAPH_DSL_SAMPLE))
  let canvas = canvas_from_graph_doc(doc)
  match canvas.nodes {
    [osc, filter] => {
      inspect(osc.title, content="osc")
      inspect(osc.subtitle, content="sine")
      inspect(filter.title, content="filter")
      inspect(filter.subtitle, content="lowpass")
      match canvas.edges {
        [edge] => {
          @debug.assert_eq(edge.source, osc.id)
          @debug.assert_eq(edge.target, filter.id)
          inspect(edge.target_port, content="input")
        }
        _ => abort("expected exactly one canvas edge")
      }
    }
    _ => abort("expected exactly two canvas nodes")
  }
}

///|
test "SetParam lowers to an exact source edit and preserves graph ids" {
  let attachment = @graph_dsl.GraphAttachment::GraphAttachment(GRAPH_DSL_SAMPLE)
  let before = ok_current_graph_doc(attachment.current_result())
  let osc_id = graph_node_id(before, "osc")
  let filter_id = graph_node_id(before, "filter")
  let lowered = ok_lowered(before.lower_set_numeric("osc", "freq", "880"))
  match lowered.incremental_edit() {
    Some(edit) => attachment.apply_edit(edit, lowered.new_source())
    None => abort("expected one exact incremental edit")
  }
  inspect(attachment.state(), content="Current")
  let after = ok_current_graph_doc(attachment.current_result())
  match after.tokens_for_role(@graph_dsl.NumericParameter) {
    [number, ..] => inspect(number.text(), content="880")
    [] => abort("expected a numeric parameter token")
  }
  inspect(
    after.source(),
    content="osc = sine(freq: 880Hz, wave: \"saw\") -> audio\nfilter = lowpass(input: osc, cutoff: 1200Hz, mode: warm)",
  )
  @debug.assert_eq(graph_node_id(after, "osc"), osc_id)
  @debug.assert_eq(graph_node_id(after, "filter"), filter_id)
  let canvas = canvas_from_graph_doc(after)
  @debug.assert_eq(canvas.edges.length(), 1)
  attachment.dispose()
}

///|
test "ConnectPorts and AddNode lower through source and reparse to canvas graph" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let doc = ok_graph_doc(@graph_dsl.project_graph_source(source))
  let connect = ok_lowered(doc.lower_add_connection("meter", "osc"))
  inspect(
    connect.new_source(),
    content="osc = sine(freq: 440Hz)\nmeter = scope(input: osc)",
  )
  let connected = ok_graph_doc(
    @graph_dsl.project_graph_source(connect.new_source()),
  )
  let connected_canvas = canvas_from_graph_doc(connected)
  match connected_canvas.edges {
    [edge] => {
      @debug.assert_eq(
        edge.source,
        required_canvas_id_for_binding(connected, "osc"),
      )
      @debug.assert_eq(
        edge.target,
        required_canvas_id_for_binding(connected, "meter"),
      )
    }
    _ => abort("expected exactly one canvas edge")
  }

  let insert = ok_lowered(
    connected.lower_insert_node_binding("reverb", "plate"),
  )
  inspect(
    insert.new_source(),
    content="osc = sine(freq: 440Hz)\nmeter = scope(input: osc)\nreverb = plate()",
  )
  let inserted = ok_graph_doc(
    @graph_dsl.project_graph_source(insert.new_source()),
  )
  let inserted_canvas = canvas_from_graph_doc(inserted)
  match inserted_canvas.nodes {
    [_, _, reverb] => {
      inspect(reverb.title, content="reverb")
      inspect(reverb.subtitle, content="plate")
    }
    _ => abort("expected three canvas nodes after AddNode")
  }
}

///|
test "source-backed handle lowers GraphOperation through graph-dsl source" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  let connect = GraphOperation(
    ConnectPorts(
      handle_token(handle, "osc"),
      "out",
      handle_token(handle, "meter"),
      "input",
    ),
  )
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, connect.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="osc = sine(freq: 440Hz)\nmeter = scope(input: osc)",
  )
  // The lowering keys off title/subtitle; the payload id is a placeholder that
  // `realized_source_operation` replaces with the new node's tracker token.
  let added : CanvasNode = {
    id: NodeId(""),
    x: 0.0,
    y: 0.0,
    w: 250.0,
    h: 138.0,
    kind: Workflow(Custom("plate")),
    title: "reverb",
    subtitle: "plate",
    inputs: [],
    outputs: [],
    configured: true,
  }
  let insert = GraphOperation(AddNode(added))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, insert.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="osc = sine(freq: 440Hz)\nmeter = scope(input: osc)\nreverb = plate()",
  )
  let reverb_token = handle_token(handle, "reverb")
  let operations = ok_operation_log(get_source_graph_action_log(handle))
  match operations {
    [_, added] =>
      match added.action() {
        AddNode(node) => @debug.assert_eq(node.id, reverb_token)
        _ => abort("expected AddNode action")
      }
    _ => abort("expected two source-backed operations")
  }
  destroy_source_graph(handle)
}

///|
test "source-backed RenameNode updates binding and references" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope(input: osc)"
  let handle = create_source_graph(source)
  let osc_token = handle_token(handle, "osc")
  let rename = GraphOperation(RenameNode(osc_token, "lfo"))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, rename.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="lfo = sine(freq: 440Hz)\nmeter = scope(input: lfo)",
  )
  let operations = ok_operation_log(get_source_graph_action_log(handle))
  match operations {
    [renamed] =>
      match renamed.action() {
        RenameNode(node_id, name) => {
          @debug.assert_eq(node_id, osc_token)
          inspect(name, content="lfo")
        }
        _ => abort("expected RenameNode action")
      }
    _ => abort("expected one source-backed rename operation")
  }
  destroy_source_graph(handle)
}

///|
test "source-backed RenameNode preserves layout keyed by binding" {
  let source = "osc = sine(freq: 440Hz)"
  let handle = create_source_graph(source)
  match source_graph_by_handle(handle) {
    Some(graph) => graph.layout = [{ binding: "osc", x: 42.0, y: 24.0 }]
    None => abort("expected source graph handle")
  }
  let rename = GraphOperation(RenameNode(handle_token(handle, "osc"), "lfo"))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, rename.to_json().stringify()),
    ),
    content="true",
  )
  match source_graph_by_handle(handle) {
    Some(graph) =>
      match graph.layout {
        [position] => {
          inspect(position.binding, content="lfo")
          inspect(position.x, content="42")
          inspect(position.y, content="24")
        }
        _ => abort("expected one layout position")
      }
    None => abort("expected source graph handle")
  }
  destroy_source_graph(handle)
}

///|
test "source-backed RenameNode carries selection to the new token" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  let osc = handle_token_str(handle, "osc")
  source_graph_pointer_down(handle, osc, 0.0, 0.0)
  source_graph_pointer_up(handle, osc, "", false)
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [osc],
  )
  let rename = GraphOperation(RenameNode(handle_token(handle, "osc"), "lfo"))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, rename.to_json().stringify()),
    ),
    content="true",
  )
  // Renaming changes the token (it embeds the binding); the rename-local hook
  // carries the live selection forward to lfo's new token rather than dropping it.
  let lfo = handle_token_str(handle, "lfo")
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [lfo],
  )
  destroy_source_graph(handle)
}

///|
test "source-backed SetNodeParam edits a numeric parameter token" {
  let source = "osc = sine(freq: 440Hz, wave: \"saw\")\nmeter = scope()"
  let handle = create_source_graph(source)
  let osc_token = handle_token(handle, "osc")
  let set_param = GraphOperation(SetNodeParam(osc_token, "freq", "880"))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, set_param.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="osc = sine(freq: 880Hz, wave: \"saw\")\nmeter = scope()",
  )
  let operations = ok_operation_log(get_source_graph_action_log(handle))
  match operations {
    [edited] =>
      match edited.action() {
        SetNodeParam(node_id, parameter, value) => {
          @debug.assert_eq(node_id, osc_token)
          inspect(parameter, content="freq")
          inspect(value, content="880")
        }
        _ => abort("expected SetNodeParam action")
      }
    _ => abort("expected one source-backed parameter operation")
  }
  destroy_source_graph(handle)
}

///|
test "source-backed SetNodeParam rejects non-numeric source text" {
  let source = "osc = sine(freq: 440Hz)"
  let handle = create_source_graph(source)
  let set_param = GraphOperation(
    SetNodeParam(handle_token(handle, "osc"), "freq", "880Hz"),
  )
  let result = apply_source_graph_operation(
    handle,
    set_param.to_json().stringify(),
  )
  inspect(operation_result_applied(result), content="false")
  inspect(get_source_graph_source(handle), content=source)
  inspect(get_source_graph_action_log(handle), content="[]")
  destroy_source_graph(handle)
}

///|
test "source-backed DeleteNodes removes a safe binding line" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope(input: osc)\nreverb = plate()"
  let handle = create_source_graph(source)
  let meter_token = handle_token(handle, "meter")
  let delete = GraphOperation(DeleteNodes([meter_token]))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, delete.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="osc = sine(freq: 440Hz)\nreverb = plate()",
  )
  let operations = ok_operation_log(get_source_graph_action_log(handle))
  match operations {
    [deleted] =>
      match deleted.action() {
        DeleteNodes(nodes) => @debug.assert_eq(nodes, [meter_token])
        _ => abort("expected DeleteNodes action")
      }
    _ => abort("expected one source-backed delete operation")
  }
  destroy_source_graph(handle)
}

///|
test "source-backed DeleteNodes rejects survivor references" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope(input: osc)"
  let handle = create_source_graph(source)
  let delete = GraphOperation(DeleteNodes([handle_token(handle, "osc")]))
  let result = apply_source_graph_operation(
    handle,
    delete.to_json().stringify(),
  )
  inspect(operation_result_applied(result), content="false")
  match operation_result_message(result) {
    Some(message) =>
      inspect(message.contains("still references"), content="true")
    None => abort("expected DeleteNodes rejection message")
  }
  inspect(get_source_graph_source(handle), content=source)
  inspect(get_source_graph_action_log(handle), content="[]")
  destroy_source_graph(handle)
}

///|
test "source-backed DeleteNodes allows deleting a referenced subgraph together" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope(input: osc)"
  let handle = create_source_graph(source)
  let delete = GraphOperation(
    DeleteNodes([handle_token(handle, "osc"), handle_token(handle, "meter")]),
  )
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, delete.to_json().stringify()),
    ),
    content="true",
  )
  inspect(get_source_graph_source(handle), content="")
  destroy_source_graph(handle)
}

///|
test "source-backed DeleteNodes clears transient selection after rewrite" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  let meter = handle_token_str(handle, "meter")
  source_graph_pointer_down(handle, meter, 0.0, 0.0)
  source_graph_pointer_up(handle, meter, "", false)
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [meter],
  )
  let delete = GraphOperation(DeleteNodes([handle_token(handle, "meter")]))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, delete.to_json().stringify()),
    ),
    content="true",
  )
  // Deleted node's token no longer resolves, so prune drops it.
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [],
  )
  destroy_source_graph(handle)
}

///|
test "source-backed DeleteNodes preserves selected survivor by stable token" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()\nreverb = plate()"
  let handle = create_source_graph(source)
  let reverb = handle_token_str(handle, "reverb")
  source_graph_pointer_down(handle, reverb, 0.0, 0.0)
  source_graph_pointer_up(handle, reverb, "", false)
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [reverb],
  )
  let delete = GraphOperation(DeleteNodes([handle_token(handle, "meter")]))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, delete.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="osc = sine(freq: 440Hz)\nreverb = plate()",
  )
  // The tracker keeps reverb's token across the delete, so selection survives
  // with no binding remap — the deleted node simply drops out.
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [reverb],
  )
  destroy_source_graph(handle)
}

///|
test "source-backed set_source reorder churns identity and clears selection" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  let meter = handle_token_str(handle, "meter")
  source_graph_pointer_down(handle, meter, 0.0, 0.0)
  source_graph_pointer_up(handle, meter, "", false)
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [meter],
  )
  // Whole-source set_source is the reset-only path; an atomic reorder churns
  // tracker tokens (residual limitation), so the selected token no longer
  // resolves and is pruned. User-facing reorders go through editor deltas,
  // which preserve identity (next test).
  set_source_graph_source(handle, "meter = scope()\nosc = sine(freq: 440Hz)")
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [],
  )
  destroy_source_graph(handle)
}

///|
test "source-backed editor-delta reorder preserves selection by token" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  let graph = match source_graph_by_handle(handle) {
    Some(graph) => graph
    None => abort("expected source graph handle")
  }
  let meter = handle_token_str(handle, "meter")
  source_graph_pointer_down(handle, meter, 0.0, 0.0)
  source_graph_pointer_up(handle, meter, "", false)
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [meter],
  )
  // Reorder as the editor would: delete the first line, then re-insert it after
  // the second. CodeMirror reports both ranges in pre-transaction coordinates;
  // applied as ordered deltas, the tracker realigns identity, so `meter`'s token
  // is unchanged and its selection survives.
  let first_line = "osc = sine(freq: 440Hz)\n"
  let reordered = "meter = scope()\nosc = sine(freq: 440Hz)"
  let _ = graph.apply_codemirror_changes(
    [
      @codemirror.ChangeDelta::new(0, first_line.length(), ""),
      @codemirror.ChangeDelta::new(
        source.length(),
        source.length(),
        "\nosc = sine(freq: 440Hz)",
      ),
    ],
    reordered,
  )
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [meter],
  )
  destroy_source_graph(handle)
}

///|
test "source-backed source edit clears selection when binding is removed" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  let meter = handle_token_str(handle, "meter")
  source_graph_pointer_down(handle, meter, 0.0, 0.0)
  source_graph_pointer_up(handle, meter, "", false)
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [meter],
  )
  set_source_graph_source(handle, "osc = sine(freq: 440Hz)")
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [],
  )
  destroy_source_graph(handle)
}

///|
/// Guards the invalid-source branch of `set_source_graph_source_checked`:
/// selection must NOT be pruned when reparse fails, because render falls back
/// to the last-good doc whose tokens still resolve the stored selection.
test "source-backed source edit keeps selection while source is invalid" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  let meter = handle_token_str(handle, "meter")
  source_graph_pointer_down(handle, meter, 0.0, 0.0)
  source_graph_pointer_up(handle, meter, "", false)
  set_source_graph_source(handle, "osc = sine(freq: )")
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [meter],
  )
  destroy_source_graph(handle)
}

///|
test "source-backed source edit preserves index-0 survivor when later binding removed" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  let osc = handle_token_str(handle, "osc")
  source_graph_pointer_down(handle, osc, 0.0, 0.0)
  source_graph_pointer_up(handle, osc, "", false)
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [osc],
  )
  // Removing a later binding is content-preserving for the survivor, so osc's
  // token is unchanged and its selection persists.
  set_source_graph_source(handle, "osc = sine(freq: 440Hz)")
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [osc],
  )
  destroy_source_graph(handle)
}

///|
test "source-backed source reorder that drops the selected node clears selection" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()\nreverb = plate()"
  let handle = create_source_graph(source)
  let meter = handle_token_str(handle, "meter")
  source_graph_pointer_down(handle, meter, 0.0, 0.0)
  source_graph_pointer_up(handle, meter, "", false)
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [meter],
  )
  // Reorder the survivors and drop the selected binding (meter) in one edit.
  set_source_graph_source(handle, "reverb = plate()\nosc = sine(freq: 440Hz)")
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [],
  )
  destroy_source_graph(handle)
}

///|
test "source-backed set_source reorder churns multi-selection (residual)" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()\nreverb = plate()"
  let handle = create_source_graph(source)
  let osc = handle_token(handle, "osc")
  let reverb = handle_token(handle, "reverb")
  match source_graph_by_handle(handle) {
    Some(graph) =>
      graph.interaction = {
        dragging: None,
        panning: None,
        connecting: None,
        selected: Some(osc),
        selected_nodes: [osc, reverb],
        pointer_down: false,
        did_move: false,
      }
    None => abort("expected source graph handle")
  }
  // Atomic set_source reorder churns both selected tokens; prune drops them.
  // (Editor-delta reorders, the user-facing path, preserve identity.)
  set_source_graph_source(
    handle, "reverb = plate()\nmeter = scope()\nosc = sine(freq: 440Hz)",
  )
  @debug.assert_eq(
    render_selected_nodes(get_source_graph_render_state(handle)),
    [],
  )
  destroy_source_graph(handle)
}

///|
test "source-backed DisconnectPorts removes only the target input reference" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope(input: osc, gain: 2)\ntap = scope(input: osc)"
  let handle = create_source_graph(source)
  let osc_token = handle_token(handle, "osc")
  let meter_token = handle_token(handle, "meter")
  let disconnect = GraphOperation(
    DisconnectPorts(osc_token, "out", meter_token, "input"),
  )
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, disconnect.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="osc = sine(freq: 440Hz)\nmeter = scope(gain: 2)\ntap = scope(input: osc)",
  )
  let operations = ok_operation_log(get_source_graph_action_log(handle))
  match operations {
    [disconnected] =>
      match disconnected.action() {
        DisconnectPorts(source, source_port, target, target_port) => {
          @debug.assert_eq(source, osc_token)
          inspect(source_port, content="out")
          @debug.assert_eq(target, meter_token)
          inspect(target_port, content="input")
        }
        _ => abort("expected DisconnectPorts action")
      }
    _ => abort("expected one source-backed disconnect operation")
  }
  destroy_source_graph(handle)
}

///|
test "source-backed DisconnectPorts removes a trailing input reference" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope(gain: 2, input: osc)"
  let handle = create_source_graph(source)
  let disconnect = GraphOperation(
    DisconnectPorts(
      handle_token(handle, "osc"),
      "out",
      handle_token(handle, "meter"),
      "input",
    ),
  )
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, disconnect.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="osc = sine(freq: 440Hz)\nmeter = scope(gain: 2)",
  )
  destroy_source_graph(handle)
}

///|
test "source-backed DisconnectPorts consumes a valid trailing comma" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope(input: osc,)"
  let handle = create_source_graph(source)
  let disconnect = GraphOperation(
    DisconnectPorts(
      handle_token(handle, "osc"),
      "out",
      handle_token(handle, "meter"),
      "input",
    ),
  )
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, disconnect.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="osc = sine(freq: 440Hz)\nmeter = scope()",
  )
  destroy_source_graph(handle)
}

///|
test "source-backed unique insert chooses a fresh graph-dsl binding" {
  let handle = create_source_graph("reverb = plate()")
  inspect(
    operation_result_applied(
      source_graph_insert_unique(handle, "reverb", "plate"),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="reverb = plate()\nreverb2 = plate()",
  )
  let reverb2_token = handle_token(handle, "reverb2")
  let operations = ok_operation_log(get_source_graph_action_log(handle))
  match operations {
    [added] =>
      match added.action() {
        AddNode(node) => {
          inspect(node.title, content="reverb2")
          @debug.assert_eq(node.id, reverb2_token)
        }
        _ => abort("expected AddNode action")
      }
    _ => abort("expected one source-backed unique insert operation")
  }
  destroy_source_graph(handle)
}

///|
test "source-backed handle rejects local graph operations without mutating source" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  let viewport : Viewport = { x: 12.0, y: 24.0, scale: 2.0 }
  let local_operation = GraphOperation(SetViewport(viewport))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(
        handle,
        local_operation.to_json().stringify(),
      ),
    ),
    content="false",
  )
  inspect(get_source_graph_source(handle), content=source)
  inspect(get_source_graph_action_log(handle), content="[]")
  destroy_source_graph(handle)
}

///|
test "source-backed handle reports invalid source apply status" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  inspect(
    operation_result_applied(
      set_source_graph_source_result(handle, "osc = sine(freq: )"),
    ),
    content="false",
  )
  inspect(get_source_graph_source(handle), content="osc = sine(freq: )")
  inspect(
    operation_result_applied(
      set_source_graph_source_result(handle, "osc = sine(input: missing)"),
    ),
    content="false",
  )
  inspect(get_source_graph_source(handle), content="osc = sine(input: missing)")
  inspect(
    operation_result_applied(set_source_graph_source_result(handle, source)),
    content="true",
  )
  inspect(get_source_graph_source(handle), content=source)
  destroy_source_graph(handle)
}

///|
test "source-backed handle rejects graph operations while source is invalid" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  let osc = handle_token(handle, "osc")
  let meter = handle_token(handle, "meter")
  set_source_graph_source(handle, "osc = sine(freq: )")
  let connect = GraphOperation(ConnectPorts(osc, "out", meter, "input"))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, connect.to_json().stringify()),
    ),
    content="false",
  )
  inspect(get_source_graph_source(handle), content="osc = sine(freq: )")
  destroy_source_graph(handle)
}

///|
/// Option (b) invariant: editor-originated CodeMirror edits are NOT rolled back
/// on parse failure, so `source` tracks the editor through transiently-invalid
/// states and the next valid keystroke recovers incrementally — preserving node
/// identity, the property a whole-source reparse would churn.
test "source-backed CodeMirror edit recovers from invalid state preserving node identity" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  let graph = match source_graph_by_handle(handle) {
    Some(graph) => graph
    None => abort("expected source graph handle")
  }
  let before = ok_current_graph_doc(graph.attachment.current_result())
  let osc_id = graph_node_id(before, "osc")
  let meter_id = graph_node_id(before, "meter")

  // Delete `440Hz`, leaving the source transiently invalid. No rollback: the
  // source follows the editor while the canvas keeps rendering last-good.
  let invalid_doc = "osc = sine(freq: )\nmeter = scope()"
  let reject = graph.apply_codemirror_changes(
    [@codemirror.ChangeDelta::new(17, 22, "")],
    invalid_doc,
  )
  inspect(reject.applied, content="false")
  @debug.assert_eq(graph.source, invalid_doc)
  @debug.assert_eq(
    graph_node_id(ok_last_good(graph.attachment.last_good()), "osc"),
    osc_id,
  )

  // Type a new valid value. Recovery lowers incrementally against the (invalid)
  // editor text, so node identity is stable end to end.
  let valid_doc = "osc = sine(freq: 220Hz)\nmeter = scope()"
  let accept = graph.apply_codemirror_changes(
    [@codemirror.ChangeDelta::new(17, 17, "220Hz")],
    valid_doc,
  )
  inspect(accept.applied, content="true")
  @debug.assert_eq(graph.source, valid_doc)
  let after = ok_current_graph_doc(graph.attachment.current_result())
  @debug.assert_eq(graph_node_id(after, "osc"), osc_id)
  @debug.assert_eq(graph_node_id(after, "meter"), meter_id)
  destroy_source_graph(handle)
}

///|
/// Option (b) stale-editor guard: when `source` has diverged from the editor
/// (an out-of-band graph mutation moved it), the incremental result no longer
/// equals the editor's authoritative buffer, so the adapter reparses that
/// buffer (editor-wins) instead of splicing the deltas onto a mismatched base.
test "source-backed CodeMirror edit reparses editor text when source diverged" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  let graph = match source_graph_by_handle(handle) {
    Some(graph) => graph
    None => abort("expected source graph handle")
  }
  // The editor's authoritative buffer (e.g. after a reorder) does not match
  // what the delta produces from the current `source`, modelling a stale base.
  let editor_doc = "meter = scope()\nosc = sine(freq: 440Hz)"
  let result = graph.apply_codemirror_changes(
    [@codemirror.ChangeDelta::new(0, 0, "x")],
    editor_doc,
  )
  // No corruption: source equals the editor's text exactly, reparsed valid.
  inspect(result.applied, content="true")
  @debug.assert_eq(graph.source, editor_doc)
  destroy_source_graph(handle)
}

///|
test "invalid source keeps last-good canvas graph available" {
  let attachment = @graph_dsl.GraphAttachment::GraphAttachment(GRAPH_DSL_SAMPLE)
  let good = ok_current_graph_doc(attachment.current_result())
  let good_canvas = canvas_from_graph_doc(good)

  attachment.set_source("osc = sine(freq: )")
  inspect(attachment.state(), content="ParserBlocked")
  let parser_blocked = ok_last_good(attachment.last_good())
  @debug.assert_eq(parser_blocked, good)
  @debug.assert_eq(
    canvas_from_graph_doc(parser_blocked).nodes.length(),
    good_canvas.nodes.length(),
  )

  attachment.set_source("osc = sine(input: missing)")
  inspect(attachment.state(), content="ProjectionBlocked")
  let projection_blocked = ok_last_good(attachment.last_good())
  @debug.assert_eq(projection_blocked, good)
  @debug.assert_eq(
    canvas_from_graph_doc(projection_blocked).edges.length(),
    good_canvas.edges.length(),
  )
  attachment.dispose()
}
