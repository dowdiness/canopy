///|
/// Writing focus and the drawn caret, attached to one text area and its
/// dimming layer from `connect` until `disconnect`. `disconnect` releases every
/// listener, frame and timer, so none of them runs afterwards.
struct WritingFocus {
  text_area : @dom.HTMLTextAreaElement
  dimming_layer : @dom.HTMLElement
  document : @dom.Document
  window : @dom.Window
  fonts : @dom.EventTarget
  reduced_motion : @dom.MediaQueryList
  text_layout : TextLayout
  cleanup : Array[() -> Unit]
  /// Whether writing focus dims surrounding paragraphs, as in Focus Mode;
  /// otherwise the session draws only the caret.
  dims : Bool
  fail : (@js.Any) -> Unit
  mut frame : Double?
  mut intent : @writing_focus.WritingIntent
  mut presentation : @writing_focus.Presentation?
  shades : Array[WritingShade]
  caret : WritingCaret
}

///|
fn draw_writing_focus(focus : WritingFocus) -> Unit raise {
  let (range, geometry_changed) = focus.text_layout.locate_focus()
  let (caret, scroll_top) = locate_writing_caret(focus)
  focus.intent = focus.intent.settle(focused=focus.text_area.matches(":focus"))
  let presentation : @writing_focus.Presentation = {
    range,
    engaged: focus.dims && focus.intent is Writing,
    reduced_motion: focus.reduced_motion.get_matches(),
  }
  let viewport_range = @writing_focus.Range(
    scroll_top,
    scroll_top + focus.text_area.get_client_height(),
  )
  let dimming = presentation.dimming(focus.presentation, geometry_changed~)
  match dimming {
    Unchanged =>
      for shade in focus.shades {
        if shade.content is Visible(range, _) {
          position_writing_shade(shade.element, range, viewport_range)
        }
      }
    Immediate(focus_range) | Animated(focus_range) => {
      let animate = dimming is Animated(_)
      let samples = if animate {
        focus.shades.filter_map(shade => {
          sample_writing_shade(focus.window, shade)
        })
      } else {
        []
      }
      let fades = @writing_focus.calculate_dimming_ranges(
        focus_range,
        samples[:],
        @browser_api.document_timeline_time(focus.document).to_option(),
        animate~,
      )
      render_writing_fades(
        focus.document,
        focus.dimming_layer,
        focus.shades,
        viewport_range,
        fades,
      )
    }
  }
  focus.presentation = Some(presentation)
  render_writing_caret(focus.caret, caret)
}

///|
/// Releases every listener, frame, animation and node the session added.
pub fn WritingFocus::disconnect(self : WritingFocus) -> Unit {
  if self.frame is Some(frame) {
    self.window.cancel_animation_frame(frame)
  }
  for stop in self.cleanup {
    stop()
  }
  clear_writing_shades(self.dimming_layer, self.shades[:])
  self.text_layout.remove()
}

///|
/// Hands a failed frame to the owner, which disconnects the session.
fn WritingFocus::draw(self : WritingFocus) -> Unit {
  ignore(
    @js.try_sync(() => {
      draw_writing_focus(self) catch {
        error => (self.fail)(@js.any(error))
      }
      @js.any(())
    }),
  ) catch {
    @js.JsError(error) => (self.fail)(error)
  }
}

///|
/// Coalesces every change before the next frame into one draw.
fn WritingFocus::schedule(self : WritingFocus) -> Unit {
  match self.frame {
    Some(_) => ()
    None =>
      self.frame = Some(
        self.window.request_animation_frame(_ => {
          self.frame = None
          self.draw()
        }),
      )
  }
}

///|
fn WritingFocus::set_intent(
  self : WritingFocus,
  intent : @writing_focus.WritingIntent,
) -> Unit {
  self.intent = intent
  self.schedule()
}

///|
fn WritingFocus::listen(
  self : WritingFocus,
  target : @dom.EventTarget,
  name : String,
  listener : @dom.Listener,
) -> Unit {
  target.add_event_listener(name, listener)
  self.cleanup.push(() => target.remove_event_listener(name, listener))
}

///|
/// Connects to already-resolved nodes: the caller resolves them after
/// rendering and disconnects before they are replaced, or when `on_failure`
/// reports that a frame could not be drawn.
pub fn connect(
  text_area : @dom.HTMLTextAreaElement,
  dimming_layer : @dom.HTMLElement,
  dims~ : Bool,
  on_failure~ : (@js.Any) -> Unit,
) -> WritingFocus raise @js.JsError {
  let focus : WritingFocus = @js.try_sync(() => {
    let document = @browser_api.element_document(text_area.as_element())
    let window = @browser_api.document_window(document)
    let fonts = @browser_api.document_fonts(document)
    let reduced_motion = window.match_media("(prefers-reduced-motion: reduce)")
    let text_layout = TextLayout(document, window, text_area, dimming_layer)
    let focus : WritingFocus = {
      text_area,
      dimming_layer,
      document,
      window,
      fonts,
      reduced_motion,
      text_layout,
      cleanup: [],
      dims,
      fail: on_failure,
      frame: None,
      intent: if text_area.matches(":focus") {
        Writing
      } else {
        Reading
      },
      presentation: None,
      shades: [],
      caret: WritingCaret(document, window, dimming_layer),
    }
    @js.any(focus)
  }).cast()
  errdefer focus.disconnect()
  @js.try_sync(() => {
    let changed : @dom.Listener = _ => focus.refresh()
    let selected : @dom.Listener = _ => focus.schedule()
    let resized : @dom.Listener = _ => focus.layout_changed()
    let activate : @dom.Listener = _ => focus.set_intent(Writing)
    let deactivate : @dom.Listener = _ => focus.set_intent(Reading)
    let source = text_area.as_event_target()
    for name in ["input", "compositionend"] {
      focus.listen(source, name, changed)
    }
    for name in ["select", "selectionchange", "scroll"] {
      focus.listen(source, name, selected)
    }
    for name in ["focus", "pointerdown", "keydown", "input", "compositionstart"] {
      focus.listen(source, name, activate)
    }
    focus.listen(source, "blur", _ => {
      focus.set_intent(Reading)
      focus.text_layout.release_retired_lines()
    })
    focus.listen(focus.window.as_event_target(), "blur", deactivate)
    focus.listen(focus.document.as_event_target(), "selectionchange", selected)
    focus.listen(focus.document.as_event_target(), "keydown", event => {
      if event.to_keyboard_event() is Some(key) && key.key() == "Tab" {
        focus.set_intent(TabNavigation)
      }
    })
    focus.listen(focus.fonts, "loadingdone", resized)
    focus.listen(focus.window.as_event_target(), "resize", resized)
    focus.listen(focus.reduced_motion.as_event_target(), "change", selected)
    let resize = @dom.ResizeObserver::new((_, _) => focus.layout_changed())
    focus.cleanup.push(() => resize.disconnect())
    focus.cleanup.push(() => focus.caret.release())
    resize.observe(text_area.as_element())
    focus.schedule()
    @js.any(())
  })
  |> ignore
  focus
}

///|
/// Rereads the text after the editor state changes it.
pub fn WritingFocus::refresh(self : WritingFocus) -> Unit {
  self.text_layout.source_pending = true
  self.schedule()
}

///|
fn WritingFocus::layout_changed(self : WritingFocus) -> Unit {
  let layout = self.text_layout
  layout.context = TextLayoutContext(
    @writing_focus.Layout(layout.context.geometry.source()),
  )
  layout.source_pending = true
  self.schedule()
}
