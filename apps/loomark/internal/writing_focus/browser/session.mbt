///|
priv suberror WritingFocusError {
  InvalidAnimationClock
  UnsupportedAnimationState(String)
  MissingFocusElement(String)
}

///|
priv enum WritingIntent {
  Reading
  Writing
  TabNavigation
}

///|
priv struct WritingFocusSession {
  text_area : @dom.HTMLTextAreaElement
  dimming_layer : @dom.HTMLElement
  document : @dom.Document
  window : @dom.Window
  fonts : @dom.EventTarget
  reduced_motion : @dom.MediaQueryList
  text_layout : TextLayout
  cleanup : Array[() -> Unit]
  mut frame : Double?
  mut intent : WritingIntent
  mut presentation : @writing_focus.Presentation?
  shades : Array[WritingShade]
}

///|
priv enum WritingFocusLifetime {
  Attached(WritingFocusSession)
  Removed
}

///|
priv struct WritingFocus {
  mut lifetime : WritingFocusLifetime
}

///|
fn draw_writing_focus(session : WritingFocusSession) -> Unit raise {
  let (range, geometry_changed) = session.text_layout.locate_focus()
  if session.intent is TabNavigation {
    session.intent = if session.text_area.matches(":focus") {
      Writing
    } else {
      Reading
    }
  }
  let presentation : @writing_focus.Presentation = {
    range,
    engaged: session.intent is Writing,
    reduced_motion: session.reduced_motion.get_matches(),
  }
  let scroll_top = session.text_area.get_scroll_top()
  let viewport_range = @writing_focus.Range(
    scroll_top,
    scroll_top + session.text_area.get_client_height(),
  )
  let dimming = presentation.dimming(session.presentation, geometry_changed~)
  match dimming {
    Unchanged =>
      for shade in session.shades {
        if shade.content is Visible(range, _) {
          position_writing_shade(shade.element, range, viewport_range)
        }
      }
    Immediate(focus_range) | Animated(focus_range) => {
      let animate = dimming is Animated(_)
      let samples = if animate {
        session.shades.filter_map(shade => {
          sample_writing_shade(session.window, shade)
        })
      } else {
        []
      }
      let fades = @writing_focus.calculate_dimming_ranges(
        focus_range,
        samples[:],
        @browser_api.document_timeline_time(session.document).to_option(),
        animate~,
      )
      render_writing_fades(
        session.document,
        session.dimming_layer,
        session.shades,
        viewport_range,
        fades,
      )
    }
  }
  session.presentation = Some(presentation)
}

///|
fn remove_writing_focus(focus : WritingFocus) -> Unit {
  match focus.lifetime {
    Removed => ()
    Attached(session) => {
      focus.lifetime = Removed
      if session.frame is Some(frame) {
        session.window.cancel_animation_frame(frame)
      }
      for stop in session.cleanup {
        stop()
      }
      clear_writing_shades(session.dimming_layer, session.shades[:])
      session.text_layout.remove()
    }
  }
}

///|
fn report_writing_focus_error(error : @js.Any) -> Unit {
  @js.global()
  .get("console")
  .call("error", [@js.any("Loomark could not update writing focus:"), error])
  |> ignore
}

///|
fn schedule_writing_focus(focus : WritingFocus) -> Unit {
  match focus.lifetime {
    Removed => ()
    Attached(session) =>
      if session.frame is None {
        session.frame = Some(
          session.window.request_animation_frame(_ => {
            match focus.lifetime {
              Removed => ()
              Attached(session) => {
                session.frame = None
                ignore(
                  @js.try_sync(() => {
                    draw_writing_focus(session) catch {
                      error => {
                        remove_writing_focus(focus)
                        report_writing_focus_error(@js.any(error))
                      }
                    }
                    @js.any(())
                  }),
                ) catch {
                  @js.JsError(error) => {
                    remove_writing_focus(focus)
                    report_writing_focus_error(error)
                  }
                }
              }
            }
          }),
        )
      }
  }
}

///|
fn set_writing_intent(focus : WritingFocus, intent : WritingIntent) -> Unit {
  match focus.lifetime {
    Removed => ()
    Attached(session) => {
      session.intent = intent
      schedule_writing_focus(focus)
    }
  }
}

