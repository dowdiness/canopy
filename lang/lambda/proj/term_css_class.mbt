// Typed CSS-class mapping for lambda Term variants.
// Replaces the label-string-parsing `kind_of` in examples/ideal/main/view_outline.mbt.
// See docs/plans/2026-05-16-show-unification.md (Task 1, PR 2).

///|
/// Map a `Term` to its CSS class fragment for the outline
/// `.tree-row.kind-<X>` selectors in `examples/ideal/web/styles/editor.css`.
/// One-to-one with the 11 variants; lower-cased for consistency with the
/// existing CSS taxonomy (`kind-lambda`, `kind-binop`, etc.).
///
/// **Drift between this function and the CSS is not test-enforced** —
/// the inspect tests below pin the returned strings, but not that
/// every returned string has a matching CSS selector. Treat the CSS
/// rule list as the contract; add a selector when adding a variant.
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

///|
/// Render the `Term`'s variant tag (`"Lam"`, `"App"`, ...) via the
/// `Renderable::kind_tag` impl in loom. Provided here so consumers
/// outside this package don't have to import `@loomcore` directly —
/// `lang/lambda/proj` is the seam for lambda-specific projection
/// metadata.
pub fn term_kind_tag(t : @ast.Term) -> String {
  @loomcore.Renderable::kind_tag(t)
}
