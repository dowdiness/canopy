///|
/// Dimming of the paragraphs around the writing group, as in Focus Mode.
priv struct Dimming {
  mut intent : @writing_focus.WritingIntent
  mut presentation : @writing_focus.Presentation?
}

///|
/// The drawn caret, and dimming while it is attached, over one text area and
/// its dimming layer from `connect` until `disconnect`. `disconnect` releases
/// every listener, frame and timer, so none of them runs afterwards.
struct WritingFocus {
  text_area : @dom.HTMLTextAreaElement
  dimming_layer : @dom.HTMLElement
  document : @dom.Document
  window : @dom.Window
  fonts : @dom.EventTarget
  reduced_motion : @dom.MediaQueryList
  text_layout : WritingMeasurement
  cleanup : Array[() -> Unit]
  fail : (@js.Any) -> Unit
  mut frame : Double?
  mut dimming : Dimming?
  /// Shade elements stay in the layer once created and are hidden when
  /// unused: removing nodes interrupts Chromium's native typing undo group.
  shades : Array[WritingShade]
  caret : WritingCaret
}

///|
/// Reads every layout this frame needs before any rendering writes, so one
/// frame forces at most one layout.
fn draw_writing_focus(focus : WritingFocus) -> Unit raise {
  let (measured, geometry_changed) = focus.text_layout.measure(
    focus.text_area,
    focus.dimming_layer,
  )
  let dimmed = match focus.dimming {
    Some(dimming) =>
      Some(
        (
          dimming,
          focus.text_layout.locate_focus(
            focus.text_area,
            measured,
            focus.text_area.get_selection_start(),
            focus.text_area.get_selection_end(),
          ),
        ),
      )
    None => None
  }
  let (caret, scroll_top) = locate_writing_caret(focus, measured)
  if dimmed is Some((dimming, range)) {
    render_dimming(focus, dimming, range, scroll_top, geometry_changed~)
  }
  render_writing_caret(focus.caret, caret)
}

///|
fn render_dimming(
  focus : WritingFocus,
  dimming : Dimming,
  range : @writing_focus.Range,
  scroll_top : Double,
  geometry_changed~ : Bool,
) -> Unit raise {
  dimming.intent = dimming.intent.settle(
    focused=focus.text_area.matches(":focus"),
  )
  let presentation : @writing_focus.Presentation = {
    range,
    engaged: dimming.intent is Writing,
    reduced_motion: focus.reduced_motion.get_matches(),
  }
  let viewport_range = @writing_focus.Range(
    scroll_top,
    scroll_top + focus.text_area.get_client_height(),
  )
  let dimmed = presentation.dimming(dimming.presentation, geometry_changed~)
  match dimmed {
    Unchanged =>
      for shade in focus.shades {
        if shade.content is Visible(range, _) {
          position_writing_shade(shade.element, range, viewport_range)
        }
      }
    Immediate(focus_range) | Animated(focus_range) => {
      let animate = dimmed is Animated(_)
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
  dimming.presentation = Some(presentation)
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
  if self.dimming is Some(dimming) {
    dimming.intent = intent
    self.schedule()
  }
}

///|
/// Attaches dimming, or detaches it and restores full readability at once.
/// The caret and the mirror stay as they are.
pub fn WritingFocus::set_dims(self : WritingFocus, dims : Bool) -> Unit {
  match (self.dimming, dims) {
    (None, true) => {
      self.dimming = Some({
        intent: if self.text_area.matches(":focus") {
          Writing
        } else {
          Reading
        },
        presentation: None,
      })
      self.schedule()
    }
    (Some(_), false) => {
      self.dimming = None
      hide_writing_shades(self.shades[:])
    }
    (None, false) | (Some(_), true) => ()
  }
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
    let text_layout = WritingMeasurement()
    let focus : WritingFocus = {
      text_area,
      dimming_layer,
      document,
      window,
      fonts,
      reduced_motion,
      text_layout,
      cleanup: [],
      fail: on_failure,
      frame: None,
      dimming: None,
      shades: [],
      caret: WritingCaret(document, window, dimming_layer),
    }
    @js.any(focus)
  }).cast()
  errdefer focus.disconnect()
  focus.set_dims(dims)
  @js.try_sync(() => {
    let selected : @dom.Listener = _ => focus.schedule()
    let resized : @dom.Listener = _ => focus.schedule()
    let activate : @dom.Listener = _ => focus.set_intent(Writing)
    let deactivate : @dom.Listener = _ => focus.set_intent(Reading)
    let source = text_area.as_event_target()
    for
      name in ["input", "compositionend", "select", "selectionchange", "scroll"] {
      focus.listen(source, name, selected)
    }
    for name in ["focus", "pointerdown", "keydown", "input", "compositionstart"] {
      focus.listen(source, name, activate)
    }
    focus.listen(source, "blur", _ => focus.set_intent(Reading))
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
    let resize = @dom.ResizeObserver::new((_, _) => focus.schedule())
    focus.cleanup.push(() => resize.disconnect())
    focus.cleanup.push(() => focus.caret.release())
    @browser_api.observe_border_box(resize, text_area.as_element())
    focus.schedule()
    @js.any(())
  })
  |> ignore
  focus
}

///|
/// Redraws after the editor state changes the text.
pub fn WritingFocus::refresh(self : WritingFocus) -> Unit {
  self.schedule()
}
