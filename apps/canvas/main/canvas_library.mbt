///|
priv struct CanvasLibraryBinding {
  root : @dom.Element
  handle : Int
  on_change : () -> Unit
  send_source : (CanvasSourceMessage) -> Unit
  can_mutate : () -> Bool
}

///|
priv enum CanvasLibraryMsg {
  SearchChanged(String)
  Insert(String)
}

///|
priv struct CanvasLibraryModel {
  filter : String
} derive(Eq)

///|
fn canvas_library_matches(
  item : CanvasNodeCatalogItem,
  filter : String,
) -> Bool {
  filter == "" ||
  (item.label + " " + item.description).to_lower().contains(filter)
}

///|
fn canvas_library_request_insert(
  binding : CanvasLibraryBinding,
  item_key : String,
) -> Unit {
  if !(binding.can_mutate)() {
    return
  }
  match canvas_backing(binding.handle) {
    Some(Runtime(runtime)) => {
      let state = runtime.state_peek()
      let screen = match
        canvas_library_screen_point(
          binding.root.get_client_width(),
          binding.root.get_client_height(),
        ) {
        Some(screen) => screen
        None => return
      }
      let position = state.viewport.screen_to_world(screen) catch {
        @spatial.CoordinateError::NonFinite => return
      }
      runtime.clear_selected_edge()
      runtime.sync_document_action_state(
        (runtime.policy.add_node)(state, item_key, position),
      )
      (binding.on_change)()
    }
    Some(Source(_)) =>
      (binding.send_source)(Request(Insert(item_key, item_key), None))
    None => ()
  }
}

///|
fn canvas_library_update(
  binding : CanvasLibraryBinding,
  model : CanvasLibraryModel,
  msg : CanvasLibraryMsg,
) -> (CanvasLibraryModel, @rabbita.Cmd) {
  match msg {
    SearchChanged(filter) =>
      ({ filter: filter.trim().to_owned().to_lower(), }, @rabbita.none)
    Insert(key) =>
      (
        model,
        @rabbita.effect(() => canvas_library_request_insert(binding, key)),
      )
  }
}

///|
#cfg(target="js")
priv suberror CanvasLibrarySub {
  Search(@dom.HTMLInputElement, @rabbita.Emit[CanvasLibraryMsg])
}

///|
#cfg(target="js")
fn canvas_library_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CanvasLibrarySub::Search(input, emit) => {
      let tagger = @ref.Ref(emit)
      let target = input.as_event_target()
      let listener : @dom.Listener = _ => {
        scheduler.add((tagger.val)(SearchChanged(input.value())))
      }
      target.add_event_listener("input", listener)
      Some({
        unload: _ => target.remove_event_listener("input", listener),
        update_tagger: next => {
          guard next is CanvasLibrarySub::Search(_, new_emit) else { return }
          tagger.val = new_emit
        },
      })
    }
    _ => None
  }
}

///|
#cfg(target="js")
fn canvas_library_subscriptions(
  search : @dom.HTMLInputElement,
  emit : @rabbita.Emit[CanvasLibraryMsg],
) -> @sub.Sub {
  @sub.custom_sub(
    "canvas.library.search",
    @sub.Scope::Local,
    CanvasLibrarySub::Search(search, emit),
    canvas_library_sub_loader,
  )
}

///|
fn canvas_library_view(
  emit : @rabbita.Emit[CanvasLibraryMsg],
  model : CanvasLibraryModel,
) -> @rabbita.Html {
  let children : Array[@rabbita.Html] = []
  for item in workflow_node_catalog() {
    if canvas_library_matches(item, model.filter) {
      children.push(
        @html.button(
          type_="button",
          title=item.description,
          class="library-item",
          on_click=emit(Insert(item.key)),
          [
            @html.strong([@html.text(item.label)]),
            @html.span([@html.text(item.description)]),
          ],
        ),
      )
    }
  }
  @html.div(attrs=@html.Attrs::build().style("display", "contents"), children)
}

///|
#cfg(target="js")
fn mount_canvas_library(
  root : @dom.Element,
  search : @dom.HTMLInputElement,
  handle : Int,
  on_change : () -> Unit,
  send_source : (CanvasSourceMessage) -> Unit,
  can_mutate : () -> Bool,
) -> Unit {
  let binding : CanvasLibraryBinding = {
    root,
    handle,
    on_change,
    send_source,
    can_mutate,
  }
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state(
      { filter: "", },
      update=(model, msg, _) => canvas_library_update(binding, model, msg),
      subscriptions=(_, emit) => canvas_library_subscriptions(search, emit),
    )
    model.map(model => canvas_library_view(emit, model))
  }).mount("node-library")
}
