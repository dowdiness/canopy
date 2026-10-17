///|
fn subscriptions(
  model : Model,
  emit : @rabbita.Emit[Msg],
  window : @dom.Window,
  font_faces : @browser.FontFaceSet,
  viewport : @sub.Sub,
) -> @sub.Sub {
  @sub.batch([
    viewport,
    match model.page {
      Editing(editing) if model.focus_mode && editing.mode != Preview =>
        writing_focus_subscription(
          editing.activation.generation,
          editing.preview,
        )
      _ => @sub.none
    },
    match model.page {
      Editing(editing) =>
        match editing.settled_text() {
          Some(text) => reading_face_subscription(window, font_faces, text)
          None => @sub.none
        }
      _ => @sub.none
    },
    match model.page {
      Editing(editing) =>
        text_placement_subscription(
          editing.text_placement(),
          emit(PaneEngaged(TextPane)),
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
    match model.page {
      Editing(editing) if editing.mode.reading_pane() is PreviewPane &&
        editing.reading_anchor is Some(anchor) &&
        editing.preview.preview_shows_blocks() =>
        preview_anchor_subscription(
          anchor,
          emit(PaneEngaged(PreviewPane)),
          editing.activation.generation,
          editing.compact,
        )
      _ => @sub.none
    },
    lead_subscriptions(model.page, emit),
    match model.page {
      Editing({ mode: Split(reading~), .. } as editing) =>
        match reading {
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
/// The textarea's placement follows from the mode and the held anchor.
fn EditingDocument::text_placement(self : Self) -> @viewport.TextPlacement {
  match (self.mode.reading_pane(), self.reading_anchor) {
    (TextPane, Some(anchor)) => HoldAnchor(anchor)
    (TextPane, None) | (PreviewPane, _) => RevealCaret
  }
}

///|
priv suberror TextPlacementSubscription {
  Place(@viewport.TextPlacement)
}

///|
/// Both the activation key and the responsive panel branch can replace the
/// textarea. Resolve its node after rendering and release the old placement
/// and scroll exposure.
fn text_placement_subscription(
  placement : @viewport.TextPlacement,
  scrolled_away : @rabbita.Cmd,
  activation : Int,
  compact : Bool,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.text-placement(\{activation},\{compact})",
    @sub.Scope::Local,
    TextPlacementSubscription::Place(placement),
    (payload, scheduler) => {
      guard payload is TextPlacementSubscription::Place(placement) else {
        return None
      }
      let mut placement = placement
      let mut active = true
      let mut placing : @viewport.TextPlacing? = None
      let mut stop_exposing_scroll : (() -> Unit)? = None
      scheduler.add(
        @cmd.custom_cmd(kind=@cmd.after_render, _ => {
          guard active && editor_text_area() is Some(area) else { return }
          stop_exposing_scroll = Some(
            @viewport.expose_scroll_top_to_styles(area),
          )
          placing = Some(
            @viewport.place_text_area(area, placement, () => {
              if active {
                scheduler.add(scrolled_away)
              }
            }),
          )
        }),
      )
      Some({
        unload: _ => {
          active = false
          if placing is Some(placing) {
            placing.disconnect()
          }
          if stop_exposing_scroll is Some(stop) {
            stop()
          }
        },
        update_tagger: payload => {
          guard payload is TextPlacementSubscription::Place(next) &&
            next != placement else {
            return
          }
          placement = next
          match next {
            // A new anchor aligns in the mode it was taken for.
            HoldAnchor(_) =>
              scheduler.add(
                @cmd.custom_cmd(kind=@cmd.after_render, _ => {
                  guard active && placing is Some(placing) else { return }
                  placing.place(placement)
                }),
              )
            // A released anchor must not realign before the next render.
            RevealCaret => if placing is Some(placing) { placing.place(next) }
          }
        },
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
/// nodes; mode and reading-pane changes also release the old connection.
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
