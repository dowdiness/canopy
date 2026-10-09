///|
const CANVAS_INSPECTOR_ID : String = "inspector-node"

///|
priv enum CanvasInspectorField {
  Binding
  Parameter(String)
} derive(Eq)

///|
priv struct CanvasInspectorFieldKey {
  node_id : String
  field : CanvasInspectorField
} derive(Eq)

///|
priv enum CanvasInspectorSessionPhase {
  Editing
  Submitted
  Cancelled
} derive(Eq)

///|
priv struct CanvasInspectorSession {
  id : Int
  key : CanvasInspectorFieldKey
  canonical : String
  submitted_value : String?
  phase : CanvasInspectorSessionPhase
} derive(Eq)

///|
priv struct CanvasInspectorProjection {
  summary : InspectorNodeJson
  params : Array[NodeParamJson]
  has_source_node : Bool
} derive(Eq)

///|
priv struct CanvasInspectorState {
  projection : CanvasInspectorProjection?
  session : CanvasInspectorSession?
  // Target/terminal invalidation only; ending one edit must not reject the
  // next focus event captured before the next render.
  reset_generation : Int
  terminal : Bool
} derive(Eq)

///|
priv enum CanvasInspectorEffect {
  NoEffect
  Finalize(CanvasInspectorFieldKey, String?, Bool, Int?)
  SyncInactive(CanvasInspectorProjection?)
  Submit(CanvasSourceRequest, CanvasInspectorFieldKey, Int)
}

///|
priv struct CanvasInspectorUpdate {
  state : CanvasInspectorState
  effect : CanvasInspectorEffect
}

///|
priv enum CanvasInspectorMsg {
  Snapshot(CanvasRenderLayerSnapshot)
  ParserStopped
  Focus(CanvasInspectorFieldKey, String, Int, Int)
  Change(CanvasInspectorFieldKey, Int, String)
  Enter(CanvasInspectorFieldKey, Int, String, Bool)
  Escape(CanvasInspectorFieldKey, Int)
  Completion(Int, CanvasSourceReply)
}

///|
fn canvas_inspector_projection(
  source_backed : Bool,
  snapshot : CanvasRenderLayerSnapshot,
) -> CanvasInspectorProjection? {
  match snapshot.inspector {
    Some(summary) => {
      let node = if source_backed && summary.source == "selected" {
        snapshot.nodes
        .search_by(node => node.id == summary.id)
        .map(index => snapshot.nodes[index])
      } else {
        None
      }
      Some({
        summary,
        params: match node {
          Some(value) => value.params
          None => []
        },
        has_source_node: node is Some(_),
      })
    }
    None if source_backed => {
      let selected_id = match snapshot.selected {
        Some(id) => Some(id)
        None => snapshot.selected_nodes.get(0)
      }
      match selected_id {
        None => None
        Some(id) =>
          match
            snapshot.nodes
            .search_by(node => node.id == id)
            .map(index => snapshot.nodes[index]) {
            None => None
            Some(node) =>
              Some({
                summary: {
                  id: node.id,
                  title: node.title,
                  subtitle: node.subtitle,
                  configured: node.configured,
                  input_count: node.inputs.length(),
                  output_count: node.outputs.length(),
                  source: "selected",
                },
                params: node.params,
                has_source_node: true,
              })
          }
      }
    }
    None => None
  }
}

///|
fn canvas_inspector_field_canonical(
  projection : CanvasInspectorProjection,
  key : CanvasInspectorFieldKey,
) -> String? {
  guard key.node_id == projection.summary.id else { return None }
  guard projection.has_source_node && projection.summary.source == "selected" else {
    return None
  }
  match key.field {
    Binding => Some(projection.summary.title)
    Parameter(name) =>
      match
        projection.params.search_by(param => {
          param.name == name && param.editable
        }) {
        Some(index) => Some(projection.params[index].value)
        None => None
      }
  }
}

///|
fn canvas_inspector_same_editable_fields(
  left : Array[NodeParamJson],
  right : Array[NodeParamJson],
) -> Bool {
  for param in left {
    if param.editable {
      guard right.search_by(other => other.name == param.name && other.editable)
        is Some(_) else {
        return false
      }
    }
  }
  for param in right {
    if param.editable {
      guard left.search_by(other => other.name == param.name && other.editable)
        is Some(_) else {
        return false
      }
    }
  }
  true
}

