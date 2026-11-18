// Imperative shell: the only code that looks up, reads, observes, or writes
// DOM elements. It hands plain values to the core and runs its decisions.

///|
/// Startup connection point. The host page provides `#grid-width`, an empty
/// element laid out like the index's content box; its width is the grid's.
/// The app starts once the card fonts have loaded, so cards are measured in
/// the faces the browser draws.
fn main {
  let document = @dom.document()
  let startup_route = route_of_href(@dom.window().current_url())
  guard document.get_element_by_id("grid-width").to_option() is Some(element) &&
    element.to_html_element() is Some(grid_probe) else {
    abort("the host page must provide #grid-width")
  }
  let page = { grid_probe, fonts: @browser.document_fonts(document), }
  let faces = @browser.document_font_faces(document)
  @browser.load_font_faces(faces, "13.5px \"iA Writer Quattro\"", "Aa")
  @browser.load_font_faces(faces, "13.5px \"IBM Plex Sans JP\"", "あ漢")
  @browser.when_font_faces_ready(faces, () => {
    @rabbita.new(() => app(startup_route, page)).mount("app")
  })
}

///|
/// What the app observes on the host page, resolved once at startup.
priv struct HostPage {
  /// The element whose width the grid follows.
  grid_probe : @dom.HTMLElement
  /// The document's font faces, which report faces that finish loading.
  fonts : @dom.EventTarget
}

///|
/// Read the key press an event describes.
fn key_press(event : @dom.KeyboardEvent) -> KeyPress {
  {
    key: event.key(),
    modified: event.ctrl_key() || event.meta_key() || event.alt_key(),
    composing: event.is_composing(),
  }
}

///|
/// After-render connection point: resolve the element the core chose and move
/// focus to it. The core only asks for elements the view renders, so a missing
/// one is a programming error.
fn focus_after_render(element_id : String) -> Cmd {
  after_render_connection(() => focus_element(element_id))
}

///|
fn focus_element(element_id : String) -> Unit {
  guard @dom.document().get_element_by_id(element_id).to_option()
    is Some(element) &&
    element.to_html_element() is Some(target) else {
    abort("#\{element_id} must be rendered before it is focused")
  }
  target.focus()
}

///|
priv suberror FocusCardSubscription {
  FocusCard(String, Cmd)
}

///|
/// Focus the element `element_id` after the render that draws it, then send
/// `focused`. The core starts this only once the view draws that element.
fn focus_card_subscription(element_id : String, focused : Cmd) -> @sub.Sub {
  @sub.custom_sub(
    "note-index.focus-card(\{element_id})",
    Local,
    FocusCard(element_id, focused),
    (payload, scheduler) => {
      guard payload is FocusCard(element_id, tagger) else { return None }
      let mut tagger = tagger
      let mut wait = Scheduled
      scheduler.queue_command(
        after_render_connection(() => {
          guard wait is Scheduled else { return }
          focus_element(element_id)
          scheduler.queue_command(tagger)
        }),
      )
      Some({
        unload: _ => wait = Released,
        update_tagger: payload => {
          if payload is FocusCard(_, next) {
            tagger = next
          }
        },
      })
    },
  )
}

///|
priv suberror GridWidthSubscription {
  ObserveGridWidth(@dom.HTMLElement, Emit[Double])
}

///|
/// Report the width of `probe` whenever it changes, while the subscription
/// is active. The probe is part of the host page, so it exists from the start.
fn grid_width_subscription(
  probe : @dom.HTMLElement,
  measured : Emit[Double],
) -> @sub.Sub {
  @sub.custom_sub(
    "note-index.grid-width",
    Local,
    ObserveGridWidth(probe, measured),
    (payload, scheduler) => {
      guard payload is ObserveGridWidth(probe, tagger) else { return None }
      let mut tagger = tagger
      let stop = report_width(probe, width => {
        scheduler.queue_command(tagger(width))
      })
      Some({
        unload: _ => stop(),
        update_tagger: payload => {
          if payload is ObserveGridWidth(_, next) {
            tagger = next
          }
        },
      })
    },
  )
}

