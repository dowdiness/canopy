///|
#cfg(target="js")
using @cmd {trait Scheduler}

///|
#cfg(target="js")
priv suberror DocumentMouseUpSubscription {
  DocumentMouseUp(@rabbita.Cmd)
}

///|
#cfg(target="js")
fn document_mouse_up_loader(
  payload : Error,
  scheduler : &Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DocumentMouseUp(cmd) => {
      let mut tagger = cmd
      let listener : @dom.Listener = _ => scheduler.add(tagger)
      @dom.document().as_event_target().add_event_listener("mouseup", listener)
      Some({
        unload: _ => {
          @dom.document()
          .as_event_target()
          .remove_event_listener("mouseup", listener)
        },
        update_tagger: payload => {
          guard payload is DocumentMouseUp(cmd) else { return }
          tagger = cmd
        },
      })
    }
    _ => None
  }
}

///|
#cfg(target="js")
fn on_document_mouse_up(cmd : @rabbita.Cmd) -> @sub.Sub {
  @sub.custom_sub(
    "resizable.document_mouse_up",
    Local,
    DocumentMouseUp(cmd),
    document_mouse_up_loader,
  )
}

///|
#cfg(target="js")
pub fn Model::subscriptions(
  self : Model,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @sub.Sub {
  if self.is_resizing() {
    @sub.batch([
      @sub.on_mouse_move(mouse => {
        let pos = mouse.client_pos()
        dispatch(PointerMove(x=pos.x, y=pos.y))
      }),
      on_document_mouse_up(dispatch(EndResize)),
    ])
  } else {
    @sub.none
  }
}

///|
#cfg(not(target="js"))
pub fn Model::subscriptions(
  self : Model,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @sub.Sub {
  ignore((self, dispatch))
  @sub.none
}