///|
fn add_focus_listener(
  session : WritingFocusSession,
  target : @dom.EventTarget,
  name : String,
  listener : @dom.Listener,
) -> Unit {
  target.add_event_listener(name, listener)
  session.cleanup.push(() => target.remove_event_listener(name, listener))
}

///|
fn add_writing_focus(
  text_area : @dom.HTMLTextAreaElement,
  dimming_layer : @dom.HTMLElement,
) -> WritingFocus raise @js.JsError {
  let session : WritingFocusSession = @js.try_sync(() => {
    let document = @browser_api.element_document(text_area.as_element())
    let window = @browser_api.document_window(document)
    let fonts = @browser_api.document_fonts(document)
    let reduced_motion = window.match_media("(prefers-reduced-motion: reduce)")
    let text_layout = TextLayout(document, window, text_area, dimming_layer)
    let session : WritingFocusSession = {
      text_area,
      dimming_layer,
      document,
      window,
      fonts,
      reduced_motion,
      text_layout,
      cleanup: [],
      frame: None,
      intent: if text_area.matches(":focus") {
        Writing
      } else {
        Reading
      },
      presentation: None,
      shades: [],
    }
    @js.any(session)
  }).cast()
  let focus : WritingFocus = { lifetime: Attached(session), }
  errdefer remove_writing_focus(focus)
  @js.try_sync(() => {
    let changed : @dom.Listener = _ => refresh_writing_focus(focus)
    let selected : @dom.Listener = _ => schedule_writing_focus(focus)
    let resized : @dom.Listener = _ => writing_focus_layout_changed(focus)
    let activate : @dom.Listener = _ => set_writing_intent(focus, Writing)
    let deactivate : @dom.Listener = _ => set_writing_intent(focus, Reading)
    let source = text_area.as_event_target()
    for name in ["input", "compositionend"] {
      add_focus_listener(session, source, name, changed)
    }
    for name in ["select", "selectionchange", "scroll"] {
      add_focus_listener(session, source, name, selected)
    }
    for name in ["focus", "pointerdown", "keydown", "input", "compositionstart"] {
      add_focus_listener(session, source, name, activate)
    }
    add_focus_listener(session, source, "blur", _ => {
      set_writing_intent(focus, Reading)
      session.text_layout.release_retired_lines()
    })
    add_focus_listener(
      session,
      session.window.as_event_target(),
      "blur",
      deactivate,
    )
    add_focus_listener(
      session,
      session.document.as_event_target(),
      "selectionchange",
      selected,
    )
    add_focus_listener(session, session.document.as_event_target(), "keydown", event => {
      if event.to_keyboard_event() is Some(key) && key.key() == "Tab" {
        set_writing_intent(focus, TabNavigation)
      }
    })
    add_focus_listener(session, session.fonts, "loadingdone", resized)
    add_focus_listener(
      session,
      session.window.as_event_target(),
      "resize",
      resized,
    )
    add_focus_listener(
      session,
      session.reduced_motion.as_event_target(),
      "change",
      selected,
    )
    let resize = @dom.ResizeObserver::new((_, _) => {
      writing_focus_layout_changed(focus)
    })
    session.cleanup.push(() => resize.disconnect())
    resize.observe(text_area.as_element())
    schedule_writing_focus(focus)
    @js.any(())
  })
  |> ignore
  focus
}

///|
fn refresh_writing_focus(focus : WritingFocus) -> Unit {
  match focus.lifetime {
    Removed => ()
    Attached(session) => {
      session.text_layout.source_pending = true
      schedule_writing_focus(focus)
    }
  }
}

///|
fn writing_focus_layout_changed(focus : WritingFocus) -> Unit {
  match focus.lifetime {
    Removed => ()
    Attached(session) => {
      let layout = session.text_layout
      layout.context = {
        geometry: @writing_focus.Layout(layout.context.geometry.source()),
        first_observation: true,
      }
      layout.source_pending = true
      schedule_writing_focus(focus)
    }
  }
}
