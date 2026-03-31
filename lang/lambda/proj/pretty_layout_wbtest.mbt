// Whitebox tests for PrettyLayout TermSym implementation.
// Uses inspect for snapshot-style assertions.

///|
test "PrettyLayout: int_lit" {
  let pl : PrettyLayout = @ast.TermSym::int_lit(42)
  inspect(@pretty.render_string(pl.layout), content="42")
}

///|
test "PrettyLayout: var" {
  let pl : PrettyLayout = @ast.TermSym::var("x")
  inspect(@pretty.render_string(pl.layout), content="x")
}

///|
test "PrettyLayout: unit" {
  let pl : PrettyLayout = @ast.TermSym::unit()
  inspect(@pretty.render_string(pl.layout), content="()")
}

///|
test "PrettyLayout: lam wide" {
  let pl : PrettyLayout = @ast.TermSym::lam("x", @ast.TermSym::var("x"))
  inspect(@pretty.render_string(pl.layout), content="λx. x")
}

///|
test "PrettyLayout: lam narrow" {
  let pl : PrettyLayout = @ast.TermSym::lam("x", @ast.TermSym::var("x"))
  inspect(
    @pretty.render_string(pl.layout, width=4),
    content=(
      #|λx.
      #|  x
    ),
  )
}

///|
test "PrettyLayout: app wide" {
  let pl : PrettyLayout = @ast.TermSym::app(
    @ast.TermSym::var("f"),
    @ast.TermSym::var("x"),
  )
  inspect(@pretty.render_string(pl.layout), content="f x")
}

///|
test "PrettyLayout: app narrow" {
  let pl : PrettyLayout = @ast.TermSym::app(
    @ast.TermSym::var("f"),
    @ast.TermSym::var("x"),
  )
  inspect(
    @pretty.render_string(pl.layout, width=3),
    content=(
      #|f
      #|  x
    ),
  )
}

///|
test "PrettyLayout: bop Plus wide" {
  let pl : PrettyLayout = @ast.TermSym::bop(
    @ast.Bop::Plus,
    @ast.TermSym::var("x"),
    @ast.TermSym::var("y"),
  )
  inspect(@pretty.render_string(pl.layout), content="x + y")
}

///|
test "PrettyLayout: bop Minus wide" {
  let pl : PrettyLayout = @ast.TermSym::bop(
    @ast.Bop::Minus,
    @ast.TermSym::var("a"),
    @ast.TermSym::var("b"),
  )
  inspect(@pretty.render_string(pl.layout), content="a - b")
}

///|
test "PrettyLayout: bop narrow" {
  let pl : PrettyLayout = @ast.TermSym::bop(
    @ast.Bop::Plus,
    @ast.TermSym::var("x"),
    @ast.TermSym::var("y"),
  )
  inspect(
    @pretty.render_string(pl.layout, width=4),
    content=(
      #|x +
      #|  y
    ),
  )
}

///|
test "PrettyLayout: if_then_else wide" {
  let pl : PrettyLayout = @ast.TermSym::if_then_else(
    @ast.TermSym::var("c"),
    @ast.TermSym::var("t"),
    @ast.TermSym::var("e"),
  )
  inspect(@pretty.render_string(pl.layout), content="if c then t else e")
}

///|
test "PrettyLayout: if_then_else narrow" {
  let pl : PrettyLayout = @ast.TermSym::if_then_else(
    @ast.TermSym::var("c"),
    @ast.TermSym::var("t"),
    @ast.TermSym::var("e"),
  )
  inspect(
    @pretty.render_string(pl.layout, width=10),
    content=(
      #|if c
      #|  then t
      #|  else e
    ),
  )
}

///|
test "PrettyLayout: module with definitions" {
  let pl : PrettyLayout = @ast.TermSym::module(
    [("x", @ast.TermSym::int_lit(1)), ("y", @ast.TermSym::int_lit(2))],
    @ast.TermSym::bop(
      @ast.Bop::Plus,
      @ast.TermSym::var("x"),
      @ast.TermSym::var("y"),
    ),
  )
  inspect(
    @pretty.render_string(pl.layout),
    content=(
      #|let x = 1
      #|let y = 2
      #|x + y
    ),
  )
}

///|
test "PrettyLayout: module empty defs" {
  let pl : PrettyLayout = @ast.TermSym::module([], @ast.TermSym::int_lit(42))
  inspect(@pretty.render_string(pl.layout), content="42")
}

///|
test "PrettyLayout: unbound" {
  let pl : PrettyLayout = @ast.TermSym::unbound("x")
  inspect(@pretty.render_string(pl.layout), content="<unbound: x>")
}

///|
test "PrettyLayout: error_term" {
  let pl : PrettyLayout = @ast.TermSym::error_term("oops")
  inspect(@pretty.render_string(pl.layout), content="<error: oops>")
}

///|
test "PrettyLayout: hole" {
  let pl : PrettyLayout = @ast.TermSym::hole(0)
  inspect(@pretty.render_string(pl.layout), content="_")
}
