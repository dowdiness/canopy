///|
/// Precedence levels for parenthesization.
/// Higher number = tighter binding.
let prec_top : Int = 0 // module, let-body

///|
let prec_if : Int = 1 // if-then-else

///|
let prec_lam : Int = 2 // λx. body

///|
let prec_bop : Int = 3 // binary operators (+, -)

///|
let prec_app : Int = 4 // function application

///|
let prec_atom : Int = 5 // literals, variables, parens

///|
pub struct PrettyLayout {
  layout : @pretty.Layout[@pretty.Ann]
  prec : Int // precedence of the outermost construct
}

///|
fn wrap_if_needed(
  child : PrettyLayout,
  ctx_prec : Int,
) -> @pretty.Layout[@pretty.Ann] {
  if child.prec < ctx_prec {
    punc("(") + child.layout + punc(")")
  } else {
    child.layout
  }
}

///|
fn tagged(
  cat : @pretty.SyntaxCategory,
  s : String,
) -> @pretty.Layout[@pretty.Ann] {
  @pretty.annotate({ category: cat, node_id: None }, @pretty.text(s))
}

///|
fn kw(s : String) -> @pretty.Layout[@pretty.Ann] {
  tagged(Keyword, s)
}

///|
fn ident(s : String) -> @pretty.Layout[@pretty.Ann] {
  tagged(Identifier, s)
}

///|
fn num(s : String) -> @pretty.Layout[@pretty.Ann] {
  tagged(Number, s)
}

///|
fn op(s : String) -> @pretty.Layout[@pretty.Ann] {
  tagged(Operator, s)
}

///|
fn punc(s : String) -> @pretty.Layout[@pretty.Ann] {
  tagged(Punctuation, s)
}

///|
fn err(s : String) -> @pretty.Layout[@pretty.Ann] {
  tagged(Error, s)
}

///|
pub impl @ast.TermSym for PrettyLayout with int_lit(n) {
  { layout: num(n.to_string()), prec: prec_atom }
}

///|
pub impl @ast.TermSym for PrettyLayout with var(name) {
  { layout: ident(name), prec: prec_atom }
}

///|
pub impl @ast.TermSym for PrettyLayout with unit() {
  { layout: punc("()"), prec: prec_atom }
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
    prec: prec_lam,
  }
}

///|
pub impl @ast.TermSym for PrettyLayout with app(f, arg) {
  {
    layout: @pretty.group(
      wrap_if_needed(f, prec_app) +
      @pretty.nest(@pretty.line() + wrap_if_needed(arg, prec_atom)),
    ),
    prec: prec_app,
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
      wrap_if_needed(l, prec_bop) +
      @pretty.text(" ") +
      op(sym) +
      @pretty.nest(@pretty.line() + wrap_if_needed(r, prec_bop + 1)),
    ),
    prec: prec_bop,
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
    prec: prec_if,
  }
}

///|
pub impl @ast.TermSym for PrettyLayout with module(defs, body) {
  let def_layouts : Array[@pretty.Layout[@pretty.Ann]] = defs.map(fn(d) {
    let (name, val) = d
    kw("let") +
    @pretty.text(" ") +
    ident(name) +
    @pretty.text(" ") +
    op("=") +
    @pretty.text(" ") +
    @pretty.nest(val.layout)
  })
  let defs_doc = @pretty.separate(@pretty.hardline(), def_layouts)
  let result = if def_layouts.is_empty() {
    body.layout
  } else {
    defs_doc + @pretty.hardline() + body.layout
  }
  { layout: result, prec: prec_top }
}

///|
pub impl @ast.TermSym for PrettyLayout with unbound(name) {
  { layout: err("<unbound: " + name + ">"), prec: prec_atom }
}

///|
pub impl @ast.TermSym for PrettyLayout with error_term(msg) {
  { layout: err("<error: " + msg + ">"), prec: prec_atom }
}

///|
pub impl @ast.TermSym for PrettyLayout with hole(_n) {
  { layout: err("_"), prec: prec_atom }
}