///|
fn canvas_inspector_reconcile(
  state : CanvasInspectorState,
  snapshot : CanvasRenderLayerSnapshot,
  source_backed : Bool,
) -> CanvasInspectorState {
  let projection = canvas_inspector_projection(source_backed, snapshot)
  let target_changed = match (state.projection, projection) {
    (None, None) => false
    (Some(previous), Some(next)) =>
      previous.summary.id != next.summary.id ||
      previous.summary.source != next.summary.source ||
      previous.has_source_node != next.has_source_node ||
      !canvas_inspector_same_editable_fields(previous.params, next.params)
    _ => true
  }
  let invalidated = match (state.session, projection) {
    (Some(session), Some(next)) =>
      canvas_inspector_field_canonical(next, session.key) is None ||
      next.summary.id != session.key.node_id
    (Some(_), None) => true
    (None, _) => false
  }
  let reset = invalidated || target_changed
  {
    ..state,
    projection,
    session: if invalidated {
      None
    } else {
      state.session
    },
    reset_generation: if reset {
      state.reset_generation + 1
    } else {
      state.reset_generation
    },
  }
}

///|
fn canvas_inspector_update(
  state : CanvasInspectorState,
  message : CanvasInspectorMsg,
  source_backed : Bool,
) -> CanvasInspectorUpdate {
  match message {
    Snapshot(snapshot) => {
      let next = canvas_inspector_reconcile(state, snapshot, source_backed)
      {
        state: next,
        effect: if source_backed && state.projection != next.projection {
          SyncInactive(state.projection)
        } else {
          NoEffect
        },
      }
    }
    ParserStopped => {
      let effect = match state.session {
        Some(session) =>
          Finalize(session.key, Some(session.canonical), true, None)
        None => NoEffect
      }
      {
        state: {
          ..state,
          terminal: true,
          session: None,
          reset_generation: state.reset_generation + 1,
        },
        effect,
      }
    }
    Focus(key, canonical, generation, id) if source_backed && !state.terminal => {
      let valid = generation == state.reset_generation &&
        (match state.projection {
          Some(projection) =>
            canvas_inspector_field_canonical(projection, key) == Some(canonical)
          None => false
        })
      if !valid {
        { state, effect: NoEffect, }
      } else {
        let session = {
          id,
          key,
          canonical,
          submitted_value: None,
          phase: Editing,
        }
        { state: { ..state, session: Some(session), }, effect: NoEffect, }
      }
    }
    Focus(_, _, _, _) => { state, effect: NoEffect, }
    Change(key, id, value) => canvas_inspector_commit(state, key, id, value)
    Enter(key, id, value, composing) if !composing =>
      canvas_inspector_commit(state, key, id, value)
    Enter(_, _, _, _) => { state, effect: NoEffect, }
    Escape(key, id) =>
      match state.session {
        Some(session) if session.id == id &&
          session.key == key &&
          session.phase == Editing =>
          {
            state: { ..state, session: Some({ ..session, phase: Cancelled, }), },
            effect: Finalize(key, Some(session.canonical), true, Some(id)),
          }
        _ => { state, effect: NoEffect, }
      }
    Completion(id, reply) =>
      match state.session {
        Some(session) if session.id == id && session.phase == Submitted => {
          let canonical = match state.projection {
            Some(projection) =>
              canvas_inspector_field_canonical(projection, session.key)
            None => None
          }
          let canonical = match (reply, session.submitted_value, canonical) {
            (Applied, Some(_), Some(latest)) if latest != session.canonical =>
              Some(latest)
            (Applied, Some(value), _) => Some(value)
            (_, _, value) => value
          }
          {
            state: { ..state, session: None, terminal: reply is ParserStopped, },
            effect: match canonical {
              Some(value) => Finalize(session.key, Some(value), false, Some(id))
              None => NoEffect
            },
          }
        }
        _ => { state, effect: NoEffect, }
      }
  }
}

