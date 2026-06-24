///|
// Private e-node language for the Canopy Lambda alpha adapter.
//
// This is not a generic `dowdiness/egraph` language: it embeds Canopy's
// `@alpha.Binder`, `@alpha.AlphaRef`, and named-source reification policy so the
// shared egraph engine can optimize Lambda terms without owning Canopy-specific
// scope or projection dependencies.
priv enum AlphaLang {
  AInt(Int)
  AUnit
  AVar(@alpha.AlphaRef)
  ALam(@alpha.Binder, @egraph.Id)
  AApp(@egraph.Id, @egraph.Id)
  ABop(@ast.Bop, @egraph.Id, @egraph.Id)
  AIf(@egraph.Id, @egraph.Id, @egraph.Id)
  ALetDef(@alpha.Binder, @egraph.Id)
  AModule(Array[(@alpha.Binder, @egraph.Id)], @egraph.Id)
  AError(String)
  AHole(Int)
  ASubst(@alpha.BinderId, @egraph.Id, @egraph.Id)
} derive(Eq)

///|
fn hash_bop_index(op : @ast.Bop) -> Int {
  match op {
    Plus => 0
    Minus => 1
  }
}

///|
fn hash_origin(origin : @alpha.BinderOrigin, hasher : Hasher) -> Unit {
  match origin {
    SourceDecl(node_id~, hint~) => {
      hasher.combine_int(0)
      hasher.combine_int(node_id.0)
      hasher.combine_string(hint)
    }
    Generated(salt) => {
      hasher.combine_int(1)
      hasher.combine_int(salt)
    }
  }
}

///|
fn hash_binder(binder : @alpha.Binder, hasher : Hasher) -> Unit {
  binder.id.hash_combine(hasher)
  hasher.combine_string(binder.hint)
  hash_origin(binder.origin, hasher)
}

///|
fn hash_free_origin(origin : @alpha.FreeOrigin, hasher : Hasher) -> Unit {
  match origin {
    SourceVar => hasher.combine_int(0)
    SourceUnbound => hasher.combine_int(1)
    GeneratedFree => hasher.combine_int(2)
  }
}

///|
fn hash_free_name(free : @alpha.FreeName, hasher : Hasher) -> Unit {
  hasher.combine_string(free.name)
  hash_free_origin(free.origin, hasher)
}

///|
fn hash_ref(alpha_ref : @alpha.AlphaRef, hasher : Hasher) -> Unit {
  match alpha_ref {
    Bound(id) => {
      hasher.combine_int(0)
      id.hash_combine(hasher)
    }
    Free(free) => {
      hasher.combine_int(1)
      hash_free_name(free, hasher)
    }
  }
}

///|
impl Hash for AlphaLang with fn hash_combine(self, hasher) {
  match self {
    AInt(value) => {
      hasher.combine_int(0)
      hasher.combine_int(value)
    }
    AUnit => hasher.combine_int(1)
    AVar(alpha_ref) => {
      hasher.combine_int(2)
      hash_ref(alpha_ref, hasher)
    }
    ALam(binder, body) => {
      hasher.combine_int(3)
      hash_binder(binder, hasher)
      body.hash_combine(hasher)
    }
    AApp(func, arg) => {
      hasher.combine_int(4)
      func.hash_combine(hasher)
      arg.hash_combine(hasher)
    }
    ABop(op, lhs, rhs) => {
      hasher.combine_int(5)
      hasher.combine_int(hash_bop_index(op))
      lhs.hash_combine(hasher)
      rhs.hash_combine(hasher)
    }
    AIf(cond, then_, else_) => {
      hasher.combine_int(6)
      cond.hash_combine(hasher)
      then_.hash_combine(hasher)
      else_.hash_combine(hasher)
    }
    ALetDef(binder, init) => {
      hasher.combine_int(7)
      hash_binder(binder, hasher)
      init.hash_combine(hasher)
    }
    AModule(defs, body) => {
      hasher.combine_int(8)
      hasher.combine_int(defs.length())
      defs
      .iter()
      .each(fn(def) {
        let (binder, init) = def
        hash_binder(binder, hasher)
        init.hash_combine(hasher)
      })
      body.hash_combine(hasher)
    }
    AError(message) => {
      hasher.combine_int(9)
      hasher.combine_string(message)
    }
    AHole(index) => {
      hasher.combine_int(10)
      hasher.combine_int(index)
    }
    ASubst(target, value, body) => {
      hasher.combine_int(11)
      target.hash_combine(hasher)
      value.hash_combine(hasher)
      body.hash_combine(hasher)
    }
  }
}

