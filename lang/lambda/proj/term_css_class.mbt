// Typed CSS-class mapping for lambda Term variants.
// Replaces the label-string-parsing `kind_of` in examples/ideal/main/view_outline.mbt.
// See docs/plans/2026-05-16-show-unification.md (Task 1, PR 2).

///|
/// Map a `Term` to its CSS class fragment for the outline/inspector
/// `kind-<X>` selectors in `examples/ideal/web/styles/editor.css`.
/// One-to-one with the 11 variants; lower-cased for consistency with the
/// existing CSS taxonomy (`kind-lambda`, `kind-binop`, etc.).
///
/// **Invariant:** every variant returns a non-empty string whose value
/// matches a `.kind-<X>` selector in `editor.css`. Drift between this
/// function and the CSS is a regression — the inspect tests below
/// document the full enumeration so adding a new Term variant flags
/// the missing case here as a non-exhaustive match.
pub fn term_css_class(t : @ast.Term) -> String {
  match t {
    Int(_) => "int"
    Var(_) => "var"
    Lam(_, _) => "lambda"
    App(_, _) => "app"
    Bop(_, _, _) => "binop"
    If(_, _, _) => "if"
    Module(_, _) => "module"
    Unit => "unit"
    Unbound(_) => "unbound"
    Error(_) => "error"
    Hole(_) => "hole"
  }
}