///|
fn canvas_inspector_commit(
  state : CanvasInspectorState,
  key : CanvasInspectorFieldKey,
  id : Int,
  value : String,
) -> CanvasInspectorUpdate {
  guard state.terminal is false else { return { state, effect: NoEffect, } }
  guard state.session is Some(session) &&
    session.id == id &&
    session.key == key &&
    session.phase == Editing else {
    return { state, effect: NoEffect, }
  }
  let trimmed = value.trim().to_owned()
  if trimmed == "" || trimmed == session.canonical {
    return {
      state: { ..state, session: None, },
      effect: Finalize(key, Some(session.canonical), true, Some(id)),
    }
  }
  let request = match key.field {
    Binding => CanvasSourceRequest::Rename(NodeId(key.node_id), trimmed)
    Parameter(name) =>
      CanvasSourceRequest::Parameter(NodeId(key.node_id), name, trimmed)
  }
  let submitted = {
    ..session,
    submitted_value: Some(trimmed),
    phase: Submitted,
  }
  {
    state: { ..state, session: Some(submitted), },
    effect: Submit(request, key, id),
  }
}

///|
fn canvas_inspector_param_id(name : String) -> String {
  let safe = StringBuilder()
  for char in name {
    if char.is_ascii_alphabetic() ||
      char.is_ascii_digit() ||
      char == '_' ||
      char == '-' {
      safe.write_char(char)
    } else {
      safe.write_char('-')
    }
  }
  "node-param-" + safe.to_string()
}

///|
fn canvas_inspector_input_value_from_key(event : @dom.KeyboardEvent) -> String {
  match event.current_target().to_option() {
    Some(target) =>
      match target.to_html_input_element() {
        Some(input) => input.value()
        None => ""
      }
    None => ""
  }
}

///|
fn canvas_inspector_event_session(event : @dom.Event) -> Int? {
  guard event.target().to_element() is Some(element) else { return None }
  guard element.get_attribute("data-inspector-session") is Some(text) else {
    return None
  }
  Some(
    @json.from_json(@json.parse(text) catch { _ => return None }) catch {
      _ => return None
    },
  )
}

///|
fn canvas_inspector_change_input(
  event : @dom.Event,
) -> (CanvasInspectorFieldKey, Int, String)? {
  guard event.target().to_html_input_element() is Some(input) else {
    return None
  }
  guard input.as_event_target().to_element() is Some(element) else {
    return None
  }
  let node_id = match element.get_attribute("data-inspector-node-id") {
    Some(value) => value
    None => return None
  }
  let kind = match element.get_attribute("data-inspector-kind") {
    Some(value) => value
    None => return None
  }
  guard canvas_inspector_event_session(event) is Some(session_id) else {
    return None
  }
  let field : CanvasInspectorField = match kind {
    "binding" => Binding
    "parameter" =>
      match element.get_attribute("data-inspector-param") {
        Some(name) => Parameter(name)
        None => return None
      }
    _ => return None
  }
  Some(({ node_id, field, }, session_id, input.value()))
}

///|
fn canvas_inspector_should_sync(
  previous : CanvasInspectorProjection?,
  next : CanvasInspectorState,
  key : CanvasInspectorFieldKey,
  value : String,
) -> Bool {
  match next.session {
    Some(session) if session.key == key && session.phase != Cancelled => false
    _ =>
      match previous {
        Some(projection) =>
          canvas_inspector_field_canonical(projection, key) != Some(value)
        None => true
      }
  }
}

///|
priv struct CanvasInspectorElements {
  mut active : Bool
  mut fields : Array[
    (CanvasInspectorFieldKey, @dom.Element, @dom.HTMLInputElement),
  ]
  mut state : CanvasInspectorState
}

///|
fn canvas_inspector_acquire_elements(
  root : @dom.Element,
  state : CanvasInspectorState,
  elements : CanvasInspectorElements,
) -> Unit {
  guard elements.active else { return }
  let fields : Array[
    (CanvasInspectorFieldKey, @dom.Element, @dom.HTMLInputElement),
  ] = []
  guard state.projection is Some(projection) &&
    projection.has_source_node &&
    projection.summary.source == "selected" else {
    elements.fields = fields
    return
  }
  let node_id = projection.summary.id
  let binding_key : CanvasInspectorFieldKey = { node_id, field: Binding, }
  match root.query_selector("#node-rename-input") {
    Some(element) if element.get_attribute("data-inspector-node-id") ==
      Some(node_id) =>
      match element.as_event_target().to_html_input_element() {
        Some(input) => fields.push((binding_key, element, input))
        None => ()
      }
    _ => ()
  }
  for param in projection.params {
    if param.editable {
      let key : CanvasInspectorFieldKey = {
        node_id,
        field: Parameter(param.name),
      }
      let selector = "#" + canvas_inspector_param_id(param.name)
      match root.query_selector(selector) {
        Some(element) if element.get_attribute("data-inspector-node-id") ==
          Some(node_id) =>
          match element.as_event_target().to_html_input_element() {
            Some(input) => fields.push((key, element, input))
            None => ()
          }
        _ => ()
      }
    }
  }
  elements.fields = fields
}