///|
impl @egraph.ENode for AlphaLang with fn arity(self) {
  match self {
    AInt(_) | AUnit | AVar(_) | AError(_) | AHole(_) => 0
    ALam(_, _) | ALetDef(_, _) => 1
    AApp(_, _) | ABop(_, _, _) | ASubst(_, _, _) => 2
    AIf(_, _, _) => 3
    AModule(defs, _) => defs.length() + 1
  }
}

///|
impl @egraph.ENode for AlphaLang with fn child(self, i) {
  match self {
    ALam(_, body) | ALetDef(_, body) => body
    AApp(func, arg) | ABop(_, func, arg) | ASubst(_, func, arg) =>
      if i == 0 {
        func
      } else {
        arg
      }
    AIf(cond, then_, else_) =>
      if i == 0 {
        cond
      } else if i == 1 {
        then_
      } else {
        else_
      }
    AModule(defs, body) => if i < defs.length() { defs[i].1 } else { body }
    AInt(_) | AUnit | AVar(_) | AError(_) | AHole(_) => abort("no children")
  }
}

///|
impl @egraph.ENode for AlphaLang with fn map_children(self, f) {
  match self {
    AInt(_) | AUnit | AVar(_) | AError(_) | AHole(_) => self
    ALam(binder, body) => ALam(binder, f(body))
    AApp(func, arg) => AApp(f(func), f(arg))
    ABop(op, lhs, rhs) => ABop(op, f(lhs), f(rhs))
    AIf(cond, then_, else_) => AIf(f(cond), f(then_), f(else_))
    ALetDef(binder, init) => ALetDef(binder, f(init))
    AModule(defs, body) =>
      AModule(
        defs.map(fn(def) {
          let (binder, init) = def
          (binder, f(init))
        }),
        f(body),
      )
    ASubst(target, value, body) => ASubst(target, f(value), f(body))
  }
}

///|
impl @egraph.ENodeRepr for AlphaLang with fn op_tag(self) {
  match self {
    AInt(_) => "Num"
    AUnit => "Unit"
    AVar(_) => "Var"
    ALam(_, _) => "Lam"
    AApp(_, _) => "App"
    ABop(Plus, _, _) => "Add"
    ABop(Minus, _, _) => "Minus"
    AIf(_, _, _) => "If"
    ALetDef(_, _) => "LetDef"
    AModule(_, _) => "Module"
    AError(_) => "Error"
    AHole(_) => "Hole"
    ASubst(_, _, _) => "Subst"
  }
}

///|
impl @egraph.ENodeRepr for AlphaLang with fn payload(self) {
  match self {
    AInt(value) => Some(value.to_string())
    AVar(Free(free)) => Some(free.name)
    AVar(Bound(id)) => Some(id.0.to_string())
    ALam(binder, _) | ALetDef(binder, _) => Some(binder.hint)
    AError(message) => Some(message)
    AHole(index) => Some(index.to_string())
    AUnit
    | AApp(_, _)
    | ABop(_, _, _)
    | AIf(_, _, _)
    | AModule(_, _)
    | ASubst(_, _, _) => None
  }
}

///|
impl @egraph.ENodeRepr for AlphaLang with fn from_op(tag, payload, children) {
  match (tag, payload, children) {
    ("Num", Some(s), []) => Some(AInt(@string.parse_int(s))) catch { _ => None }
    ("Unit", None, []) => Some(AUnit)
    ("Var", Some(name), []) =>
      Some(AVar(Free({ name, origin: @alpha.FreeOrigin::GeneratedFree })))
    ("Add", None, [lhs, rhs]) => Some(ABop(Plus, lhs, rhs))
    ("Minus", None, [lhs, rhs]) => Some(ABop(Minus, lhs, rhs))
    ("App", None, [func, arg]) => Some(AApp(func, arg))
    ("If", None, [cond, then_, else_]) => Some(AIf(cond, then_, else_))
    _ => None
  }
}
