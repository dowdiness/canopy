///|
fn substitute(
  term : AlphaTerm,
  target : BinderId,
  replacement : AlphaTerm,
) -> AlphaTerm {
  match term {
    Var(Bound(id)) => if id == target { replacement } else { term }
    Var(Free(_)) => term
    Lam(binder, body) =>
      if binder.id == target {
        term
      } else {
        Lam(binder, substitute(body, target, replacement))
      }
    App(func, arg) =>
      App(
        substitute(func, target, replacement),
        substitute(arg, target, replacement),
      )
    Bop(op, lhs, rhs) =>
      Bop(
        op,
        substitute(lhs, target, replacement),
        substitute(rhs, target, replacement),
      )
    If(cond, then_, else_) =>
      If(
        substitute(cond, target, replacement),
        substitute(then_, target, replacement),
        substitute(else_, target, replacement),
      )
    LetDef(binder, init) =>
      LetDef(binder, substitute(init, target, replacement))
    Module(defs, body) => substitute_module(defs, body, target, replacement)
    Int(_) | Unit | Error(_) | Hole(_) => term
  }
}

///|
fn substitute_module(
  defs : Array[(Binder, AlphaTerm)],
  body : AlphaTerm,
  target : BinderId,
  replacement : AlphaTerm,
) -> AlphaTerm {
  let substituted_defs : Array[(Binder, AlphaTerm)] = []
  let body_visible = for def in defs; target_visible = true {
    let (binder, init) = def
    let substituted_init = if target_visible {
      substitute(init, target, replacement)
    } else {
      init
    }
    substituted_defs.push((binder, substituted_init))
    continue target_visible && binder.id != target
  } nobreak {
    target_visible
  }
  let substituted_body = if body_visible {
    substitute(body, target, replacement)
  } else {
    body
  }
  Module(substituted_defs, substituted_body)
}

///|
pub fn beta_reduce_root(term : AlphaTerm) -> AlphaTerm? {
  match term {
    App(Lam(binder, body), arg) => Some(substitute(body, binder.id, arg))
    _ => None
  }
}
