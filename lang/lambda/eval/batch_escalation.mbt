// Batch escalation: Tier 1 → Tier 2 for incomplete programs.
//
// When Tier 1 (direct eval) encounters a stuck expression (hole, parse error),
// it suppresses all subsequent definitions. Tier 2 (egglog relational eval)
// can evaluate around holes — independent definitions that don't depend on
// the stuck binding can still produce results.
//
// Algorithm:
// 1. Run Tier 1 sequentially (already done by eval_memo)
// 2. If any results are Suppressed, re-walk the Module to extract defs/terms
// 3. Re-evaluate the successful prefix to recover raw Values for env construction
// 4. Build partial environments: include Value bindings, exclude Stuck names
// 5. Seed suppressed defs into one egglog Database with partial envs
// 6. Run Datalog + Bridge loop until fixpoint
// 7. Merge: Tier 1 Value/Stuck stay; Suppressed replaced by Tier 2 if resolved

///|
/// Maximum rounds of iterative forward propagation.
/// A chain of N dependent definitions after a hole needs N rounds.
const MAX_ESCALATION_ROUNDS = 10

///|
/// Internal state tracking per-definition evaluation for escalation.
priv struct DefState {
  name : String
  term : @ast.Term
  result : EvalResult
  raw_value : @lambda_eval.Value?
}

///|
/// Build the escalation memo that merges Tier 1 and Tier 2 results.
///
/// Depends on the Tier 1 eval_memo. If no results are Suppressed,
/// returns Tier 1 results directly (fast path). Otherwise, runs
/// batch egglog evaluation for suppressed definitions.
pub fn build_escalation_memo(
  rt : @incr.Runtime,
  eval_memo : @incr.Memo[Array[EvalResult]],
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  parser : @loom.ImperativeParser[@ast.Term],
) -> @incr.Memo[Array[EvalResult]] {
  @incr.Memo::new_no_backdate(
    rt,
    fn() -> Array[EvalResult] {
      let tier1_results = eval_memo.get()
      // Fast path: no suppressed results → no escalation needed
      guard tier1_results.iter().any(fn(r) { r == Suppressed }) else {
        return tier1_results
      }
      // Need syntax_tree dependency for reactive tracking
      let _ = syntax_tree.get()
      let ast = parser.get_tree().unwrap_or(@ast.Term::Unit)
      escalate_suppressed(ast, tier1_results)
    },
    label="escalation_memo",
  )
}

///|
/// Run batch escalation for suppressed definitions.
///
/// Re-walks the Module AST to extract definition terms, re-evaluates the
/// successful prefix to recover raw Values, then runs egglog for each
/// suppressed definition with a partial environment.
fn escalate_suppressed(
  ast : @ast.Term,
  tier1_results : Array[EvalResult],
) -> Array[EvalResult] {
  let (defs, body) = match ast {
    Module(defs, body) => (defs, Some(body))
    _ => return tier1_results // non-Module: nothing to escalate
  }
  // Re-evaluate the successful prefix to recover raw Values and track env state.
  // This duplicates Tier 1 work for the prefix but is necessary to get raw Values.
  let def_states = build_def_states(defs, body, tier1_results)
  // Collect candidates: indices of Suppressed results
  let candidates : Array[Int] = []
  for i, state in def_states {
    if state.result == Suppressed {
      candidates.push(i)
    }
  }
  if candidates.is_empty() {
    return tier1_results
  }
  // Run batch egglog evaluation
  run_batch_egglog(def_states, candidates)
}

///|
/// Re-evaluate the Module's successful prefix to recover raw Values.
///
/// For each definition:
/// - If Tier 1 result is Value: re-evaluate to get the raw Value
/// - If Tier 1 result is Stuck: mark name as blocked (shadows earlier bindings)
/// - If Tier 1 result is Suppressed: record for escalation
fn build_def_states(
  defs : Array[(@ast.VarName, @ast.Term)],
  body : @ast.Term?,
  tier1_results : Array[EvalResult],
) -> Array[DefState] {
  let states : Array[DefState] = []
  let mut env = @lambda_eval.Env::empty()
  for i, def in defs {
    let (name, expr) = def
    let result = tier1_results.get(i).unwrap_or(Suppressed)
    match result {
      Value(_) => {
        // Re-evaluate to get the raw Value for env construction.
        // Cannot fail: Tier 1 already produced Value for this exact env+expr.
        let raw = @lambda_eval.eval(env, expr) catch {
          e =>
            abort(
              "build_def_states: Tier 1 said Value but re-eval failed: " +
              e.to_string(),
            )
        }
        env = env.extend(name, raw)
        states.push({ name, term: expr, result, raw_value: Some(raw) })
      }
      Stuck(_) =>
        // Stuck binding shadows the name but provides no value.
        // Do NOT extend env — downstream Tier 1 re-evaluation will fail
        // on lookup, which is correct. The egglog escalation path uses
        // blocked_names in run_batch_egglog to exclude this name from
        // partial environments.
        states.push({ name, term: expr, result, raw_value: None })
      Suppressed => states.push({ name, term: expr, result, raw_value: None })
    }
  }
  // Body
  if body is Some(body_term) {
    let body_result = if defs.length() < tier1_results.length() {
      tier1_results[defs.length()]
    } else {
      Suppressed
    }
    states.push({
      name: "_body",
      term: body_term,
      result: body_result,
      raw_value: None,
    })
  }
  states
}

