///|
const CANVAS_RENDER_LAYER_ID : String = "canvas-render-layer"

///|
const CANVAS_RENDER_STATE_EVENT : String = "canopy-canvas-render-state"

///|
priv struct CanvasRenderLayerViewport {
  x : Double
  y : Double
  scale : Double
} derive(Eq, FromJson)

///|
priv struct CanvasRenderLayerSnapshot {
  viewport : CanvasRenderLayerViewport
  nodes : Array[NodeJson]
  edges : Array[EdgeJson]
  selected_nodes : Array[String]
  connecting : ConnectingJson?
  input_compatibility : Array[PortCompatibilityJson]
  validation : Array[ValidationJson]
} derive(Eq)

///|
priv struct CanvasRenderLayerState {
  snapshot : CanvasRenderLayerSnapshot?
} derive(Eq)

///|
priv enum CanvasRenderLayerMsg {
  RenderState(String)
}

///|
fn parse_connecting_path_d(fields : Map[String, Json]) -> String? {
  match fields.get("path_d") {
    None | Some(Null) => None
    Some(String(value)) => Some(value)
    Some(Array([value])) => {
      let path_d : String = @json.from_json(value) catch { _ => return None }
      Some(path_d)
    }
    Some(_) => None
  }
}

///|
fn parse_connecting_json(fields : Map[String, Json]) -> ConnectingJson? {
  let from : String = match fields.get("from") {
    Some(value) => @json.from_json(value) catch { _ => return None }
    None => return None
  }
  let from_port : String = match fields.get("from_port") {
    Some(value) => @json.from_json(value) catch { _ => return None }
    None => return None
  }
  let cursor_x : Double = match fields.get("cursor_x") {
    Some(value) => @json.from_json(value) catch { _ => return None }
    None => return None
  }
  let cursor_y : Double = match fields.get("cursor_y") {
    Some(value) => @json.from_json(value) catch { _ => return None }
    None => return None
  }
  Some({
    from,
    from_port,
    cursor_x,
    cursor_y,
    path_d: parse_connecting_path_d(fields),
  })
}

///|
fn parse_canvas_render_layer_snapshot(
  json_text : String,
) -> CanvasRenderLayerSnapshot? {
  let json = @json.parse(json_text) catch { _ => return None }
  match json {
    Object(fields) => {
      let viewport_json = match fields.get("viewport") {
        Some(value) => value
        None => return None
      }
      let nodes_json = match fields.get("nodes") {
        Some(value) => value
        None => return None
      }
      let edges_json = match fields.get("edges") {
        Some(value) => value
        None => return None
      }
      let selected_nodes_json = match fields.get("selected_nodes") {
        Some(value) => value
        None => return None
      }
      let input_compatibility_json = match fields.get("input_compatibility") {
        Some(value) => value
        None => return None
      }
      let validation_json = match fields.get("validation") {
        Some(value) => value
        None => return None
      }
      let viewport : CanvasRenderLayerViewport = @json.from_json(viewport_json) catch {
        _ => return None
      }
      let nodes : Array[NodeJson] = @json.from_json(nodes_json) catch {
        _ => return None
      }
      let edges : Array[EdgeJson] = @json.from_json(edges_json) catch {
        _ => return None
      }
      let selected_nodes : Array[String] = @json.from_json(selected_nodes_json) catch {
        _ => return None
      }
      let input_compatibility : Array[PortCompatibilityJson] = @json.from_json(
        input_compatibility_json,
      ) catch {
        _ => return None
      }
      let validation : Array[ValidationJson] = @json.from_json(validation_json) catch {
        _ => return None
      }
      let connecting = match fields.get("connecting") {
        None | Some(Null) => None
        Some(Object(connecting)) => parse_connecting_json(connecting)
        Some(Array([Object(connecting)])) => parse_connecting_json(connecting)
        Some(_) => None
      }
      Some({
        viewport,
        nodes,
        edges,
        selected_nodes,
        connecting,
        input_compatibility,
        validation,
      })
    }
    _ => None
  }
}

///|
fn canvas_render_layer_update(
  model : CanvasRenderLayerState,
  message : CanvasRenderLayerMsg,
) -> CanvasRenderLayerState {
  match message {
    RenderState(json) =>
      match parse_canvas_render_layer_snapshot(json) {
        Some(snapshot) => { snapshot: Some(snapshot) }
        None => model
      }
  }
}

///|
fn canvas_render_layer_transform(
  viewport : CanvasRenderLayerViewport,
) -> String {
  "translate(\{viewport.x}px, \{viewport.y}px) scale(\{viewport.scale})"
}

///|
fn canvas_node_class(
  node : NodeJson,
  selected_nodes : Set[String],
  invalid_nodes : Set[String],
  connecting : ConnectingJson?,
) -> String {
  let class = "canvas-node workflow-node"
  let class = if selected_nodes.contains(node.id) {
    class + " selected"
  } else {
    class
  }
  let class = if invalid_nodes.contains(node.id) {
    class + " invalid"
  } else {
    class
  }
  let class = if !node.configured { class + " unconfigured" } else { class }
  match connecting {
    Some(value) if value.from == node.id => class + " connecting-source"
    _ => class
  }
}

