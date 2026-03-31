///|
pub fn[A] render_string(layout : Layout[A], width? : Int = 80) -> String {
  let buf = StringBuilder::new()
  for cmd in resolve(width, layout) {
    match cmd {
      CText(s) => buf.write_string(s)
      CNewline(indent) => {
        buf.write_char('\n')
        for _ in 0..<indent {
          buf.write_char(' ')
        }
      }
      CAnnStart(_) | CAnnEnd(_) => ()
    }
  }
  buf.to_string()
}
