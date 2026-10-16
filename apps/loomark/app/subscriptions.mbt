///|
fn subscriptions(
  model : Model,
  emit : @rabbita.Emit[Msg],
  viewport : @sub.Sub,
) -> @sub.Sub {
  @sub.batch([
    viewport,
    match model.page {
      Editing(editing) if model.focus_mode && editing.mode != Preview =>
        @writing_focus_browser.subscription(
          EDITOR_TEXT_ID,
          editing.activation.generation,
          editing.preview,
        )
      _ => @sub.none
    },
    match model.page {
      Editing(editing) =>
        text_area_resize_subscription(
          editing.activation.generation,
          editing.compact,
        )
      _ => @sub.none
    },
    @sub.on_resize(viewport => emit(ViewportChanged(viewport.width))),
    @sub.on_visibility_change(hidden => emit(VisibilityChanged(hidden))),
    @sub.on_key_down(key => {
      if key.key() == "Escape" && !key.is_composing() {
        emit(EscapePressed)
      } else {
        @cmd.none
      }
    }),
    page_restore_subscription(emit(PageRestored)),
    lead_subscriptions(model.page, emit),
    match model.page {
      Editing(editing) if editing.mode == Split =>
        match model.scroll_owner {
          TextPane =>
            split_scroll_subscription(
              "loomark-text",
              "loomark-preview-scroll",
              editing.activation.generation,
              editing.compact,
              editing.preview,
            )
          PreviewPane =>
            split_scroll_subscription(
              "loomark-preview-scroll",
              "loomark-text",
              editing.activation.generation,
              editing.compact,
              editing.preview,
            )
        }
      _ => @sub.none
    },
  ])
}

///|
priv suberror TextAreaResizeSubscription {
  RevealResizedCaret
}

///|
/// Both the activation key and the responsive panel branch can replace the
/// textarea. Resolve its node after rendering and release the old observation.
fn text_area_resize_subscription(activation : Int, compact : Bool) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.text-area-resize(\{activation},\{compact})",
    @sub.Scope::Local,
    TextAreaResizeSubscription::RevealResizedCaret,
    (_, scheduler) => {
      let mut active = true
      let mut stop : (() -> Unit)? = None
      scheduler.add(
        @cmd.custom_cmd(kind=@cmd.after_render, _ => {
          guard active &&
            @dom.document().get_element_by_id(EDITOR_TEXT_ID).to_option()
            is Some(element) &&
            element.to_html_text_area_element() is Some(area) else {
            return
          }
          stop = Some(
            @viewport.observe_text_area_resize(area) catch {
              @js.JsError(error) => {
                @js.global()
                .get("console")
                .call("error", [
                  @js.any("Loomark could not observe the text area:"),
                  error,
                ])
                |> ignore
                return
              }
            },
          )
        }),
      )
      Some({
        unload: _ => {
          active = false
          if stop is Some(stop) {
            stop()
          }
        },
        update_tagger: _ => (),
      })
    },
  )
}

///|
priv suberror SplitScrollSubscription {
  Follow(@editor.EditorState)
}

///|
/// Resolve this render's pair once. Activation and breakpoint changes replace
/// nodes; mode and scroll-owner changes also release the old connection.
fn split_scroll_subscription(
  source : String,
  target : String,
  activation : Int,
  compact : Bool,
  preview : @editor.EditorState,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.split-scroll(\{source},\{target},\{activation},\{compact})",
    @sub.Scope::Local,
    SplitScrollSubscription::Follow(preview),
    (payload, scheduler) => {
      guard payload is SplitScrollSubscription::Follow(preview) else {
        return None
      }
      let mut active = true
      let mut previous_preview = preview
      let mut connection : (() -> Unit, () -> Unit)? = None
      fn sync_after_render() {
        scheduler.add(
          @cmd.custom_cmd(kind=@cmd.after_render, _ => {
            guard active && connection is Some((sync, _)) else { return }
            sync()
          }),
        )
      }
      scheduler.add(
        @cmd.custom_cmd(kind=@cmd.after_render, _ => {
          guard active &&
            @dom.document().get_element_by_id(source).to_option() is Some(from) &&
            @dom.document().get_element_by_id(target).to_option() is Some(to) else {
            return
          }
          let connected = @viewport.connect_split_scroll(
            from, to, sync_after_render,
          )
          connection = Some(connected)
          // A scroll can precede this after-render connection when its owner
          // changes. Catch up from live geometry once the listener is attached.
          let (sync, _) = connected
          sync()
        }),
      )
      Some({
        unload: _ => {
          active = false
          if connection is Some((_, stop)) {
            stop()
          }
          connection = None
        },
        update_tagger: payload => {
          guard payload is SplitScrollSubscription::Follow(next) else { return }
          if previous_preview != next {
            previous_preview = next
            sync_after_render()
          }
        },
      })
    },
  )
}

///|
const LEAD_DELAY_MS : Int = 250

///|
fn lead_subscriptions(model : Page, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  let pending = match model {
    Editing(editing) => editing.documents.pending_edits()
    OpeningNew(preparing, _) => preparing.documents.pending_edits()
    Loading(_) | Recovery(_, _) => []
  }
  @sub.batch(
    pending.map(item => {
      let (key, revision) = item
      let lifecycle_key = key.lifecycle_key()
      @timeout.after(
        "loomark.pending-edit.\{lifecycle_key}-\{revision}",
        LEAD_DELAY_MS,
        emit(ApplyPendingEdit(key, revision)),
      )
    }),
  )
}