///|
fn canvas_node_kind(node : NodeJson) -> String {
  match node.kind {
    Workflow(_) => "Workflow"
  }
}

///|
fn canvas_port_type_name(port : PortDef) -> String {
  match port.port_type {
    Flow => "Flow"
    Text => "Text"
    Number => "Number"
    Boolean => "Boolean"
    Json => "Json"
    Any => "Any"
  }
}

///|
fn canvas_port_title(port : PortDef) -> String {
  port.label + ": " + canvas_port_type_name(port)
}

///|
fn canvas_handle_class(
  node : NodeJson,
  side : String,
  port : PortDef,
  connecting_active : Bool,
  compatibility : Map[(String, String), Bool],
) -> String {
  let class = "handle " + side
  if side != "input" || !connecting_active {
    return class
  }
  match compatibility.get((node.id, port.id)) {
    Some(true) => class + " compatible-target"
    _ => class + " incompatible-target"
  }
}

///|
fn canvas_handle_view(
  node : NodeJson,
  side : String,
  port : PortDef,
  index : Int,
  port_count : Int,
  connecting_active : Bool,
  compatibility : Map[(String, String), Bool],
) -> @rabbita.Html {
  let side_title = if side == "input" { "Input" } else { "Output" }
  let top = ((index + 1).to_double() * 100.0 / (port_count + 1).to_double()).to_string() +
    "%"
  let attrs = @html.Attrs::build()
    .class(canvas_handle_class(
      node,
      side,
      port,
      connecting_active,
      compatibility,
    ))
    .data_set("handle", side)
    .data_set("node-id", node.id)
    .data_set("port-id", port.id)
    .data_set("port-label", port.label)
    .style("top", top)
    .title(side_title + " " + canvas_port_title(port))
    .aria_label(node.title + " " + side + " " + canvas_port_title(port))
  @html.node("div", attrs, @html.nothing)
}

///|
fn canvas_port_pill_view(direction : String, port : PortDef) -> @rabbita.Html {
  @html.node(
    "span",
    @html.Attrs::build()
    .class("port-pill " + direction)
    .title(canvas_port_title(port)),
    direction + ":" + port.label,
  )
}

///|
fn canvas_node_body_view(node : NodeJson) -> @rabbita.Html {
  let ports : Map[String, @rabbita.Html] = Map([])
  for port in node.inputs {
    ports["input:" + port.id] = canvas_port_pill_view("in", port)
  }
  for port in node.outputs {
    ports["output:" + port.id] = canvas_port_pill_view("out", port)
  }
  @html.node("div", @html.Attrs::build().class("node-body"), [
    @html.node(
      "div",
      @html.Attrs::build().class("node-kicker"),
      "Workflow step",
    ),
    @html.node("div", @html.Attrs::build().class("node-title"), node.title),
    @html.node(
      "div",
      @html.Attrs::build().class("node-subtitle"),
      node.subtitle,
    ),
    @html.node(
      "div",
      @html.Attrs::build().class("ports").aria_label("typed ports"),
      ports,
    ),
  ])
}

///|
fn canvas_node_view(
  node : NodeJson,
  selected_nodes : Set[String],
  invalid_nodes : Set[String],
  connecting : ConnectingJson?,
  compatibility : Map[(String, String), Bool],
) -> @rabbita.Html {
  let connecting_active = connecting is Some(_)
  let attrs = @html.Attrs::build()
    .class(canvas_node_class(node, selected_nodes, invalid_nodes, connecting))
    .data_set("node-id", node.id)
    .data_set("kind", canvas_node_kind(node))
    .style("left", "\{node.x}px")
    .style("top", "\{node.y}px")
    .style("width", "\{node.w}px")
    .style("height", "\{node.h}px")
    .title(node.title + "\n" + node.subtitle)
  let children : Map[String, @rabbita.Html] = Map([])
  children["body"] = canvas_node_body_view(node)
  for index, port in node.inputs {
    children["handle:input:" + port.id] = canvas_handle_view(
      node,
      "input",
      port,
      index,
      node.inputs.length(),
      connecting_active,
      compatibility,
    )
  }
  for index, port in node.outputs {
    children["handle:output:" + port.id] = canvas_handle_view(
      node,
      "output",
      port,
      index,
      node.outputs.length(),
      connecting_active,
      compatibility,
    )
  }
  @html.node("div", attrs, children)
}

///|
fn canvas_edge_path_class(edge : EdgeJson) -> String {
  if edge.selected {
    "edge selected"
  } else {
    "edge"
  }
}

///|
fn canvas_edge_path(edge : EdgeJson) -> @svg.Svg {
  @svg.path(
    class=canvas_edge_path_class(edge),
    d=edge.path_d,
    attrs=@svg.Attrs::build()
      .data_set("edge-id", edge.id)
      .role("button")
      .tabindex("0")
      .aria_label(edge.aria_label),
  )
}

