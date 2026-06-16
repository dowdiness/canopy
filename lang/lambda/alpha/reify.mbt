///|
pub fn reify(term : AlphaTerm, policy : ReifyPolicy) -> @ast.Term {
  let env : Map[BinderId, String] = {}
  let used : Array[String] = []
  reify_with(term, policy, env, used)
}

///|
fn push_unique(names : Array[String], name : String) -> Unit {
  if !names.contains(name) {
    names.push(name)
  }
}

///|
fn merged_names(left : Array[String], right : Array[String]) -> Array[String] {
  let result = left.copy()
  for name in right {
    push_unique(result, name)
  }
  result
}

///|
fn free_names(term : AlphaTerm) -> Array[String] {
  match term {
    Var(Free(free)) => [free.name]
    Var(Bound(_)) => []
    Lam(_, body) => free_names(body)
    App(func, arg) => merged_names(free_names(func), free_names(arg))
    Bop(_, lhs, rhs) => merged_names(free_names(lhs), free_names(rhs))
    If(cond, then_, else_) =>
      merged_names(
        merged_names(free_names(cond), free_names(then_)),
        free_names(else_),
      )
    LetDef(_, init) => free_names(init)
    Module(defs, body) => {
      let result = free_names(body)
      for def in defs {
        let (_, init) = def
        for name in free_names(init) {
          push_unique(result, name)
        }
      }
      result
    }
    Int(_) | Unit | Error(_) | Hole(_) => []
  }
}

///|
fn suffix_free_names(
  defs : Array[(Binder, AlphaTerm)],
  body : AlphaTerm,
  start : Int,
) -> Array[String] {
  let result = free_names(body)
  for i in start..<defs.length() {
    let (_, init) = defs[i]
    for name in free_names(init) {
      push_unique(result, name)
    }
  }
  result
}

///|
fn base_hint(hint : String) -> String {
  if hint == "" {
    "x"
  } else {
    hint
  }
}

///|
fn fresh_name(hint : String, avoid : Array[String]) -> String {
  let base = base_hint(hint)
  if !avoid.contains(base) {
    base
  } else {
    for i = 1 {
      let candidate = base + i.to_string()
      if !avoid.contains(candidate) {
        break candidate
      }
      continue i + 1
    }
  }
}

///|
fn reify_ref(
  alpha_ref : AlphaRef,
  policy : ReifyPolicy,
  env : Map[BinderId, String],
) -> @ast.Term {
  match alpha_ref {
    Bound(id) =>
      env
      .get(id)
      .map_or(
        match policy {
          Display => @ast.Term::Unbound("bound")
          Source => @ast.Term::Var("bound")
        },
        name => @ast.Term::Var(name),
      )
    Free(free) =>
      match (policy, free.origin) {
        (Display, SourceUnbound) => @ast.Term::Unbound(free.name)
        _ => @ast.Term::Var(free.name)
      }
  }
}

///|
fn reify_lam(
  binder : Binder,
  body : AlphaTerm,
  policy : ReifyPolicy,
  env : Map[BinderId, String],
  used : Array[String],
) -> @ast.Term {
  let avoid = merged_names(used, free_names(body))
  let name = fresh_name(binder.hint, avoid)
  let next_env = env.copy()
  next_env[binder.id] = name
  let next_used = used.copy()
  push_unique(next_used, name)
  @ast.Term::Lam(name, reify_with(body, policy, next_env, next_used))
}

///|
fn reify_module(
  defs : Array[(Binder, AlphaTerm)],
  body : AlphaTerm,
  policy : ReifyPolicy,
  env : Map[BinderId, String],
  used : Array[String],
) -> @ast.Term {
  let out_defs : Array[(String, @ast.Term)] = []
  let next_env = env.copy()
  let next_used = used.copy()
  for i, def in defs {
    let (binder, init) = def
    let init_term = reify_with(init, policy, next_env, next_used)
    let avoid = merged_names(next_used, suffix_free_names(defs, body, i + 1))
    let name = fresh_name(binder.hint, avoid)
    out_defs.push((name, init_term))
    next_env[binder.id] = name
    push_unique(next_used, name)
  }
  @ast.Term::Module(out_defs, reify_with(body, policy, next_env, next_used))
}

///|
fn reify_with(
  term : AlphaTerm,
  policy : ReifyPolicy,
  env : Map[BinderId, String],
  used : Array[String],
) -> @ast.Term {
  match term {
    Int(value) => @ast.Term::Int(value)
    Unit => @ast.Term::Unit
    Var(alpha_ref) => reify_ref(alpha_ref, policy, env)
    Lam(binder, body) => reify_lam(binder, body, policy, env, used)
    App(func, arg) =>
      @ast.Term::App(
        reify_with(func, policy, env, used),
        reify_with(arg, policy, env, used),
      )
    Bop(op, lhs, rhs) =>
      @ast.Term::Bop(
        op,
        reify_with(lhs, policy, env, used),
        reify_with(rhs, policy, env, used),
      )
    If(cond, then_, else_) =>
      @ast.Term::If(
        reify_with(cond, policy, env, used),
        reify_with(then_, policy, env, used),
        reify_with(else_, policy, env, used),
      )
    LetDef(binder, init) =>
      @ast.Term::LetDef(
        fresh_name(binder.hint, used),
        reify_with(init, policy, env, used),
      )
    Module(defs, body) => reify_module(defs, body, policy, env, used)
    Error(message) => @ast.Term::Error(message)
    Hole(index) => @ast.Term::Hole(index)
  }
}
