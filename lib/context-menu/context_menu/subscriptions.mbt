///|
#cfg(target="js")
priv suberror DismissableLayerSub {
  DismissableLayer(String, @rabbita.Emit[Msg])
}

///|
#cfg(target="js")
extern "js" fn event_target_is_inside_element_id(
  id : String,
  event : @dom.Event,
) -> Bool =
  #| (id, event) => {
  #|   const root = document.getElementById(id);
  #|   const target = event && event.target;
  #|   return !!(root && target instanceof Node && root.contains(target));
  #| }

///|
#cfg(target="js")
extern "js" fn event_is_undismissed_escape(
  id : String,
  event : @dom.Event,
) -> Bool =
  #| (id, event) => {
  #|   if (!event || event.key !== "Escape" || event.defaultPrevented) return false;
  #|   const root = document.getElementById(id);
  #|   const target = event.target;
  #|   return !(root && target instanceof Node && root.contains(target));
  #| }

///|
#cfg(target="js")
fn dismissable_layer_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DismissableLayer(id, emit) => {
      let tagger = @ref.Ref(emit)
      let target = @dom.document().as_event_target()
      let pointer_listener : @dom.Listener = event => {
        if !event_target_is_inside_element_id(id, event) {
          scheduler.add((tagger.val)(Dismiss(PointerOutside)))
        }
      }
      let key_listener : @dom.Listener = event => {
        if event_is_undismissed_escape(id, event) {
          scheduler.add((tagger.val)(Dismiss(EscapeKey)))
        }
      }
      target.add_event_listener("pointerdown", pointer_listener)
      target.add_event_listener("keydown", key_listener)
      Some({
        unload: _ => {
          target.remove_event_listener("pointerdown", pointer_listener)
          target.remove_event_listener("keydown", key_listener)
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
pub fn Model::subscriptions(
  self : Model,
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
pub fn Model::subscriptions(
  self : Model,
  emit : @rabbita.Emit[Msg],
) -> @sub.Sub {
  ignore((self, emit))
  @sub.none
}