///|
fn canvas_render_layer_view(model : CanvasRenderLayerState) -> @rabbita.Html {
  match model.snapshot {
    None => @html.nothing
    Some(snapshot) => {
      let selected_nodes : Set[String] = Set(snapshot.selected_nodes)
      let invalid_nodes : Set[String] = Set([])
      for validation in snapshot.validation {
        match validation.node_id {
          Some(node_id) => invalid_nodes.add(node_id)
          None => ()
        }
      }
      let compatibility : Map[(String, String), Bool] = Map([])
      for entry in snapshot.input_compatibility {
        compatibility[(entry.node_id, entry.port_id)] = entry.compatible
      }
      let edge_children : Map[String, @svg.Svg] = Map([])
      for edge in snapshot.edges {
        edge_children["edge:" + edge.id] = canvas_edge_path(edge)
      }
      match snapshot.connecting {
        Some(connecting) =>
          match connecting.path_d {
            Some(path_d) =>
              edge_children["pending"] = @svg.path(
                class="edge-pending",
                d=path_d,
              )
            None => ()
          }
        None => ()
      }
      let edges = @svg.keyed_node(
        "svg",
        @svg.Attrs::build()
        .id("edges")
        .style("transform", canvas_render_layer_transform(snapshot.viewport)),
        edge_children,
      ).to_html()
      let node_children : Map[String, @rabbita.Html] = Map([])
      for node in snapshot.nodes {
        node_children["node:" + node.id] = canvas_node_view(
          node,
          selected_nodes,
          invalid_nodes,
          snapshot.connecting,
          compatibility,
        )
      }
      let world = @html.node(
        "div",
        @html.Attrs::build()
        .id("world")
        .style("transform", canvas_render_layer_transform(snapshot.viewport)),
        node_children,
      )
      @html.fragment([edges, world])
    }
  }
}

///|
#cfg(target="js")
priv suberror CanvasRenderLayerSubscription {
  RenderState(@rabbita.Emit[CanvasRenderLayerMsg])
}

///|
#cfg(target="js")
fn canvas_render_layer_event_target() -> @dom.EventTarget {
  @dom.document()
  .get_element_by_id(CANVAS_RENDER_LAYER_ID)
  .unwrap()
  .as_event_target()
}

///|
#cfg(target="js")
fn canvas_render_layer_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CanvasRenderLayerSubscription::RenderState(emit) => {
      let tagger = @ref.Ref(emit)
      let target = canvas_render_layer_event_target()
      let listener : @dom.Listener = event => {
        match event.to_custom_event() {
          Some(custom) =>
            scheduler.add(
              (tagger.val)(
                CanvasRenderLayerMsg::RenderState(
                  custom.get_detail().to_string(),
                ),
              ),
            )
          None => ()
        }
      }
      target.add_event_listener(CANVAS_RENDER_STATE_EVENT, listener)
      Some({
        unload: _ => {
          target.remove_event_listener(CANVAS_RENDER_STATE_EVENT, listener)
        },
        update_tagger: next => {
          guard next is CanvasRenderLayerSubscription::RenderState(new_emit) else {
            return
          }
          tagger.val = new_emit
        },
      })
    }
    _ => None
  }
}

///|
#cfg(target="js")
fn canvas_render_layer_subscriptions(
  _model : CanvasRenderLayerState,
  emit : @rabbita.Emit[CanvasRenderLayerMsg],
) -> @sub.Sub {
  @sub.custom_sub(
    "canvas.render-state",
    @sub.Scope::Local,
    CanvasRenderLayerSubscription::RenderState(emit),
    canvas_render_layer_sub_loader,
  )
}

///|
#cfg(target="js")
pub fn mount_canvas_render_layer() -> Unit {
  @rabbita.new(fn() {
    let (model, _emit) = @rabbita.create_state(
      { snapshot: None },
      update=fn(model, message, _emit) {
        (canvas_render_layer_update(model, message), @rabbita.none)
      },
      subscriptions=canvas_render_layer_subscriptions,
    )
    model.map(canvas_render_layer_view)
  }).mount(CANVAS_RENDER_LAYER_ID)
}

///|
#cfg(target="js")
fn dispatch_canvas_render_state(json : String) -> Unit {
  match @dom.document().get_element_by_id(CANVAS_RENDER_LAYER_ID).to_option() {
    None => ()
    Some(target) =>
      target.dispatch_event(
        @dom.CustomEvent::new(
          CANVAS_RENDER_STATE_EVENT,
          detail=@js.Optional::from_option(Some(@js.Value::cast_from(json))),
        ).as_event(),
      )
  }
}

///|
/// Publish one serialized render snapshot to the TypeScript and Rabbita
/// consumers. The custom event is only an app-private transport seam; the
/// returned string is the same snapshot consumed by the TypeScript shell.
#cfg(target="js")
pub fn publish_render_state(handle : Int) -> String {
  let json = match canvas_backing(handle) {
    Some(backing) => backing.render_state_json()
    None => {
      // Preserve the old workflow registry's out-of-range failure while
      // retaining the source boundary's error result for an empty slot.
      if handle < 0 || handle >= canvas_instances.length() {
        ignore(canvas_instances[handle])
      }
      get_source_graph_render_state(handle)
    }
  }
  dispatch_canvas_render_state(json)
  json
}