///|
fn canvas_inspector_dom_finalize(
  elements : CanvasInspectorElements,
  key : CanvasInspectorFieldKey,
  restore : String?,
  blur : Bool,
  session_id? : Int,
) -> Unit {
  guard elements.fields.search_by(entry => entry.0 == key) is Some(index) else {
    return
  }
  canvas_inspector_finalize_input(
    elements.fields[index].1,
    elements.fields[index].2,
    key,
    restore,
    blur,
    session_id?,
  )
}

///|
fn canvas_inspector_finalize_input(
  element : @dom.Element,
  input : @dom.HTMLInputElement,
  key : CanvasInspectorFieldKey,
  restore : String?,
  blur : Bool,
  session_id? : Int,
) -> Unit {
  guard element.get_attribute("data-inspector-node-id") == Some(key.node_id) else {
    return
  }
  // A queued effect must not affect a newer focus of the same native element.
  if session_id is Some(expected_id) &&
    element.get_attribute("data-inspector-session") !=
    Some(expected_id.to_string()) {
    return
  }
  match restore {
    Some(value) => input.set_value(value)
    None => ()
  }
  if blur {
    input.blur()
  }
}

///|
fn canvas_inspector_sync_inactive_field(
  elements : CanvasInspectorElements,
  previous : CanvasInspectorProjection?,
  next : CanvasInspectorState,
  key : CanvasInspectorFieldKey,
  value : String,
) -> Unit {
  guard canvas_inspector_should_sync(previous, next, key, value) else { return }
  // Changing the value attribute does not reset a dirty native input property.
  canvas_inspector_dom_finalize(elements, key, Some(value), false)
}

///|
fn canvas_inspector_sync_inactive_fields(
  root : @dom.Element,
  elements : CanvasInspectorElements,
  previous : CanvasInspectorProjection?,
  next : CanvasInspectorState,
) -> Unit {
  canvas_inspector_acquire_elements(root, next, elements)
  guard next.projection is Some(projection) &&
    projection.has_source_node &&
    projection.summary.source == "selected" else {
    return
  }
  let node_id = projection.summary.id
  canvas_inspector_sync_inactive_field(
    elements,
    previous,
    next,
    { node_id, field: Binding, },
    projection.summary.title,
  )
  for param in projection.params {
    if param.editable {
      canvas_inspector_sync_inactive_field(
        elements,
        previous,
        next,
        { node_id, field: Parameter(param.name), },
        param.value,
      )
    }
  }
}

///|
fn canvas_inspector_input(
  state : CanvasInspectorState,
  key : CanvasInspectorFieldKey,
  id : String,
  canonical : String,
  label : String,
  emit : @rabbita.Emit[CanvasInspectorMsg],
  next_session_id : @ref.Ref[Int],
) -> @rabbita.Html {
  let key_text = match key.field {
    Binding => key.node_id + ":binding"
    Parameter(name) => key.node_id + ":parameter:" + name
  }
  let canonical = match state.session {
    Some(session) if session.key == key && session.phase != Cancelled =>
      session.canonical
    _ => canonical
  }
  let attrs = @html.Attrs::build()
    .id(id)
    .data_set("inspector-field", key_text)
    .data_set("inspector-node-id", key.node_id)
    .data_set(
      "inspector-kind",
      match key.field {
        Binding => "binding"
        Parameter(_) => "parameter"
      },
    )
    .data_set(
      "inspector-param",
      match key.field {
        Binding => ""
        Parameter(name) => name
      },
    )
    .type_("text")
    .value(canonical)
    .autocomplete(@html.Off)
    .spellcheck(false)
    .disabled(state.terminal)
    .aria_label(label)
    .on_focus(event => {
      guard event.target().to_element() is Some(element) else {
        return @rabbita.none
      }
      // Reserve the identity in the DOM callback, before queued updates/render.
      // Enter/change/Escape in this same task must carry this focus's identity.
      let id = next_session_id.val
      next_session_id.val += 1
      element.set_attribute("data-inspector-session", id.to_string())
      emit(Focus(key, canonical, state.reset_generation, id))
    })
    .on_keydown(event => {
      match event.key() {
        "Enter" if !event.is_composing() => {
          event.prevent_default()
          guard canvas_inspector_event_session(event.as_event())
            is Some(session_id) else {
            return @rabbita.none
          }
          emit(
            Enter(
              key,
              session_id,
              canvas_inspector_input_value_from_key(event),
              false,
            ),
          )
        }
        "Escape" => {
          event.prevent_default()
          guard canvas_inspector_event_session(event.as_event())
            is Some(session_id) else {
            return @rabbita.none
          }
          emit(Escape(key, session_id))
        }
        _ => @rabbita.none
      }
    })
  let attrs = match key.field {
    Binding => attrs
    Parameter(_) => attrs.inputmode("decimal")
  }
  @html.node("input", attrs, @html.nothing)
}

