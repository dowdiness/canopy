///|
priv enum ConstValue {
  Unknown
  Known(Int)
  Conflict
} derive(Eq)

///|
priv struct EvalState {
  val : ConstValue
  has_incomplete : Bool
}

///|
fn known_bop_value(op : @ast.Bop, left : Int, right : Int) -> Int {
  match op {
    Plus => left + right
    Minus => left - right
  }
}

///|
fn union_node(
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState],
  class_id : @egraph.Id,
  node : AlphaLang,
) -> Unit {
  eg.union(class_id, eg.add(node)) |> ignore
}

///|
fn subst_id(
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState],
  target : @alpha.BinderId,
  value_id : @egraph.Id,
  body_id : @egraph.Id,
) -> @egraph.Id {
  eg.add(ASubst(target, value_id, body_id))
}

///|
fn subst_defs(
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState],
  defs : Array[(@alpha.Binder, @egraph.Id)],
  target : @alpha.BinderId,
  value_id : @egraph.Id,
) -> (Array[(@alpha.Binder, @egraph.Id)], Bool) {
  for def in defs; state = ([], true) {
    let (rewritten_defs, target_visible) : (
      Array[(@alpha.Binder, @egraph.Id)],
      Bool,
    ) = state
    let (binder, init_id) = def
    let new_init = if target_visible {
      subst_id(eg, target, value_id, init_id)
    } else {
      init_id
    }
    rewritten_defs.push((binder, new_init))
    continue (rewritten_defs, target_visible && binder.id != target)
  } nobreak {
    state
  }
}

///|
fn apply_subst(
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState],
  subst_class : @egraph.Id,
  target : @alpha.BinderId,
  value_id : @egraph.Id,
  node : AlphaLang,
) -> Unit {
  match node {
    AVar(Bound(id)) =>
      if id == target {
        eg.union(subst_class, value_id) |> ignore
      } else {
        union_node(eg, subst_class, AVar(Bound(id)))
      }
    AVar(Free(free)) => union_node(eg, subst_class, AVar(Free(free)))
    AInt(value) => union_node(eg, subst_class, AInt(value))
    AUnit => union_node(eg, subst_class, AUnit)
    ALam(binder, body_id) =>
      if binder.id == target {
        union_node(eg, subst_class, ALam(binder, body_id))
      } else {
        union_node(
          eg,
          subst_class,
          ALam(binder, subst_id(eg, target, value_id, body_id)),
        )
      }
    AApp(func_id, arg_id) =>
      union_node(
        eg,
        subst_class,
        AApp(
          subst_id(eg, target, value_id, func_id),
          subst_id(eg, target, value_id, arg_id),
        ),
      )
    ABop(op, lhs_id, rhs_id) =>
      union_node(
        eg,
        subst_class,
        ABop(
          op,
          subst_id(eg, target, value_id, lhs_id),
          subst_id(eg, target, value_id, rhs_id),
        ),
      )
    AIf(cond_id, then_id, else_id) =>
      union_node(
        eg,
        subst_class,
        AIf(
          subst_id(eg, target, value_id, cond_id),
          subst_id(eg, target, value_id, then_id),
          subst_id(eg, target, value_id, else_id),
        ),
      )
    ALetDef(binder, init_id) =>
      union_node(
        eg,
        subst_class,
        ALetDef(binder, subst_id(eg, target, value_id, init_id)),
      )
    AModule(defs, body_id) => {
      let (new_defs, body_visible) = subst_defs(eg, defs, target, value_id)
      let new_body = if body_visible {
        subst_id(eg, target, value_id, body_id)
      } else {
        body_id
      }
      union_node(eg, subst_class, AModule(new_defs, new_body))
    }
    AError(message) => union_node(eg, subst_class, AError(message))
    AHole(index) => union_node(eg, subst_class, AHole(index))
    ASubst(_, _, _) => ()
  }
}

///|
fn merge_const(left : ConstValue, right : ConstValue) -> ConstValue {
  match (left, right) {
    (Conflict, _) | (_, Conflict) => Conflict
    (Unknown, value) | (value, Unknown) => value
    (Known(left_value), Known(right_value)) =>
      if left_value == right_value {
        left
      } else {
        Conflict
      }
  }
}

