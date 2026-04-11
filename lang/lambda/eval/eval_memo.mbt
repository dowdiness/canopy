// Lambda evaluation: term evaluation and eval annotation rendering.
// Moved from editor/eval_memo.mbt to separate language code from framework.

///|
pub(all) enum EvalResult {
  Value(String)
  Stuck(String)
  Suppressed
} derive(Debug, Eq)

///|
pub impl Show for EvalResult with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn render_value(v : @lambda_eval.Value) -> String {
  match v {
    VInt(n) => n.to_string()
    VClosure(_, _, _) => "\u{2039}closure\u{203a}"
    VUnit => "()"
  }
}

///|
fn render_stuck(reason : @lambda_eval.StuckReason) -> EvalResult {
  match reason {
    Incomplete => Suppressed
    ParseError => Suppressed
    Unbound(name) => Stuck("\u{2039}unbound: " + name + "\u{203a}")
    TypeMismatch(msg) => Stuck("\u{2039}type error: " + msg + "\u{203a}")
    Divergence => Stuck("\u{2039}diverges\u{203a}")
  }
}

///|
/// Cached state for one definition, preserving the raw Value for env
/// reconstruction and the Term for change detection.
priv struct CachedDef {
  name : String // binder name (or "_body" for body)
  term : @ast.Term
  result : EvalResult
  raw_value : @lambda_eval.Value?
}

///|
/// Evaluate a term and return per-definition results.
/// For Module(defs, body): one result per def + one for body.
/// For non-Module: one result for the whole expression.
pub fn eval_term(term : @ast.Term) -> Array[EvalResult] {
  eval_term_cached(term, []).0
}

///|
/// Evaluate with incremental caching. Reuses cached results for unchanged
/// definitions in the prefix. Returns (display_results, new_cache).
///
/// Cache invariant: if def i has the same Term and all defs 0..i-1 are
/// cache hits, then def i's result and raw_value are still valid (because
/// evaluation is deterministic and env depends only on preceding values).
fn eval_term_cached(
  term : @ast.Term,
  prev_cache : Array[CachedDef],
) -> (Array[EvalResult], Array[CachedDef]) {
  match term {
    Module(defs, body) => eval_module_cached(defs, body, prev_cache)
    _ => {
      let results : Array[EvalResult] = []
      try {
        let v = @lambda_eval.eval(@lambda_eval.Env::empty(), term)
        results.push(Value(render_value(v)))
      } catch {
        reason => results.push(render_stuck(reason))
      }
      (results, [])
    }
  }
}

///|
/// Incrementally evaluate a Module with caching.
fn eval_module_cached(
  defs : Array[(@ast.VarName, @ast.Term)],
  body : @ast.Term,
  prev_cache : Array[CachedDef],
) -> (Array[EvalResult], Array[CachedDef]) {
  let results : Array[EvalResult] = []
  let new_cache : Array[CachedDef] = []
  let mut env = @lambda_eval.Env::empty()
  // Cache is usable only if shape matches: same number of defs + body.
  let cache_valid = prev_cache.length() == defs.length() + 1
  // Find first changed definition (compare both name AND term)
  let mut first_changed = 0
  if cache_valid {
    first_changed = defs.length()
    for i, def in defs {
      let (name, expr) = def
      if prev_cache[i].name != name || prev_cache[i].term != expr {
        first_changed = i
        break
      }
    }
  }
  // Check body if all defs are unchanged
  let body_changed = if cache_valid && first_changed == defs.length() {
    prev_cache[defs.length()].term != body
  } else {
    true
  }
  // Fast path: nothing changed
  if cache_valid && first_changed == defs.length() && !body_changed {
    return (prev_cache.map(fn(c) { c.result }), prev_cache)
  }
  // Reuse cached prefix (0..first_changed-1)
  for i = 0; i < first_changed; i = i + 1 {
    let cached = prev_cache[i]
    results.push(cached.result)
    new_cache.push(cached)
    match cached.raw_value {
      Some(v) => env = env.extend(defs[i].0, v)
      None => {
        // Stuck in unchanged prefix: env is incomplete.
        // Everything from here onward is Suppressed regardless of changes.
        fill_suppressed(results, new_cache, defs, body, i + 1)
        return (results, new_cache)
      }
    }
  }
  // Re-evaluate from first_changed onward
  for i = first_changed; i < defs.length(); i = i + 1 {
    let (name, expr) = defs[i]
    try {
      let v = @lambda_eval.eval(env, expr)
      let display = Value(render_value(v))
      results.push(display)
      new_cache.push({ name, term: expr, result: display, raw_value: Some(v) })
      env = env.extend(name, v)
    } catch {
      reason => {
        let display = render_stuck(reason)
        results.push(display)
        new_cache.push({ name, term: expr, result: display, raw_value: None })
        fill_suppressed(results, new_cache, defs, body, i + 1)
        return (results, new_cache)
      }
    }
  }
  // Evaluate body
  try {
    let v = @lambda_eval.eval(env, body)
    let display = Value(render_value(v))
    results.push(display)
    new_cache.push({
      name: "_body",
      term: body,
      result: display,
      raw_value: Some(v),
    })
  } catch {
    reason => {
      let display = render_stuck(reason)
      results.push(display)
      new_cache.push({
        name: "_body",
        term: body,
        result: display,
        raw_value: None,
      })
    }
  }
  (results, new_cache)
}

