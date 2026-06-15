///|
pub fn alpha_eq(left : AlphaTerm, right : AlphaTerm) -> Bool {
  let left_to_right : Map[BinderId, BinderId] = {}
  let right_to_left : Map[BinderId, BinderId] = {}
  alpha_eq_term(left, right, left_to_right, right_to_left)
}

///|
fn alpha_eq_ref(
  left : AlphaRef,
  right : AlphaRef,
  left_to_right : Map[BinderId, BinderId],
  right_to_left : Map[BinderId, BinderId],
) -> Bool {
  match (left, right) {
    (Bound(left_id), Bound(right_id)) =>
      left_to_right
      .get(left_id)
      .map_or(
        right_to_left
        .get(right_id)
        .map_or(left_id == right_id, mapped => mapped == left_id),
        mapped => mapped == right_id,
      )
    (Free(left_free), Free(right_free)) => left_free == right_free
    _ => false
  }
}

///|
fn alpha_eq_lam(
  left_binder : Binder,
  left_body : AlphaTerm,
  right_binder : Binder,
  right_body : AlphaTerm,
  left_to_right : Map[BinderId, BinderId],
  right_to_left : Map[BinderId, BinderId],
) -> Bool {
  let next_left = left_to_right.copy()
  let next_right = right_to_left.copy()
  next_left[left_binder.id] = right_binder.id
  next_right[right_binder.id] = left_binder.id
  alpha_eq_term(left_body, right_body, next_left, next_right)
}

///|
fn alpha_eq_module(
  left_defs : Array[(Binder, AlphaTerm)],
  left_body : AlphaTerm,
  right_defs : Array[(Binder, AlphaTerm)],
  right_body : AlphaTerm,
  left_to_right : Map[BinderId, BinderId],
  right_to_left : Map[BinderId, BinderId],
) -> Bool {
  guard left_defs.length() == right_defs.length() else { return false }
  let next_left = left_to_right.copy()
  let next_right = right_to_left.copy()
  let defs_match = for i in 0..<left_defs.length(); ok = true {
    if !ok {
      continue false
    }
    let (left_binder, left_init) = left_defs[i]
    let (right_binder, right_init) = right_defs[i]
    let same_init = alpha_eq_term(left_init, right_init, next_left, next_right)
    next_left[left_binder.id] = right_binder.id
    next_right[right_binder.id] = left_binder.id
    continue same_init
  } nobreak {
    ok
  }
  defs_match && alpha_eq_term(left_body, right_body, next_left, next_right)
}

///|
fn alpha_eq_term(
  left : AlphaTerm,
  right : AlphaTerm,
  left_to_right : Map[BinderId, BinderId],
  right_to_left : Map[BinderId, BinderId],
) -> Bool {
  match (left, right) {
    (Int(left_value), Int(right_value)) => left_value == right_value
    (Unit, Unit) => true
    (Var(left_ref), Var(right_ref)) =>
      alpha_eq_ref(left_ref, right_ref, left_to_right, right_to_left)
    (Lam(left_binder, left_body), Lam(right_binder, right_body)) =>
      alpha_eq_lam(
        left_binder, left_body, right_binder, right_body, left_to_right, right_to_left,
      )
    (App(left_fn, left_arg), App(right_fn, right_arg)) =>
      alpha_eq_term(left_fn, right_fn, left_to_right, right_to_left) &&
      alpha_eq_term(left_arg, right_arg, left_to_right, right_to_left)
    (Bop(left_op, left_lhs, left_rhs), Bop(right_op, right_lhs, right_rhs)) =>
      left_op == right_op &&
      alpha_eq_term(left_lhs, right_lhs, left_to_right, right_to_left) &&
      alpha_eq_term(left_rhs, right_rhs, left_to_right, right_to_left)
    (If(left_cond, left_then, left_else), If(right_cond, right_then, right_else)
    ) =>
      alpha_eq_term(left_cond, right_cond, left_to_right, right_to_left) &&
      alpha_eq_term(left_then, right_then, left_to_right, right_to_left) &&
      alpha_eq_term(left_else, right_else, left_to_right, right_to_left)
    (LetDef(_, left_init), LetDef(_, right_init)) =>
      alpha_eq_term(left_init, right_init, left_to_right, right_to_left)
    (Module(left_defs, left_body), Module(right_defs, right_body)) =>
      alpha_eq_module(
        left_defs, left_body, right_defs, right_body, left_to_right, right_to_left,
      )
    (Error(left_message), Error(right_message)) => left_message == right_message
    (Hole(left_index), Hole(right_index)) => left_index == right_index
    _ => false
  }
}