///|
fn canvas_inspector_view(
  state : CanvasInspectorState,
  source_backed : Bool,
  emit : @rabbita.Emit[CanvasInspectorMsg],
  next_session_id : @ref.Ref[Int],
) -> @rabbita.Html {
  match state.projection {
    None =>
      @html.node(
        "div",
        @html.Attrs::build().class("inspector-empty"),
        "Select or hover a node to inspect its sparse derived details.",
      )
    Some(projection) => {
      let item = projection.summary
      let source = if item.source == "selected" {
        "Selected node"
      } else {
        "Hovered node"
      }
      // Fixed chrome uses ordered children. Key only semantic identities:
      // rebuilding a multi-entry Map can reorder and relocate focused DOM.
      let children : Array[@rabbita.Html] = [
        @html.div(class="inspector-eyebrow", source),
        @html.div(class="inspector-title", item.title),
        @html.div(class="inspector-subtitle", item.subtitle),
        @html.div(class="inspector-meta", [
          @html.span(
            if item.configured {
              "Configured"
            } else {
              "Needs config"
            },
          ),
          @html.span("\{item.input_count} in · \{item.output_count} out"),
        ]),
      ]
      if source_backed &&
        item.source == "selected" &&
        projection.has_source_node {
        let fields : Array[@rabbita.Html] = []
        let binding_key : CanvasInspectorFieldKey = {
          node_id: item.id,
          field: Binding,
        }
        fields.push(
          @html.node(
            "label",
            @html.Attrs::build()
            .class("inspector-field")
            .for_("node-rename-input"),
            [
              @html.node("span", @html.Attrs::build(), "Binding"),
              canvas_inspector_input(
                state,
                binding_key,
                "node-rename-input",
                item.title,
                "Node binding",
                emit,
                next_session_id,
              ),
            ],
          ),
        )
        let params : Array[@rabbita.Html] = []
        for param in projection.params {
          let pkey : CanvasInspectorFieldKey = {
            node_id: item.id,
            field: Parameter(param.name),
          }
          let id = canvas_inspector_param_id(param.name)
          let child = if param.editable {
            let input = canvas_inspector_input(
              state,
              pkey,
              id,
              param.value,
              "Parameter " + param.name,
              emit,
              next_session_id,
            )
            @html.node(
              "label",
              @html.Attrs::build()
              .class("inspector-field param editable")
              .for_(id),
              match param.unit {
                Some(unit) =>
                  [
                    @html.node("span", @html.Attrs::build(), param.name),
                    input,
                    @html.node(
                      "span",
                      @html.Attrs::build().class("param-unit"),
                      unit,
                    ),
                  ]
                None =>
                  [@html.node("span", @html.Attrs::build(), param.name), input]
              },
            )
          } else {
            @html.node(
              "label",
              @html.Attrs::build().class("inspector-field param readonly"),
              [
                @html.node("span", @html.Attrs::build(), param.name),
                @html.node(
                  "span",
                  @html.Attrs::build().class("param-readonly-value"),
                  match param.unit {
                    Some(unit) => param.value + unit
                    None => param.value
                  },
                ),
              ],
            )
          }
          params.push(
            @html.div(style=["display: contents"], Map([(param.name, child)])),
          )
        }
        if params.length() > 0 {
          fields.push(@html.div(class="inspector-param-list", params))
        }
        children.push(@html.div(class="inspector-source-editor", fields))
      }
      @html.div(Map([(item.id, @html.div(children))]))
    }
  }
}