///|
/// Fill remaining definitions and body with Suppressed.
fn fill_suppressed(
  results : Array[EvalResult],
  cache : Array[CachedDef],
  defs : Array[(@ast.VarName, @ast.Term)],
  body : @ast.Term,
  from_index : Int,
) -> Unit {
  for i = from_index; i < defs.length(); i = i + 1 {
    results.push(Suppressed)
    cache.push({
      name: defs[i].0,
      term: defs[i].1,
      result: Suppressed,
      raw_value: None,
    })
  }
  results.push(Suppressed)
  cache.push({ name: "_body", term: body, result: Suppressed, raw_value: None })
}

///|
/// Build a reactive eval memo with incremental caching.
///
/// Two layers of incrementality:
/// - **Inner (CachedDef):** prefix-reuse cache. When only definition N changes,
///   reuses results for definitions 0..N-1 and re-evaluates from N onward.
/// - **Outer (Memo::new backdating):** when the recomputed Array[EvalResult]
///   is structurally equal to the previous one, the memo's changed_at timestamp
///   is preserved, preventing downstream memos (escalation, projection) from
///   recomputing unnecessarily.
pub fn build_eval_memo(
  rt : @incr.Runtime,
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  parser : @loom.ImperativeParser[@ast.Term],
) -> @incr.Memo[Array[EvalResult]] {
  let cache : Ref[Array[CachedDef]] = Ref::new([])
  @incr.Memo::new(
    rt,
    fn() -> Array[EvalResult] {
      let _ = syntax_tree.get()
      let ast = parser.get_tree().unwrap_or(@ast.Term::Unit)
      let (results, new_cache) = eval_term_cached(ast, cache.val)
      cache.val = new_cache
      results
    },
    label="eval_memo",
  )
}

///|
/// Split a Layout at top-level HardLine boundaries.
/// Only descends into Concat nodes — Nest, Group, Annotate are opaque.
pub fn split_at_hardlines(
  layout : @pretty.Layout[@pretty.SyntaxCategory],
) -> Array[@pretty.Layout[@pretty.SyntaxCategory]] {
  let segments : Array[@pretty.Layout[@pretty.SyntaxCategory]] = []
  let parts : Array[@pretty.Layout[@pretty.SyntaxCategory]] = []
  fn flush() -> Unit {
    if parts.is_empty() {
      return
    }
    let mut combined = parts[0]
    for i = 1; i < parts.length(); i = i + 1 {
      combined = combined + parts[i]
    }
    segments.push(combined)
    parts.clear()
  }

  fn walk(l : @pretty.Layout[@pretty.SyntaxCategory]) -> Unit {
    match l {
      HardLine => flush()
      Concat(left, right) => {
        walk(left)
        walk(right)
      }
      Empty => ()
      other => parts.push(other)
    }
  }

  walk(layout)
  flush()
  segments
}

///|
pub fn eval_annotation_layout(
  result : EvalResult,
) -> @pretty.Layout[@pretty.SyntaxCategory]? {
  match result {
    Value(s) =>
      Some(
        @pretty.annotate(
          @pretty.SyntaxCategory::EvalAnnotation,
          @pretty.text("  \u{2192} " + s),
        ),
      )
    Stuck(s) =>
      Some(
        @pretty.annotate(
          @pretty.SyntaxCategory::EvalError,
          @pretty.text("  \u{2192} " + s),
        ),
      )
    Suppressed => None
  }
}

///|
/// Post-process a Layout to inject eval annotations after each segment.
/// Splits the canonical Layout at HardLine boundaries, appends annotation
/// to each segment, and rejoins with HardLine.
pub fn inject_eval_annotations(
  layout : @pretty.Layout[@pretty.SyntaxCategory],
  eval_results : Array[EvalResult],
) -> @pretty.Layout[@pretty.SyntaxCategory] {
  if eval_results.is_empty() {
    return layout
  }
  let segments = split_at_hardlines(layout)
  let annotated : Array[@pretty.Layout[@pretty.SyntaxCategory]] = []
  for i, seg in segments {
    match eval_results.get(i) {
      Some(result) =>
        match eval_annotation_layout(result) {
          Some(ann) => annotated.push(seg + ann)
          None => annotated.push(seg)
        }
      None => annotated.push(seg)
    }
  }
  @pretty.separate(@pretty.hardline(), annotated)
}
