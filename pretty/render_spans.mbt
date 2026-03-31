///|
pub fn[A] render_spans(
  layout : Layout[A],
  width? : Int = 80,
) -> Array[(Span, A)] {
  let spans : Array[(Span, A)] = []
  let ann_stack : Array[(A, Int)] = []
  for cmd in resolve(width, layout); offset = 0 {
    match cmd {
      CText(s) => continue offset + s.length()
      CNewline(indent) => continue offset + 1 + indent
      CAnnStart(ann) => {
        ann_stack.push((ann, offset))
        continue offset
      }
      CAnnEnd(_) => {
        if ann_stack.pop() is Some((ann, start)) {
          spans.push(({ start, end: offset }, ann))
        }
        continue offset
      }
    }
  } nobreak {
    ignore(offset)
  }
  spans
}
