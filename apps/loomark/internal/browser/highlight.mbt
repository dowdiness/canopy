///|
/// A live range over part of a text node, as a CSS highlight paints it.
#external
priv type TextRange

///|
extern "js" fn text_nodes(element : @dom.Element) -> FixedArray[@dom.Node] =
  #| (element) => {
  #|   const walker = element.ownerDocument.createTreeWalker(element, NodeFilter.SHOW_TEXT);
  #|   const nodes = [];
  #|   while (walker.nextNode()) nodes.push(walker.currentNode);
  #|   return nodes;
  #| }

///|
extern "js" fn text_data(text : @dom.Node) -> String =
  #| (text) => text.data

///|
extern "js" fn text_range(
  text : @dom.Node,
  start : Int32,
  end : Int32,
) -> TextRange =
  #| (text, start, end) => {
  #|   const range = text.ownerDocument.createRange();
  #|   range.setStart(text, start);
  #|   range.setEnd(text, end);
  #|   return range;
  #| }

///|
extern "js" fn set_highlight(
  name : String,
  ranges : FixedArray[TextRange],
) -> Unit =
  #| (name, ranges) => CSS.highlights.set(name, new Highlight(...ranges))

///|
extern "js" fn delete_highlight(name : String) -> Unit =
  #| (name) => CSS.highlights.delete(name)

///|
priv suberror HighlightOccurrences {
  HighlightOccurrences(@text_search.Query)
}

///|
/// Where a highlight subscription stands: waiting for the first render to
/// find its element, painting in it, or released.
priv enum Highlighting {
  Connecting
  Painting(@dom.Element)
  Stopped
}

///|
/// Paint every occurrence of `query` in the text of `#element_id` with the
/// CSS highlight `name`, after each render while the subscription is active.
/// The element is found once, after the first render, and must stay in the
/// document while the subscription is active. A highlight paints without
/// changing the DOM, so typing that changes `query` keeps its native Undo
/// steps whole; Chromium ends a typing step whenever a node leaves the
/// document.
pub fn highlight_occurrences(
  name : String,
  element_id : String,
  query : @text_search.Query,
) -> @sub.Sub {
  @sub.custom_sub(
    "browser.highlight_occurrences(\{name},\{element_id})",
    Local,
    HighlightOccurrences(query),
    (payload, scheduler) => {
      guard payload is HighlightOccurrences(query) else { return None }
      let mut query = query
      let mut state = Connecting
      let paint_in = (element : @dom.Element) => {
        let ranges = []
        for text in text_nodes(element) {
          for found in query.occurrences(text_data(text)) {
            ranges.push(text_range(text, found.0, found.1))
          }
        }
        set_highlight(name, FixedArray::from_array(ranges))
      }
      let paint = () => {
        match state {
          Connecting => {
            guard @dom.document().get_element_by_id(element_id).to_option()
              is Some(element) else {
              abort("#\{element_id} must be rendered while it is highlighted")
            }
            state = Painting(element)
            paint_in(element)
          }
          Painting(element) => paint_in(element)
          Stopped => ()
        }
      }
      scheduler.queue_command(after_render(paint))
      Some({
        unload: _ => {
          state = Stopped
          delete_highlight(name)
        },
        update_tagger: payload => {
          if payload is HighlightOccurrences(next) {
            query = next
            scheduler.queue_command(after_render(paint))
          }
        },
      })
    },
  )
}
