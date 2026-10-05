///|
/// Mount the fixed-page UI once. Each receiver is installed by its receiving
/// host's subscription and queues only on that host's scheduler.
#cfg(target="js")
pub fn mount_canvas_ui(
  handle : Int,
  render_target : @dom.Element,
  on_change : () -> Unit,
  on_rendered : () -> Unit,
) -> Unit {
  guard canvas_backing(handle) is Some(backing) else { return }
  let document = @dom.document()
  let root = document.get_element_by_id(CANVAS_ROOT_ID).unwrap()
  let inspector = document.get_element_by_id(CANVAS_INSPECTOR_ID).unwrap()
  let search = document
    .get_element_by_id("node-search")
    .unwrap()
    .to_html_input_element()
    .unwrap()
  let source_backed = backing is Source(_)
  let mut source_receiver : ((CanvasSourceMessage) -> Unit)? = None
  let mut inspector_receiver : ((CanvasInspectorMsg) -> Unit)? = None
  let mut stopped = false
  let send_source = fn(message) { source_receiver.unwrap()(message) }
  let send_inspector = fn(message) { inspector_receiver.unwrap()(message) }
  let observe_parser = fn() {
    match backing {
      Source(graph) if graph.parser_failure is Some(_) && !stopped =>
        send_source(CanvasSourceMessage::ParserStopped)
      _ => ()
    }
  }
  let notify = fn() {
    observe_parser()
    on_change()
  }
  let can_mutate = fn() {
    !stopped &&
    (match backing {
      Source(graph) => graph.parser_failure is None
      Runtime(_) => true
    })
  }
  mount_canvas_inspector(inspector, source_backed, send_source, receiver => {
    inspector_receiver = Some(receiver)
  })
  mount_source_demo(
    handle,
    source_backed,
    notify,
    receiver => source_receiver = Some(receiver),
    fn() {
      stopped = true
      send_inspector(CanvasInspectorMsg::ParserStopped)
    },
  )
  mount_canvas_render_layer(
    render_target,
    snapshot => send_inspector(CanvasInspectorMsg::Snapshot(snapshot)),
    on_rendered,
  )
  mount_canvas_library(root, search, handle, notify, send_source, can_mutate)
  mount_canvas_context_menu(
    root,
    handle,
    notify,
    fn(result) {
      observe_parser()
      send_source(Completed(ContextOperation, result))
    },
    can_mutate,
  )
  mount_canvas_keyboard(
    document.as_event_target(),
    handle,
    notify,
    send_source,
    can_mutate,
  )
  mount_canvas_pointer_session(root, handle, notify)
}
