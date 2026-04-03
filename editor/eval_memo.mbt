// Eval Memo: Reactive evaluation of lambda terms with result rendering.

///|
pub(all) enum EvalResult {
  Value(String)
  Stuck(String)
  Suppressed
} derive(Show, Eq)

///|
fn render_value(v : @eval.Value) -> String {
  match v {
    VInt(n) => n.to_string()
    VClosure(_, _, _) => "\u{2039}closure\u{203a}"
    VUnit => "()"
  }
}

///|
fn render_stuck(reason : @eval.StuckReason) -> EvalResult {
  match reason {
    Incomplete => Suppressed
    ParseError => Suppressed
    Unbound(name) => Stuck("\u{2039}unbound: " + name + "\u{203a}")
    TypeMismatch(msg) => Stuck("\u{2039}type error: " + msg + "\u{203a}")
    Divergence => Stuck("\u{2039}diverges\u{203a}")
  }
}

///|
/// Evaluate a term and return per-definition results.
/// For Module(defs, body): one result per def + one for body.
/// For non-Module: one result for the whole expression.
pub fn eval_term(term : @ast.Term) -> Array[EvalResult] {
  let results : Array[EvalResult] = []
  match term {
    Module(defs, body) => {
      let mut env = @eval.Env::empty()
      for i, def in defs {
        let (name, expr) = def
        try {
          let v = @eval.eval(env, expr)
          results.push(Value(render_value(v)))
          env = env.extend(name, v)
        } catch {
          reason => {
            results.push(render_stuck(reason))
            // Stop evaluating — env is incomplete
            for _ in (i + 1)..<defs.length() {
              results.push(Suppressed)
            }
            results.push(Suppressed) // body
            return results
          }
        }
      }
      // Evaluate body
      try {
        let v = @eval.eval(env, body)
        results.push(Value(render_value(v)))
      } catch {
        reason => results.push(render_stuck(reason))
      }
    }
    _ =>
      try {
        let v = @eval.eval(@eval.Env::empty(), term)
        results.push(Value(render_value(v)))
      } catch {
        reason => results.push(render_stuck(reason))
      }
  }
  results
}

///|
/// Build a reactive eval memo.
/// Reads `syntax_tree` signal to establish reactive dependency.
pub fn build_eval_memo(
  rt : @incr.Runtime,
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  parser : @loom.ImperativeParser[@ast.Term],
) -> @incr.Memo[Array[EvalResult]] {
  @incr.Memo::new_no_backdate(
    rt,
    fn() -> Array[EvalResult] {
      let _ = syntax_tree.get()
      let ast = parser.get_tree().unwrap_or(@ast.Term::Unit)
      eval_term(ast)
    },
    label="eval_memo",
  )
}
