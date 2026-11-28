///|
priv suberror ElementWidth {
  ElementWidth(@dom.HTMLElement, @cmd.Emit[Double])
}

///|
/// Report the width of `element` now and whenever it changes, while the
/// subscription is active. `element` is resolved once by the app, such as at
/// startup; `id` tells observers of different elements apart.
pub fn element_width(
  id : String,
  element : @dom.HTMLElement,
  measured : @cmd.Emit[Double],
) -> @sub.Sub {
  @sub.custom_sub(
    "browser.element_width(\{id})",
    Local,
    ElementWidth(element, measured),
    (payload, scheduler) => {
      guard payload is ElementWidth(element, tagger) else { return None }
      let mut tagger = tagger
      let observer = @dom.ResizeObserver::new((_, _) => {
        scheduler.queue_command(tagger(element.get_client_width()))
      })
      observer.observe(element.as_element())
      Some({
        unload: _ => observer.disconnect(),
        update_tagger: payload => {
          if payload is ElementWidth(_, next) {
            tagger = next
          }
        },
      })
    },
  )
}

///|
priv suberror RenderedHeights {
  RenderedHeights(String, @cmd.Emit[Array[Int32]])
}

///|
/// After the next render, read the height of every child of `#layer_id` in
/// one pass, rounded up to whole pixels, and send them paired with `items`
/// in order. The view must draw one child per item. A new `id` measures
/// again; ending the subscription first cancels the measurement.
pub fn[T] rendered_heights(
  id : String,
  layer_id : String,
  items : Array[T],
  measured : @cmd.Emit[Array[(T, Int32)]],
) -> @sub.Sub {
  let paired : @cmd.Emit[Array[Int32]] = @cmd.Emit(heights => {
    guard heights.length() == items.length() else {
      abort("#\{layer_id} must hold one child per item")
    }
    measured(items.zip(heights))
  })
  @sub.custom_sub(
    "browser.rendered_heights(\{id})",
    Local,
    RenderedHeights(layer_id, paired),
    (payload, scheduler) => {
      guard payload is RenderedHeights(layer_id, tagger) else { return None }
      let mut tagger = tagger
      let mut wait = Scheduled
      scheduler.queue_command(
        after_render(() => {
          guard wait is Scheduled else { return }
          guard @dom.document().get_element_by_id(layer_id).to_option()
            is Some(layer) else {
            abort("#\{layer_id} must be rendered while it is measured")
          }
          let heights = layer
            .get_children()
            .iter()
            .map(child => {
              child.get_bounding_client_rect().get_height().ceil().to_int()
            })
            .collect()
          scheduler.queue_command(tagger(heights))
        }),
      )
      Some({
        unload: _ => wait = Released,
        update_tagger: payload => {
          if payload is RenderedHeights(_, next) {
            tagger = next
          }
        },
      })
    },
  )
}

///|
priv suberror RenderedWidth {
  RenderedWidth(String, @cmd.Emit[Double])
}

///|
/// After the next render, report the width of `#element_id`, then again
/// whenever it changes, while the subscription is active. For an element the
/// app draws itself, so it cannot be resolved at startup.
pub fn rendered_width(
  element_id : String,
  measured : @cmd.Emit[Double],
) -> @sub.Sub {
  @sub.custom_sub(
    "browser.rendered_width(\{element_id})",
    Local,
    RenderedWidth(element_id, measured),
    (payload, scheduler) => {
      guard payload is RenderedWidth(element_id, tagger) else { return None }
      let mut tagger = tagger
      let mut wait = Scheduled
      let observer = @dom.ResizeObserver::new((_, _) => {
        guard wait is Scheduled else { return }
        guard @dom.document().get_element_by_id(element_id).to_option()
          is Some(element) &&
          element.to_html_element() is Some(element) else {
          return
        }
        scheduler.queue_command(tagger(element.get_client_width()))
      })
      scheduler.queue_command(
        after_render(() => {
          guard wait is Scheduled else { return }
          guard @dom.document().get_element_by_id(element_id).to_option()
            is Some(element) else {
            abort("#\{element_id} must be rendered while its width is observed")
          }
          observer.observe(element)
        }),
      )
      Some({
        unload: _ => {
          wait = Released
          observer.disconnect()
        },
        update_tagger: payload => {
          if payload is RenderedWidth(_, next) {
            tagger = next
          }
        },
      })
    },
  )
}
