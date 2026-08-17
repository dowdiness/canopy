///|
const CANVAS_EDGE_LAYER_ID : String = "canvas-edge-layer"

///|
const CANVAS_RENDER_STATE_EVENT : String = "canopy-canvas-render-state"

///|
priv struct CanvasEdgeLayerViewport {
  x : Double
  y : Double
  scale : Double
} derive(Eq, FromJson)

///|
priv struct CanvasEdgeLayerSnapshot {
  viewport : CanvasEdgeLayerViewport
  edges : Array[EdgeJson]
  connecting_path_d : String?
} derive(Eq)

///|
priv struct CanvasEdgeLayerState {
  snapshot : CanvasEdgeLayerSnapshot?
} derive(Eq)

///|
priv enum CanvasEdgeLayerMsg {
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
fn parse_canvas_edge_layer_snapshot(
  json_text : String,
) -> CanvasEdgeLayerSnapshot? {
  let json = @json.parse(json_text) catch { _ => return None }
  match json {
    Object(fields) => {
      let viewport_json = match fields.get("viewport") {
        Some(value) => value
        None => return None
      }
      let edges_json = match fields.get("edges") {
        Some(value) => value
        None => return None
      }
      let viewport : CanvasEdgeLayerViewport = @json.from_json(viewport_json) catch {
        _ => return None
      }
      let edges : Array[EdgeJson] = @json.from_json(edges_json) catch {
        _ => return None
      }
      let connecting_path_d = match fields.get("connecting") {
        None | Some(Null) => None
        Some(Object(connecting)) => parse_connecting_path_d(connecting)
        Some(Array([Object(connecting)])) => parse_connecting_path_d(connecting)
        Some(_) => None
      }
      Some({ viewport, edges, connecting_path_d })
    }
    _ => None
  }
}

///|
fn canvas_edge_layer_update(
  model : CanvasEdgeLayerState,
  message : CanvasEdgeLayerMsg,
) -> CanvasEdgeLayerState {
  match message {
    RenderState(json) =>
      match parse_canvas_edge_layer_snapshot(json) {
        Some(snapshot) => { snapshot: Some(snapshot) }
        None => model
      }
  }
}

///|
fn canvas_edge_layer_transform(viewport : CanvasEdgeLayerViewport) -> String {
  "translate(\{viewport.x}px, \{viewport.y}px) scale(\{viewport.scale})"
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
fn canvas_edge_layer_view(model : CanvasEdgeLayerState) -> @rabbita.Html {
  match model.snapshot {
    None => @html.nothing
    Some(snapshot) => {
      let children : Map[String, @svg.Svg] = Map([])
      for edge in snapshot.edges {
        children["edge:\{edge.id}"] = canvas_edge_path(edge)
      }
      match snapshot.connecting_path_d {
        None => ()
        Some(path_d) =>
          children["pending"] = @svg.path(class="edge-pending", d=path_d)
      }
      let attrs = @svg.Attrs::build()
        .id("edges")
        .style("transform", canvas_edge_layer_transform(snapshot.viewport))
      @svg.keyed_node("svg", attrs, children).to_html()
    }
  }
}

///|
#cfg(target="js")
priv suberror CanvasEdgeLayerSubscription {
  RenderState(@rabbita.Emit[CanvasEdgeLayerMsg])
}

///|
#cfg(target="js")
fn canvas_edge_layer_event_target() -> @dom.EventTarget {
  @dom.document()
  .get_element_by_id(CANVAS_EDGE_LAYER_ID)
  .unwrap()
  .as_event_target()
}

///|
#cfg(target="js")
fn canvas_edge_layer_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CanvasEdgeLayerSubscription::RenderState(emit) => {
      let tagger = @ref.Ref(emit)
      let target = canvas_edge_layer_event_target()
      let listener : @dom.Listener = event => {
        match event.to_custom_event() {
          Some(custom) =>
            scheduler.add(
              (tagger.val)(
                CanvasEdgeLayerMsg::RenderState(custom.get_detail().to_string()),
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
          guard next is CanvasEdgeLayerSubscription::RenderState(new_emit) else {
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
fn canvas_edge_layer_subscriptions(
  _model : CanvasEdgeLayerState,
  emit : @rabbita.Emit[CanvasEdgeLayerMsg],
) -> @sub.Sub {
  @sub.custom_sub(
    "canvas.edge-render-state",
    @sub.Scope::Local,
    CanvasEdgeLayerSubscription::RenderState(emit),
    canvas_edge_layer_sub_loader,
  )
}

///|
#cfg(target="js")
pub fn mount_canvas_edge_layer() -> Unit {
  @rabbita.new(fn() {
    let (model, _emit) = @rabbita.create_state(
      { snapshot: None },
      update=fn(model, message, _emit) {
        (canvas_edge_layer_update(model, message), @rabbita.none)
      },
      subscriptions=canvas_edge_layer_subscriptions,
    )
    model.map(canvas_edge_layer_view)
  }).mount(CANVAS_EDGE_LAYER_ID)
}

///|
#cfg(target="js")
fn dispatch_canvas_render_state(json : String) -> Unit {
  match @dom.document().get_element_by_id(CANVAS_EDGE_LAYER_ID).to_option() {
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
pub fn publish_render_state(handle : Int, source_backed : Bool) -> String {
  let json = if source_backed {
    get_source_graph_render_state(handle)
  } else {
    get_render_state(handle)
  }
  dispatch_canvas_render_state(json)
  json
}
