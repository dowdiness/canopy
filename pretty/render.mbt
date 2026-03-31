///|
priv enum Mode {
  Flat
  Break
} derive(Show, Eq)

///|
pub enum Cmd[A] {
  CText(String)
  CNewline(Int)
  CAnnStart(A)
  CAnnEnd(A)
} derive(Show, Eq)

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
  fn go(indent : Int, mode : Mode, column : Int, lay : Layout[A]) -> Int {
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
      Nest(i, doc) => go(indent + i, mode, column, doc)
      Concat(l, r) => {
        let col = go(indent, mode, column, l)
        go(indent, mode, col, r)
      }
      Group(doc) => {
        let m = if flat_width(doc) < width - column { Flat } else { Break }
        go(indent, m, column, doc)
      }
      Annotate(ann, doc) => {
        cmds.push(CAnnStart(ann))
        let col = go(indent, mode, column, doc)
        cmds.push(CAnnEnd(ann))
        col
      }
    }
  }

  let _ = go(0, Break, 0, layout)
  cmds
}
