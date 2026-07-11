///|
fn alpha_term_add(
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState],
  term : @alpha.AlphaTerm,
) -> @egraph.Id {
  match term {
    Int(value) => eg.add(AInt(value))
    Unit => eg.add(AUnit)
    Var(alpha_ref) => eg.add(AVar(alpha_ref))
    Lam(binder, body) => {
      let body_id = alpha_term_add(eg, body)
      eg.add(ALam(binder, body_id))
    }
    App(func, arg) => {
      let func_id = alpha_term_add(eg, func)
      let arg_id = alpha_term_add(eg, arg)
      eg.add(AApp(func_id, arg_id))
    }
    Bop(op, lhs, rhs) => {
      let lhs_id = alpha_term_add(eg, lhs)
      let rhs_id = alpha_term_add(eg, rhs)
      eg.add(ABop(op, lhs_id, rhs_id))
    }
    If(cond, then_, else_) => {
      let cond_id = alpha_term_add(eg, cond)
      let then_id = alpha_term_add(eg, then_)
      let else_id = alpha_term_add(eg, else_)
      eg.add(AIf(cond_id, then_id, else_id))
    }
    LetDef(binder, init) => {
      let init_id = alpha_term_add(eg, init)
      eg.add(ALetDef(binder, init_id))
    }
    Module(defs, body) => {
      let def_ids = defs.map(fn(def) {
        let (binder, init) = def
        (binder, alpha_term_add(eg, init))
      })
      let body_id = alpha_term_add(eg, body)
      eg.add(AModule(def_ids, body_id))
    }
    Error(message) => eg.add(AError(message))
    Hole(index) => eg.add(AHole(index))
  }
}

///|
fn substitute_alpha(
  term : @alpha.AlphaTerm,
  target : @alpha.BinderId,
  replacement : @alpha.AlphaTerm,
) -> @alpha.AlphaTerm {
  match term {
    Var(Bound(id)) => if id == target { replacement } else { term }
    Var(Free(_)) => term
    Lam(binder, body) =>
      if binder.id == target {
        term
      } else {
        @alpha.AlphaTerm::Lam(
          binder,
          substitute_alpha(body, target, replacement),
        )
      }
    App(func, arg) =>
      @alpha.AlphaTerm::App(
        substitute_alpha(func, target, replacement),
        substitute_alpha(arg, target, replacement),
      )
    Bop(op, lhs, rhs) =>
      @alpha.AlphaTerm::Bop(
        op,
        substitute_alpha(lhs, target, replacement),
        substitute_alpha(rhs, target, replacement),
      )
    If(cond, then_, else_) =>
      @alpha.AlphaTerm::If(
        substitute_alpha(cond, target, replacement),
        substitute_alpha(then_, target, replacement),
        substitute_alpha(else_, target, replacement),
      )
    LetDef(binder, init) =>
      @alpha.AlphaTerm::LetDef(
        binder,
        substitute_alpha(init, target, replacement),
      )
    Module(defs, body) =>
      substitute_alpha_module(defs, body, target, replacement)
    Int(_) | Unit | Error(_) | Hole(_) => term
  }
}

///|
fn substitute_alpha_module(
  defs : Array[(@alpha.Binder, @alpha.AlphaTerm)],
  body : @alpha.AlphaTerm,
  target : @alpha.BinderId,
  replacement : @alpha.AlphaTerm,
) -> @alpha.AlphaTerm {
  let substituted_defs : Array[(@alpha.Binder, @alpha.AlphaTerm)] = []
  let body_visible = for def in defs; target_visible = true {
    let (binder, init) = def
    let substituted_init = if target_visible {
      substitute_alpha(init, target, replacement)
    } else {
      init
    }
    substituted_defs.push((binder, substituted_init))
    continue target_visible && binder.id != target
  } nobreak {
    target_visible
  }
  let substituted_body = if body_visible {
    substitute_alpha(body, target, replacement)
  } else {
    body
  }
  @alpha.AlphaTerm::Module(substituted_defs, substituted_body)
}

///|
fn rec_expr_to_alpha(rec : @egraph.RecExpr[AlphaLang]) -> @alpha.AlphaTerm {
  let nodes = rec.nodes
  let terms : Array[@alpha.AlphaTerm] = []
  for node in nodes {
    let term = match node {
      AInt(value) => @alpha.AlphaTerm::Int(value)
      AUnit => @alpha.AlphaTerm::Unit
      AVar(alpha_ref) => @alpha.AlphaTerm::Var(alpha_ref)
      ALam(binder, body) => @alpha.AlphaTerm::Lam(binder, terms[body.0])
      AApp(func, arg) => @alpha.AlphaTerm::App(terms[func.0], terms[arg.0])
      ABop(op, lhs, rhs) =>
        @alpha.AlphaTerm::Bop(op, terms[lhs.0], terms[rhs.0])
      AIf(cond, then_, else_) =>
        @alpha.AlphaTerm::If(terms[cond.0], terms[then_.0], terms[else_.0])
      ALetDef(binder, init) => @alpha.AlphaTerm::LetDef(binder, terms[init.0])
      AModule(defs, body) =>
        @alpha.AlphaTerm::Module(
          defs.map(fn(def) {
            let (binder, init) = def
            (binder, terms[init.0])
          }),
          terms[body.0],
        )
      AError(message) => @alpha.AlphaTerm::Error(message)
      AHole(index) => @alpha.AlphaTerm::Hole(index)
      ASubst(target, value, body) =>
        substitute_alpha(terms[body.0], target, terms[value.0])
    }
    terms.push(term)
  }
  match terms {
    [.., root] => root
    [] => abort("empty extracted alpha expression")
  }
}
