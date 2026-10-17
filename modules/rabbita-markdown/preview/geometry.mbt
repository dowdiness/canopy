///|
/// The source text one top-level Preview block renders.
priv struct SourceRange {
  start : Int
  end : Int
} derive(Eq)

///|
/// The Preview content records the ranges of the blocks it renders, so a
/// measurement always pairs each element with the source it shows, even
/// before a newer Preview state has been rendered.
const SOURCE_RANGES_ATTRIBUTE : String = "data-rmd-source-ranges"

///|
fn encode_source_ranges(ranges : ArrayView[SourceRange]) -> String {
  ranges.map(range => "\{range.start}:\{range.end}").join(" ")
}

///|
fn decode_source_ranges(encoded : String) -> Array[SourceRange]? {
  let ranges = []
  for range in encoded.split(" ") {
    guard range.split(":").collect() is [start, end] else { return None }
    ranges.push(
      { start: @string.parse_int(start), end: @string.parse_int(end), } catch {
        _ => return None
      },
    )
  }
  Some(ranges)
}

///|
fn source_ranges_attrs(preview : RenderedPreview?) -> @html.Attrs {
  match preview {
    Some(preview) if !preview.block_ranges.is_empty() =>
      @html.Attrs::build().data_set(
        "rmd-source-ranges",
        encode_source_ranges(preview.block_ranges),
      )
    _ => @html.Attrs::build()
  }
}

///|
/// Whether `State::view` shows rendered blocks, including those it keeps after
/// a later render fails.
pub fn State::shows_blocks(self : State) -> Bool {
  match self.phase {
    Ready(_) | Failed(Some(_)) => true
    Unrequested | Preparing | Failed(None) => false
  }
}

///|
/// Locate a source offset among the blocks: the last block starting at or
/// before it, and how far through that block's source it lies.
fn block_position(
  ranges : ArrayView[SourceRange],
  offset : Int,
) -> (Int, Double) {
  let mut index = 0
  for i, range in ranges {
    guard range.start <= offset else { break }
    index = i
  }
  let range = ranges[index]
  let fraction = if range.end > range.start {
    ((offset - range.start).to_double() / (range.end - range.start).to_double()).clamp(
      min=0.0,
      max=1.0,
    )
  } else {
    0.0
  }
  (index, fraction)
}

///|
/// The source offset `fraction` of the way through a block; the inverse of
/// `block_position` within that block. A fraction below 1 stays inside it.
fn block_offset(range : SourceRange, fraction : Double) -> Int {
  range.start +
  ((range.end - range.start).to_double() * fraction.clamp(min=0.0, max=1.0))
  .floor()
  .to_int()
}

///|
/// Viewport geometry of a rendered Preview, read from the live DOM. Source
/// offsets inside a block are placed in proportion to its height.
pub struct PreviewGeometry {
  priv root : @dom.Element
  priv content : @dom.Element
  priv ranges : Array[SourceRange]
}

///|
/// Measure the Preview rendered by `State::view` inside `root`. `None` when it
/// shows no blocks, or when the page has changed them, as an extension that
/// inserts an element does.
pub fn PreviewGeometry::measure(root : @dom.Element) -> PreviewGeometry? {
  guard root.query_selector(".rmd-preview-content") is Some(content) &&
    content.get_attribute(SOURCE_RANGES_ATTRIBUTE) is Some(encoded) &&
    decode_source_ranges(encoded) is Some(ranges) &&
    content.get_children().length() == ranges.length() else {
    return None
  }
  Some({ root, content, ranges, })
}

///|
fn PreviewGeometry::block_box(self : Self, index : Int) -> (Double, Double) {
  let block = self.content.get_children().item(index.to_double()).unwrap()
  let rect = block.get_bounding_client_rect()
  (rect.get_top(), rect.get_height())
}

///|
/// Viewport top of the place where `offset` is shown.
pub fn PreviewGeometry::top_of(self : Self, offset : Int) -> Double {
  let (index, fraction) = block_position(self.ranges, offset)
  let (top, height) = self.block_box(index)
  top + fraction * height
}

///|
/// The first block whose box reaches below viewport height `top`.
fn PreviewGeometry::first_block_below(self : Self, top : Double) -> Int {
  let mut low = 0
  let mut high = self.ranges.length()
  while low < high {
    let middle = (low + high) / 2
    let (block_top, height) = self.block_box(middle)
    if block_top + height > top {
      high = middle
    } else {
      low = middle + 1
    }
  }
  low
}

///|
/// The source offset shown at viewport height `top`. A height in the gap
/// above a block shows that block's start.
pub fn PreviewGeometry::offset_at(self : Self, top : Double) -> Int {
  let index = self.first_block_below(top)
  guard index < self.ranges.length() else {
    return self.ranges[self.ranges.length() - 1].end
  }
  let range = self.ranges[index]
  let (block_top, height) = self.block_box(index)
  if block_top >= top {
    range.start
  } else {
    block_offset(range, (top - block_top) / height)
  }
}

///|
/// Viewport top and bottom of the area clear of overlaid controls, which the
/// content's padding reserves, and of the notice that sticks over the top of a
/// stale rendering, which can be taller than that padding.
pub fn PreviewGeometry::readable(self : Self) -> (Double, Double) {
  let rect = self.root.get_bounding_client_rect()
  let style = @dom.window().get_computed_style(self.content)
  let top = rect.get_top() + css_pixels(style.get_property_value("padding-top"))
  (
    match self.root.query_selector(".rmd-error-stale") {
      Some(notice) => top.max(notice.get_bounding_client_rect().get_bottom())
      None => top
    },
    rect.get_top() +
    self.root.get_client_height() -
    css_pixels(style.get_property_value("padding-bottom")),
  )
}

///|
pub fn PreviewGeometry::scroll_by(self : Self, delta : Double) -> Unit {
  self.root.set_scroll_top(self.root.get_scroll_top() + delta)
}

///|
fn css_pixels(value : String) -> Double {
  guard value.strip_suffix("px") is Some(number) else { return 0.0 }
  @string.parse_double(number.to_owned()) catch {
    _ => 0.0
  }
}

///|
/// Call `changed` after layout whenever the Preview in `root` or its content
/// changes size, as when fonts or images arrive. Returns the disconnect action.
pub fn observe_preview_layout(
  root : @dom.Element,
  changed : () -> Unit,
) -> () -> Unit {
  let observer = @dom.ResizeObserver::new((_, _) => changed())
  observer.observe(root)
  if root.query_selector(".rmd-preview-content") is Some(content) {
    observer.observe(content)
  }
  () => observer.disconnect()
}
