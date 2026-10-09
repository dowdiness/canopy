///|
#cfg(target="js")
priv suberror DismissableLayerSub {
  DismissableLayer(String, @rabbita.Emit[Msg])
}

///|
#cfg(target="js")
fn event_target_is_inside_element(
  panel : @dom.Element,
  event : @dom.Event,
) -> Bool {
  match event.target().to_node() {
    Some(target) => panel.contains(target)
    None => false
  }
}

///|
#cfg(target="js")
fn event_is_undismissed_escape(
  panel : @dom.Element,
  event : @dom.Event,
) -> Bool {
  if event.get_default_prevented() {
    false
  } else {
    match event.to_keyboard_event() {
      Some(keyboard) =>
        keyboard.key() == "Escape" &&
        !event_target_is_inside_element(panel, event)
      None => false
    }
  }
}

///|
#cfg(target="js")
fn connect_dismissal_layer(
  id : String,
  active : @ref.Ref[Bool],
  listeners : @ref.Ref[(@dom.EventTarget, @dom.Listener, @dom.Listener)?],
  emit : @ref.Ref[@rabbita.Emit[Msg]],
  scheduler : &@cmd.Scheduler,
) -> Unit {
  if active.val {
    match @dom.document().get_element_by_id(id).to_option() {
      Some(panel) if panel.get_is_connected() => {
        let target = @dom.document().as_event_target()
        let pointer_listener : @dom.Listener = event => {
          if active.val && !event_target_is_inside_element(panel, event) {
            scheduler.add((emit.val)(Dismiss(PointerOutside)))
          }
        }
        let key_listener : @dom.Listener = event => {
          if active.val && event_is_undismissed_escape(panel, event) {
            scheduler.add((emit.val)(Dismiss(EscapeKey)))
          }
        }
        target.add_event_listener("pointerdown", pointer_listener)
        target.add_event_listener("keydown", key_listener)
        listeners.val = Some((target, pointer_listener, key_listener))
      }
      _ => ()
    }
  }
}

///|
#cfg(target="js")
fn dismissable_layer_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DismissableLayer(id, emit) => {
      let active = @ref.Ref(true)
      let listeners : @ref.Ref[
        (@dom.EventTarget, @dom.Listener, @dom.Listener)?,
      ] = @ref.Ref(None)
      let tagger = @ref.Ref(emit)
      scheduler.add(
        @cmd.custom_cmd(
          custom_scheduler => {
            connect_dismissal_layer(
              id, active, listeners, tagger, custom_scheduler,
            )
          },
          kind=@cmd.after_render,
        ),
      )
      Some({
        unload: _ => {
          active.val = false
          match listeners.val {
            Some((target, pointer_listener, key_listener)) => {
              target.remove_event_listener("pointerdown", pointer_listener)
              target.remove_event_listener("keydown", key_listener)
              listeners.val = None
            }
            None => ()
          }
        },
        update_tagger: payload => {
          guard payload is DismissableLayer(_, new_emit) else { return }
          tagger.val = new_emit
        },
      })
    }
    _ => None
  }
}

///|
#cfg(target="js")
fn dismissable_layer_sub(id : String, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  @sub.custom_sub(
    "context-menu.dismissable-layer(id=\{id})",
    @sub.Scope::Local,
    DismissableLayer(id, emit),
    dismissable_layer_loader,
  )
}

///|
/// Subscribe to document-level dismissal behavior while the context menu is open.
///
/// The subscription emits `Dismiss(PointerOutside)` for outside pointer presses
/// and `Dismiss(EscapeKey)` for `Escape` when focus is outside the menu panel.
/// `Escape` pressed inside the panel is handled by `panel_attrs`, which also
/// prevents the default key action.
#cfg(target="js")
pub fn[T] Model::subscriptions(
  self : Model[T],
  emit : @rabbita.Emit[Msg],
) -> @sub.Sub {
  if self.is_open() {
    dismissable_layer_sub(self.id, emit)
  } else {
    @sub.none
  }
}

///|
#cfg(not(target="js"))
pub fn[T] Model::subscriptions(
  self : Model[T],
  emit : @rabbita.Emit[Msg],
) -> @sub.Sub {
  ignore((self, emit))
  @sub.none
}
