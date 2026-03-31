// PrettyLayout: TermSym interpretation that produces Layout[Ann] documents
// for structured pretty-printing with syntax highlighting.

///|
pub struct PrettyLayout {
  layout : @pretty.Layout[@pretty.Ann]
}

///|
fn kw(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate(
    { category: @pretty.SyntaxCategory::Keyword, node_id: None },
    @pretty.text(s),
  )
}

///|
fn ident(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate(
    { category: @pretty.SyntaxCategory::Identifier, node_id: None },
    @pretty.text(s),
  )
}

///|
fn num(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate(
    { category: @pretty.SyntaxCategory::Number, node_id: None },
    @pretty.text(s),
  )
}

///|
fn op(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate(
    { category: @pretty.SyntaxCategory::Operator, node_id: None },
    @pretty.text(s),
  )
}

///|
fn punc(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate(
    { category: @pretty.SyntaxCategory::Punctuation, node_id: None },
    @pretty.text(s),
  )
}

///|
fn err(s : String) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate(
    { category: @pretty.SyntaxCategory::Error, node_id: None },
    @pretty.text(s),
  )
}

///|
pub impl @ast.TermSym for PrettyLayout with int_lit(n) {
  { layout: num(n.to_string()) }
}

///|
pub impl @ast.TermSym for PrettyLayout with var(name) {
  { layout: ident(name) }
}

///|
pub impl @ast.TermSym for PrettyLayout with unit() {
  { layout: punc("()") }
}

///|
pub impl @ast.TermSym for PrettyLayout with lam(x, body) {
  {
    layout: @pretty.group(
      kw("λ") +
      ident(x) +
      punc(".") +
      @pretty.nest(@pretty.line() + body.layout),
    ),
  }
}

///|
pub impl @ast.TermSym for PrettyLayout with app(f, arg) {
  {
    layout: @pretty.group(f.layout + @pretty.nest(@pretty.line() + arg.layout)),
  }
}

///|
pub impl @ast.TermSym for PrettyLayout with bop(b, l, r) {
  let sym = match b {
    @ast.Bop::Plus => "+"
    @ast.Bop::Minus => "-"
  }
  {
    layout: @pretty.group(
      l.layout +
      @pretty.text(" ") +
      op(sym) +
      @pretty.nest(@pretty.line() + r.layout),
    ),
  }
}

///|
pub impl @ast.TermSym for PrettyLayout with if_then_else(cond, then_, else_) {
  {
    layout: @pretty.group(
      kw("if") +
      @pretty.text(" ") +
      cond.layout +
      @pretty.nest(
        @pretty.line() +
        kw("then") +
        @pretty.text(" ") +
        then_.layout +
        @pretty.line() +
        kw("else") +
        @pretty.text(" ") +
        else_.layout,
      ),
    ),
  }
}

///|
pub impl @ast.TermSym for PrettyLayout with module(defs, body) {
  let def_docs : Array[@pretty.Layout[@pretty.Ann]] = defs.map(fn(d) {
    let (name, val) = d
    kw("let") +
    @pretty.text(" ") +
    ident(name) +
    @pretty.text(" ") +
    op("=") +
    @pretty.text(" ") +
    @pretty.nest(val.layout)
  })
  def_docs.push(body.layout)
  { layout: @pretty.separate(@pretty.hardline(), def_docs) }
}

///|
pub impl @ast.TermSym for PrettyLayout with unbound(name) {
  { layout: err("<unbound: " + name + ">") }
}

///|
pub impl @ast.TermSym for PrettyLayout with error_term(msg) {
  { layout: err("<error: " + msg + ">") }
}

///|
pub impl @ast.TermSym for PrettyLayout with hole(_n) {
  { layout: err("_") }
}
