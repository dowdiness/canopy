// Seeding: convert @ast.Term → egglog database facts for Tier 2 evaluation.
//
// The egglog evaluator works on database-level facts (Num, Var, Add, etc.).
// This module bridges the gap by recursively converting a Term AST into
// the corresponding egglog table entries.

///|
/// Recursively seed a Term into an egglog database, returning the egglog
/// expression id. Each AST node becomes one or more table entries.
///
/// Module is desugared to nested Let (right-folded):
///   Module([(x,e1),(y,e2)], body) → Let(x, e1, Let(y, e2, body))
pub fn seed_term(db : @egglog.Database, term : @ast.Term) -> @egglog.Value {
  match term {
    Int(n) => db.call("Num", [@egglog.IntVal(n)])
    Unit => db.call("Unit", [])
    Var(x) => db.call("Var", [@egglog.StrVal(x)])
    Lam(x, body) => db.call("Lam", [@egglog.StrVal(x), seed_term(db, body)])
    App(f, arg) => db.call("App", [seed_term(db, f), seed_term(db, arg)])
    Bop(Plus, a, b) => db.call("Add", [seed_term(db, a), seed_term(db, b)])
    Bop(Minus, a, b) => db.call("Minus", [seed_term(db, a), seed_term(db, b)])
    If(c, t, e) =>
      db.call("If", [seed_term(db, c), seed_term(db, t), seed_term(db, e)])
    Module(defs, body) => {
      // Right-fold into nested Let: last def wraps body, first def is outermost
      let mut result = seed_term(db, body)
      for i = defs.length() - 1; i >= 0; i = i - 1 {
        let (name, expr) = defs[i]
        result = db.call("Let", [
          @egglog.StrVal(name),
          seed_term(db, expr),
          result,
        ])
      }
      result
    }
    Hole(tag) => db.call("HoleNode", [@egglog.IntVal(tag)])
    Error(msg) => db.call("ErrorNode", [@egglog.StrVal(msg)])
    Unbound(name) => db.call("UnboundNode", [@egglog.StrVal(name)])
  }
}

///|
/// Seed a Tier 1 Value into egglog as a value fact.
/// Used to build environments for escalation from successful Tier 1 results.
fn seed_value(db : @egglog.Database, val : @lambda_eval.Value) -> @egglog.Value {
  match val {
    VInt(n) => db.call("ValInt", [@egglog.IntVal(n)])
    VUnit => db.call("ValUnit", [])
    VClosure(env, x, body) => {
      // Seed the closure's captured environment and body
      let env_id = seed_env(db, env)
      let body_id = seed_term(db, body)
      db.call("Closure", [env_id, @egglog.StrVal(x), body_id])
    }
  }
}

///|
/// Seed a Tier 1 Env into egglog, creating ValueEnv entries for all bindings.
fn seed_env(db : @egglog.Database, env : @lambda_eval.Env) -> @egglog.Value {
  build_partial_env(db, env.bindings.iter().map(fn(p) { (p.0, p.1) }).collect())
}

///|
/// Build a ValueEnv from a list of (name, Tier1 Value) bindings.
/// Used by batch escalation to construct partial environments
/// from successfully-evaluated definitions.
fn build_partial_env(
  db : @egglog.Database,
  bindings : Array[(String, @lambda_eval.Value)],
) -> @egglog.Value {
  let mut val_env = @egglog_eval.ValueEnv::make(db)
  for binding in bindings {
    let (name, value) = binding
    val_env = val_env.extend(db, name, seed_value(db, value))
  }
  val_env.id
}

///|
/// Convert an egglog value id to a display string.
/// Scans ValInt, Closure, and ValUnit tables to determine the value type.
fn extract_egglog_value_string(
  db : @egglog.Database,
  val : @egglog.Value,
) -> String? {
  let val_id = egglog_find(db, val)
  for row in db.scan("ValInt") {
    let (args, result) = row
    if egglog_find(db, result) == val_id {
      match args[0] {
        @egglog.IntVal(n) => return Some(n.to_string())
        _ => ()
      }
    }
  }
  for row in db.scan("Closure") {
    let (_, result) = row
    if egglog_find(db, result) == val_id {
      return Some("\u{2039}closure\u{203a}")
    }
  }
  for row in db.scan("ValUnit") {
    let (_, result) = row
    if egglog_find(db, result) == val_id {
      return Some("()")
    }
  }
  None
}

///|
/// Find the canonical id for an egglog Value.
fn egglog_find(db : @egglog.Database, v : @egglog.Value) -> @egglog.Id {
  match v {
    @egglog.IdVal(id) => db.find(id)
    _ => abort("egglog_find: expected IdVal")
  }
}
