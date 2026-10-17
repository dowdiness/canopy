///|
fn EditorMode::kind(self : Self) -> @editor.Mode {
  match self {
    Text => Text
    Preview => Preview
    Split(..) => Split
  }
}

///|
/// The pane the user is reading in this mode.
fn EditorMode::reading_pane(self : Self) -> ScrollPane {
  match self {
    Text => TextPane
    Preview => PreviewPane
    Split(reading~) => reading
  }
}

///|
/// Split opens reading the pane the user came from.
fn EditorMode::chosen(self : Self, kind : @editor.Mode) -> EditorMode {
  match kind {
    Text => Text
    Preview => Preview
    Split => Split(reading=self.reading_pane())
  }
}

///|
/// The only pane on screen is always the one being read.
fn EditorMode::engaged(self : Self, pane : ScrollPane) -> EditorMode {
  match self {
    Split(..) => Split(reading=pane)
    mode => mode
  }
}

///|
fn editor_text_area() -> @dom.HTMLTextAreaElement? {
  guard @dom.document().get_element_by_id(EDITOR_TEXT_ID).to_option()
    is Some(element) else {
    return None
  }
  element.to_html_text_area_element()
}

///|
fn editor_preview_scroll() -> @dom.Element? {
  @dom.document().get_element_by_id("loomark-preview-scroll").to_option()
}

///|
/// Measures the live DOM, so run it before the mode change renders.
fn capture_reading_anchor(
  pane : ScrollPane,
  anchored : @rabbita.Emit[@viewport.ReadingAnchor],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard editor_text_area() is Some(area) else { return }
    let anchor = match pane {
      TextPane => @viewport.text_reading_anchor(area)
      PreviewPane =>
        editor_preview_scroll().bind(preview => {
          @viewport.preview_reading_anchor(area, preview)
        })
    }
    if anchor is Some(anchor) {
      scheduler.add(anchored(anchor))
    }
  })
}

///|
/// Hold the anchor in Preview once the rendering it was taken for is shown.
fn preview_anchor_subscription(
  anchor : @viewport.ReadingAnchor,
  scrolled_away : @rabbita.Cmd,
  activation : Int,
  compact : Bool,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.preview-anchor(\{activation},\{compact},\{anchor.offset},\{anchor.top})",
    @sub.Scope::Local,
    PreviewAnchorSubscription::Hold,
    (_, scheduler) => {
      let mut active = true
      let mut release : (() -> Unit)? = None
      scheduler.add(
        @cmd.custom_cmd(kind=@cmd.after_render, _ => {
          guard active && editor_preview_scroll() is Some(scroll) else {
            return
          }
          release = Some(
            @viewport.hold_preview_anchor(scroll, anchor, () => {
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
          if release is Some(release) {
            release()
          }
        },
        update_tagger: _ => (),
      })
    },
  )
}

///|
priv suberror PreviewAnchorSubscription {
  Hold
}