///|
/// Measure `frame` now and whenever its size changes; returns how to stop.
fn report_width(
  frame : @dom.HTMLElement,
  measured : (Double) -> Unit,
) -> () -> Unit {
  let observer = @dom.ResizeObserver::new((_, _) => {
    measured(frame.get_client_width())
  })
  observer.observe(frame.as_element())
  () => observer.disconnect()
}

///|
priv suberror CardHeightSubscription {
  MeasureCardHeights(Array[CardMeasure], Emit[Array[(CardMeasure, Int)]])
}

///|
/// A connection waits for the render that draws its elements, and may be
/// released first when the subscription ends.
priv enum RenderWait {
  Scheduled
  Released
}

///|
/// Measure the cards `card_measure_view` draws for `measures`, once they are
/// rendered. A new set of measures is a new subscription.
fn card_height_subscription(
  measures : Array[CardMeasure],
  measured : Emit[Array[(CardMeasure, Int)]],
) -> @sub.Sub {
  @sub.custom_sub(
    "note-index.card-heights(\{measures.hash()})",
    Local,
    MeasureCardHeights(measures, measured),
    (payload, scheduler) => {
      guard payload is MeasureCardHeights(measures, tagger) else { return None }
      let mut tagger = tagger
      let mut measurement = Scheduled
      scheduler.queue_command(
        after_render_connection(() => {
          guard measurement is Scheduled else { return }
          guard @dom.document().get_element_by_id("card-measure").to_option()
            is Some(layer) else {
            abort("#card-measure must be rendered while cards are unmeasured")
          }
          let heights = read_card_heights(layer)
          guard heights.length() == measures.length() else {
            abort("#card-measure must hold one card per measure")
          }
          scheduler.queue_command(tagger(measures.zip(heights)))
        }),
      )
      Some({
        unload: _ => measurement = Released,
        update_tagger: payload => {
          if payload is MeasureCardHeights(_, next) {
            tagger = next
          }
        },
      })
    },
  )
}

///|
fn after_render_connection(connect : () -> Unit) -> Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, _ => connect())
}

///|
/// Read every drawn card's height in one pass, rounded up to whole pixels.
fn read_card_heights(layer : @dom.Element) -> Array[Int] {
  layer
  .get_children()
  .iter()
  .map(card => card.get_bounding_client_rect().get_height().ceil().to_int())
  .collect()
}

///|
priv suberror FontsLoadedSubscription {
  ObserveFontsLoaded(@dom.EventTarget, Cmd)
}

///|
/// Send `loaded` whenever font faces finish loading, such as a late web font
/// or a face for characters not drawn before, while the subscription is
/// active.
fn fonts_loaded_subscription(
  fonts : @dom.EventTarget,
  loaded : Cmd,
) -> @sub.Sub {
  @sub.custom_sub(
    "note-index.fonts-loaded",
    Local,
    ObserveFontsLoaded(fonts, loaded),
    (payload, scheduler) => {
      guard payload is ObserveFontsLoaded(fonts, tagger) else { return None }
      let mut tagger = tagger
      let report : @dom.Listener = _ => scheduler.queue_command(tagger)
      fonts.add_event_listener("loadingdone", report)
      Some({
        unload: _ => fonts.remove_event_listener("loadingdone", report),
        update_tagger: payload => {
          if payload is ObserveFontsLoaded(_, next) {
            tagger = next
          }
        },
      })
    },
  )
}

///|
priv suberror OnceAfterSubscription {
  SendOnceAfter(Int, Cmd)
}

///|
/// Send `cmd` once, `ms` after the subscription starts, unless it ends first.
/// A different `key` is a new subscription, so changing it restarts the wait.
fn once_after_subscription(key : String, ms : Int, cmd : Cmd) -> @sub.Sub {
  @sub.custom_sub(key, Local, SendOnceAfter(ms, cmd), (payload, scheduler) => {
    guard payload is SendOnceAfter(ms, tagger) else { return None }
    let mut tagger = tagger
    let window = @dom.window()
    let timeout = window.set_timeout(() => scheduler.queue_command(tagger), ms)
    Some({
      unload: _ => window.clear_timeout(timeout),
      update_tagger: payload => {
        if payload is SendOnceAfter(_, next) {
          tagger = next
        }
      },
    })
  })
}