///|
/// Run batch egglog evaluation for suppressed definitions with forward
/// propagation: recovered values from earlier defs feed into later ones.
///
/// Uses iterative evaluation: each round evaluates all unresolved candidates,
/// collects newly-resolved values, and feeds them forward. Converges when
/// no new resolutions occur or all candidates are resolved.
fn run_batch_egglog(
  def_states : Array[DefState],
  candidates : Array[Int],
) -> Array[EvalResult] {
  let results : Array[EvalResult] = def_states.map(fn(s) { s.result })
  let rules = @egglog_eval.eval_rules()
  let recovered_values : Map[Int, @lambda_eval.Value] = {}
  for i, state in def_states {
    match state.raw_value {
      Some(v) => recovered_values[i] = v
      None => ()
    }
  }
  // Iterative escalation: keep resolving until no progress
  let mut unresolved = candidates
  for round = 0; round < MAX_ESCALATION_ROUNDS; round = round + 1 {
    if unresolved.is_empty() {
      break
    }
    let mut progress = false
    let next_unresolved : Array[Int] = []
    for candidate_idx in unresolved {
      let state = def_states[candidate_idx]
      let db = @egglog_eval.lambda_eval_db()
      // Build partial env: reverse walk handles shadowing via seen_names.
      // Defs without a recovered value are simply absent from the env.
      let bindings = build_candidate_bindings(
        def_states, recovered_values, candidate_idx,
      )
      let env_id = build_partial_env(db, bindings)
      let expr_id = seed_term(db, state.term)
      let eval_result = @egglog_eval.run_eval(db, env_id, expr_id, rules)
      match eval_result {
        Some(val) => {
          let display = match extract_egglog_value_string(db, val) {
            Some(s) => Value(s)
            None => Suppressed
          }
          if display is Value(_) {
            results[candidate_idx] = display
            // Recover raw value for forward propagation.
            // On failure, leave unavailable rather than wrongly bound.
            try {
              let env = build_tier1_env(
                def_states, recovered_values, candidate_idx,
              )
              let raw = @lambda_eval.eval(env, state.term)
              recovered_values[candidate_idx] = raw
            } catch {
              _ => ()
            }
            progress = true
          } else {
            next_unresolved.push(candidate_idx)
          }
        }
        None =>
          match db.lookup("EvalError", [env_id, expr_id]) {
            Some(@egglog.StrVal(msg)) => {
              results[candidate_idx] = Stuck(
                "\u{2039}type error: " + msg + "\u{203a}",
              )
              progress = true
            }
            _ => next_unresolved.push(candidate_idx)
          }
      }
    }
    unresolved = next_unresolved
    if !progress {
      break
    }
  }
  results
}

///|
/// Build bindings for a candidate's partial env using reverse walk for shadowing.
/// Later defs shadow earlier ones. Defs without a value (stuck/unresolved)
/// shadow their name — the name is simply absent from the result.
fn build_candidate_bindings(
  def_states : Array[DefState],
  recovered_values : Map[Int, @lambda_eval.Value],
  candidate_idx : Int,
) -> Array[(String, @lambda_eval.Value)] {
  let bindings : Array[(String, @lambda_eval.Value)] = []
  let seen_names : Map[String, Bool] = {}
  for j = candidate_idx - 1; j >= 0; j = j - 1 {
    let prev = def_states[j]
    if seen_names.get(prev.name).unwrap_or(false) {
      continue
    }
    seen_names[prev.name] = true
    match recovered_values.get(j) {
      Some(v) => bindings.push((prev.name, v))
      None => () // stuck/unresolved — name absent, correctly shadows earlier
    }
  }
  bindings
}

///|
/// Build a Tier 1 Env from available values for re-evaluation.
/// Uses forward walk with a mutable map: later defs overwrite earlier ones,
/// and defs without values remove the name (correct shadowing).
fn build_tier1_env(
  def_states : Array[DefState],
  recovered_values : Map[Int, @lambda_eval.Value],
  up_to_index : Int,
) -> @lambda_eval.Env {
  let bindings : Map[String, @lambda_eval.Value] = {}
  for j = 0; j < up_to_index; j = j + 1 {
    let prev = def_states[j]
    match recovered_values.get(j) {
      Some(v) => bindings[prev.name] = v
      None => bindings.remove(prev.name) // stuck def removes the binding
    }
  }
  let mut env = @lambda_eval.Env::empty()
  for name, v in bindings {
    env = env.extend(name, v)
  }
  env
}