///|
fn make_const_value(
  node : AlphaLang,
  get_data : (@egraph.Id) -> EvalState,
) -> ConstValue {
  match node {
    AInt(value) => Known(value)
    ABop(op, lhs, rhs) =>
      match (get_data(lhs).val, get_data(rhs).val) {
        (Known(left), Known(right)) => Known(known_bop_value(op, left, right))
        (Conflict, _) | (_, Conflict) => Conflict
        _ => Unknown
      }
    AIf(cond, then_, else_) =>
      match get_data(cond).val {
        Known(0) => get_data(else_).val
        Known(_) => get_data(then_).val
        Conflict => Conflict
        Unknown => Unknown
      }
    AUnit
    | AVar(_)
    | ALam(_, _)
    | AApp(_, _)
    | ALetDef(_, _)
    | AModule(_, _)
    | AError(_)
    | AHole(_)
    | ASubst(_, _, _) => Unknown
  }
}

///|
fn has_incomplete_node(
  node : AlphaLang,
  get_data : (@egraph.Id) -> EvalState,
) -> Bool {
  match node {
    AError(_) | AHole(_) => true
    AInt(_) | AUnit | AVar(_) => false
    ALam(_, body) | ALetDef(_, body) => get_data(body).has_incomplete
    AApp(func, arg) | ABop(_, func, arg) | ASubst(_, func, arg) =>
      get_data(func).has_incomplete || get_data(arg).has_incomplete
    AIf(cond, then_, else_) =>
      get_data(cond).has_incomplete ||
      get_data(then_).has_incomplete ||
      get_data(else_).has_incomplete
    AModule(defs, body) =>
      get_data(body).has_incomplete ||
      defs
      .iter()
      .any(fn(def) {
        let (_, init) = def
        get_data(init).has_incomplete
      })
  }
}

///|
fn canonical_class(
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState],
  id : @egraph.Id,
) -> @egraph.EClass[AlphaLang]? {
  eg.egraph.classes.get(eg.find(id))
}

///|
fn apply_beta_from_app(
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState],
  class_id : @egraph.Id,
  func_id : @egraph.Id,
  arg_id : @egraph.Id,
) -> Unit {
  if eg.get_data(arg_id).has_incomplete {
    return
  }
  match canonical_class(eg, func_id) {
    None => ()
    Some(func_class) =>
      for func_node in func_class.nodes {
        match func_node {
          ALam(binder, body_id) =>
            eg.union(class_id, eg.add(ASubst(binder.id, arg_id, body_id)))
            |> ignore
          _ => ()
        }
      }
  }
}

///|
fn apply_subst_from_node(
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState],
  class_id : @egraph.Id,
  target : @alpha.BinderId,
  value_id : @egraph.Id,
  body_id : @egraph.Id,
) -> Unit {
  match canonical_class(eg, body_id) {
    None => ()
    Some(body_class) =>
      for body_node in body_class.nodes {
        apply_subst(eg, class_id, target, value_id, body_node)
      }
  }
}

///|
fn modify_node(
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState],
  class_id : @egraph.Id,
  node : AlphaLang,
) -> Unit {
  match node {
    AApp(func_id, arg_id) => apply_beta_from_app(eg, class_id, func_id, arg_id)
    ASubst(target, value_id, body_id) =>
      apply_subst_from_node(eg, class_id, target, value_id, body_id)
    _ => ()
  }
}

///|
fn eval_analysis() -> @egraph.Analysis[AlphaLang, EvalState] {
  {
    make: fn(node, get_data) {
      {
        val: make_const_value(node, get_data),
        has_incomplete: has_incomplete_node(node, get_data),
      }
    },
    merge: fn(left, right) {
      let val = merge_const(left.val, right.val)
      let has_incomplete = left.has_incomplete || right.has_incomplete
      let result : EvalState = { val, has_incomplete }
      (
        result,
        {
          a_changed: left.val != val || left.has_incomplete != has_incomplete,
          b_changed: right.val != val || right.has_incomplete != has_incomplete,
        },
      )
    },
    modify: fn(eg, id) {
      match eg.get_data(id).val {
        Known(value) => union_node(eg, id, AInt(value))
        Unknown | Conflict => ()
      }
      let class_id = eg.find(id)
      match eg.egraph.classes.get(class_id) {
        None => ()
        Some(class) =>
          for node in class.nodes {
            modify_node(eg, class_id, node)
          }
      }
    },
  }
}