///|
fn canvas_inspector_run_effect(
  root : @dom.Element,
  elements : CanvasInspectorElements,
  effect : CanvasInspectorEffect,
  send_source : (CanvasSourceMessage) -> Unit,
  post_to_self : (CanvasInspectorMsg) -> Unit,
) -> @rabbita.Cmd {
  match effect {
    NoEffect => @rabbita.none
    SyncInactive(previous) =>
      @cmd.custom_cmd(
        _ => {
          guard elements.active else { return }
          // A native focus may have started after the snapshot was received.
          // Use the current pure state, not the snapshot's earlier session.
          canvas_inspector_sync_inactive_fields(
            root,
            elements,
            previous,
            elements.state,
          )
        },
        kind=@cmd.after_render,
      )
    Finalize(key, restore, blur, session_id) =>
      @cmd.custom_cmd(_ => {
        guard elements.active else { return }
        canvas_inspector_dom_finalize(elements, key, restore, blur, session_id?)
      })
    Submit(request, key, id) =>
      @cmd.custom_cmd(_ => {
        guard elements.active else { return }
        send_source(
          CanvasSourceMessage::Request(
            request,
            Some(reply => post_to_self(Completion(id, reply))),
          ),
        )
        canvas_inspector_dom_finalize(elements, key, None, true, session_id=id)
      })
  }
}

///|
#cfg(target="js")
priv suberror CanvasInspectorSubscription {
  Receive(
    @dom.Element,
    CanvasInspectorElements,
    @rabbita.Emit[CanvasInspectorMsg],
    ((CanvasInspectorMsg) -> Unit) -> Unit,
    @ref.Ref[(CanvasInspectorMsg) -> Unit]
  )
}

///|
#cfg(target="js")
fn canvas_inspector_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CanvasInspectorSubscription::Receive(
      root,
      elements,
      emit,
      register,
      self_queue
    ) => {
      let tagger = @ref.Ref(emit)
      let active = @ref.Ref(true)
      let queue = fn(message) {
        if active.val {
          scheduler.add((tagger.val)(message))
        }
      }
      let change_listener : @dom.Listener = event => {
        if active.val {
          match canvas_inspector_change_input(event) {
            Some((key, session_id, value)) =>
              scheduler.add((tagger.val)(Change(key, session_id, value)))
            None => ()
          }
        }
      }
      let target = root.as_event_target()
      target.add_event_listener("change", change_listener)
      self_queue.val = queue
      register(queue)
      Some({
        unload: _ => {
          active.val = false
          elements.active = false
          target.remove_event_listener("change", change_listener)
          self_queue.val = _ => ()
          elements.fields = []
        },
        update_tagger: next => {
          guard next
            is CanvasInspectorSubscription::Receive(_, _, new_emit, _, _) else {
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
fn mount_canvas_inspector(
  root : @dom.Element,
  source_backed : Bool,
  send_source : (CanvasSourceMessage) -> Unit,
  register : ((CanvasInspectorMsg) -> Unit) -> Unit,
) -> Unit {
  let self_queue = @ref.Ref((_ : CanvasInspectorMsg) => ())
  let initial : CanvasInspectorState = {
    projection: None,
    session: None,
    reset_generation: 0,
    terminal: false,
  }
  let elements = { active: true, fields: [], state: initial, }
  @rabbita.new(() => {
    let next_session_id = @ref.Ref(1)
    let (model, emit) = @rabbita.create_state(
      initial,
      update=fn(model, message, _emit) {
        let update = canvas_inspector_update(model, message, source_backed)
        elements.state = update.state
        (
          update.state,
          canvas_inspector_run_effect(
            root,
            elements,
            update.effect,
            send_source,
            self_queue.val,
          ),
        )
      },
      subscriptions=(_, emit) => {
        @sub.custom_sub(
          "canvas.inspector.receiver",
          @sub.Scope::Local,
          CanvasInspectorSubscription::Receive(
            root, elements, emit, register, self_queue,
          ),
          canvas_inspector_sub_loader,
        )
      },
    )
    model.map(state => {
      canvas_inspector_view(state, source_backed, emit, next_session_id)
    })
  }).mount(CANVAS_INSPECTOR_ID)
}
