///|
priv enum Mode {
  Flat
  Break
}

///|
pub(all) enum Cmd[A] {
  CText(String)
  CNewline(Int)
  CAnnStart(A)
  CAnnEnd(A)
} derive(Show, Eq)

///|
/// Flat width of content before the first HardLine.
/// If no HardLine exists, returns the full flat_width.
fn[A] prefix_flat_width(layout : Layout[A]) -> Int {
  match layout {
    Empty => 0
    Text(s) => s.length()
    Line => 1
    HardLine => 0
    Nest(_, doc) => prefix_flat_width(doc)
    Concat(l, r) => {
      let lw = prefix_flat_width(l)
      if has_hardline_prefix(l) {
        lw
      } else {
        lw + prefix_flat_width(r)
      }
    }
    Group(doc) => flat_width(doc) // Group flattens if it fits — use full width
    Annotate(_, doc) => prefix_flat_width(doc)
  }
}

///|
fn[A] has_hardline_prefix(layout : Layout[A]) -> Bool {
  match layout {
    Empty | Text(_) | Line => false
    HardLine => true
    Nest(_, doc) => has_hardline_prefix(doc)
    Concat(l, _) => has_hardline_prefix(l)
    Group(_) => false // Group absorbs its content
    Annotate(_, doc) => has_hardline_prefix(doc)
  }
}

///|
fn[A] flat_width(layout : Layout[A]) -> Int {
  match layout {
    Empty => 0
    Text(s) => s.length()
    Line => 1
    HardLine => -1
    Nest(_, doc) => flat_width(doc)
    Concat(l, r) => {
      let lw = flat_width(l)
      guard lw >= 0 else { -1 }
      let rw = flat_width(r)
      guard rw >= 0 else { -1 }
      lw + rw
    }
    Group(doc) => flat_width(doc)
    Annotate(_, doc) => flat_width(doc)
  }
}

///|
pub fn[A] resolve(width : Int, layout : Layout[A]) -> Array[Cmd[A]] {
  let cmds : Array[Cmd[A]] = []
  // suffix_fw: flat width of content that follows on the same line.
  // Used by Group to decide Flat vs Break — the group's content plus
  // whatever suffix shares the line must fit within the remaining width.
  fn go(
    indent : Int,
    mode : Mode,
    column : Int,
    lay : Layout[A],
    suffix_fw : Int,
  ) -> Int {
    match lay {
      Empty => column
      Text(s) => {
        cmds.push(CText(s))
        column + s.length()
      }
      Line =>
        match mode {
          Flat => {
            cmds.push(CText(" "))
            column + 1
          }
          Break => {
            cmds.push(CNewline(indent))
            indent
          }
        }
      HardLine => {
        cmds.push(CNewline(indent))
        indent
      }
      Nest(i, doc) => go(indent + i, mode, column, doc, suffix_fw)
      Concat(l, r) => {
        let r_fw = flat_width(r)
        let left_suffix = if r_fw >= 0 {
          r_fw + suffix_fw
        } else {
          prefix_flat_width(r) + suffix_fw
        }
        let col = go(indent, mode, column, l, left_suffix)
        go(indent, mode, col, r, suffix_fw)
      }
      Group(doc) => {
        let fw = flat_width(doc)
        let m = if fw >= 0 && fw + suffix_fw <= width - column {
          Flat
        } else {
          Break
        }
        go(indent, m, column, doc, suffix_fw)
      }
      Annotate(ann, doc) => {
        cmds.push(CAnnStart(ann))
        let col = go(indent, mode, column, doc, suffix_fw)
        cmds.push(CAnnEnd(ann))
        col
      }
    }
  }

  let _ = go(0, Break, 0, layout, 0)
  cmds
}
