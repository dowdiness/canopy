///|
pub fn[A] text(s : String) -> Layout[A] {
  Text(s)
}

///|
pub fn[A] char(c : Char) -> Layout[A] {
  Text(c.to_string())
}

///|
pub fn[A] line() -> Layout[A] {
  Line
}

///|
pub fn[A] hardline() -> Layout[A] {
  HardLine
}

///|
pub fn[A] softline() -> Layout[A] {
  Group(Line)
}

///|
pub fn[A] nest(layout : Layout[A], indent? : Int = 2) -> Layout[A] {
  Nest(indent, layout)
}

///|
pub fn[A] group(doc : Layout[A]) -> Layout[A] {
  Group(doc)
}

///|
pub fn[A] concat(l : Layout[A], r : Layout[A]) -> Layout[A] {
  Concat(l, r)
}

///|
pub fn[A] annotate(ann : A, doc : Layout[A]) -> Layout[A] {
  Annotate(ann, doc)
}

///|
pub impl[A] Add for Layout[A] with add(self, other) {
  Concat(self, other)
}

///|
pub fn[A] separate(sep : Layout[A], docs : Array[Layout[A]]) -> Layout[A] {
  match docs {
    [] => Empty
    [x, .. xs] => xs.iter().fold(init=x, fn(acc, d) { acc + sep + d })
  }
}

///|
pub fn[A] surround(
  left : Layout[A],
  right : Layout[A],
  doc : Layout[A],
) -> Layout[A] {
  left + doc + right
}

///|
pub fn[A] parens(doc : Layout[A]) -> Layout[A] {
  surround(char('('), char(')'), doc)
}

///|
pub fn[A] brackets(doc : Layout[A]) -> Layout[A] {
  surround(char('['), char(']'), doc)
}

///|
pub fn[A] braces(doc : Layout[A]) -> Layout[A] {
  surround(char('{'), char('}'), doc)
}

///|
pub fn[A] bracket(l : String, r : String, doc : Layout[A]) -> Layout[A] {
  match doc {
    Empty => group(text(l) + text(r))
    _ => group(text(l) + nest(line() + doc) + line() + text(r))
  }
}
