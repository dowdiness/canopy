///|
enum AlphaKeyRef {
  KBound(Int)
  KUnscopedBound(BinderId)
  KFree(String)
} derive(Eq, Hash)

///|
enum AlphaKeyRepr {
  KInt(Int)
  KUnit
  KVar(AlphaKeyRef)
  KLam(AlphaKeyRepr)
  KApp(AlphaKeyRepr, AlphaKeyRepr)
  KBop(@ast.Bop, AlphaKeyRepr, AlphaKeyRepr)
  KIf(AlphaKeyRepr, AlphaKeyRepr, AlphaKeyRepr)
  KLetDef(AlphaKeyRepr)
  KModule(Array[AlphaKeyRepr], AlphaKeyRepr)
  KError(String)
  KHole(Int)
} derive(Eq)

///|
/// Opaque canonical key for an `AlphaTerm`.
///
/// `AlphaKey` equality and hashing are stable under alpha-renaming of scoped
/// binders. Free references are keyed by their textual free name only; their
/// `FreeOrigin` is diagnostic/source provenance and does not affect the key.
/// The internal representation is private so future hash-consing/egraph work can
/// change the encoding without changing callers.
pub struct AlphaKey {
  priv repr : AlphaKeyRepr
} derive(Eq)

///|
impl Hash for AlphaKeyRepr with fn hash_combine(self, hasher) {
  match self {
    KInt(value) => {
      hasher.combine_int(0)
      hasher.combine_int(value)
    }
    KUnit => hasher.combine_int(1)
    KVar(alpha_ref) => {
      hasher.combine_int(2)
      alpha_ref.hash_combine(hasher)
    }
    KLam(body) => {
      hasher.combine_int(3)
      body.hash_combine(hasher)
    }
    KApp(fn_key, arg_key) => {
      hasher.combine_int(4)
      fn_key.hash_combine(hasher)
      arg_key.hash_combine(hasher)
    }
    KBop(op, lhs_key, rhs_key) => {
      hasher.combine_int(5)
      hasher.combine_int(key_bop_index(op))
      lhs_key.hash_combine(hasher)
      rhs_key.hash_combine(hasher)
    }
    KIf(cond_key, then_key, else_key) => {
      hasher.combine_int(6)
      cond_key.hash_combine(hasher)
      then_key.hash_combine(hasher)
      else_key.hash_combine(hasher)
    }
    KLetDef(init_key) => {
      hasher.combine_int(7)
      init_key.hash_combine(hasher)
    }
    KModule(def_keys, body_key) => {
      hasher.combine_int(8)
      hasher.combine_int(def_keys.length())
      def_keys.iter().each(fn(def_key) { def_key.hash_combine(hasher) })
      body_key.hash_combine(hasher)
    }
    KError(message) => {
      hasher.combine_int(9)
      hasher.combine_string(message)
    }
    KHole(index) => {
      hasher.combine_int(10)
      hasher.combine_int(index)
    }
  }
}

///|
pub impl Hash for AlphaKey with fn hash_combine(self, hasher) {
  self.repr.hash_combine(hasher)
}

///|
/// Build a whole-term canonical key for `term`.
///
/// Binder positions are numbered deterministically from the root traversal, so
/// the result is intended for whole `AlphaTerm` keys rather than context-free
/// subterm extraction.
pub fn alpha_key(term : AlphaTerm) -> AlphaKey {
  let env : Map[BinderId, Int] = Map([])
  let (key, _) = key_term(term, env, 0)
  AlphaKey::{ repr: key }
}

///|
fn key_ref(alpha_ref : AlphaRef, env : Map[BinderId, Int]) -> AlphaKeyRef {
  match alpha_ref {
    Bound(id) =>
      match env.get(id) {
        Some(index) => KBound(index)
        None => KUnscopedBound(id)
      }
    Free(free) => KFree(free.name)
  }
}

///|
fn key_bop_index(op : @ast.Bop) -> Int {
  match op {
    @ast.Bop::Plus => 0
    @ast.Bop::Minus => 1
  }
}

///|
fn key_term(
  term : AlphaTerm,
  env : Map[BinderId, Int],
  next : Int,
) -> (AlphaKeyRepr, Int) {
  match term {
    Int(value) => (KInt(value), next)
    Unit => (KUnit, next)
    Var(alpha_ref) => (KVar(key_ref(alpha_ref, env)), next)
    Lam(binder, body) => {
      let next_env = env.copy()
      next_env[binder.id] = next
      let (body_key, after_body) = key_term(body, next_env, next + 1)
      (KLam(body_key), after_body)
    }
    App(fn_term, arg) => {
      let (fn_key, after_fn) = key_term(fn_term, env, next)
      let (arg_key, after_arg) = key_term(arg, env, after_fn)
      (KApp(fn_key, arg_key), after_arg)
    }
    Bop(op, lhs, rhs) => {
      let (lhs_key, after_lhs) = key_term(lhs, env, next)
      let (rhs_key, after_rhs) = key_term(rhs, env, after_lhs)
      (KBop(op, lhs_key, rhs_key), after_rhs)
    }
    If(cond, then_term, else_term) => {
      let (cond_key, after_cond) = key_term(cond, env, next)
      let (then_key, after_then) = key_term(then_term, env, after_cond)
      let (else_key, after_else) = key_term(else_term, env, after_then)
      (KIf(cond_key, then_key, else_key), after_else)
    }
    LetDef(_, init) => {
      let (init_key, after_init) = key_term(init, env, next)
      (KLetDef(init_key), after_init)
    }
    Module(defs, body) => {
      let next_env = env.copy()
      let def_keys : Array[AlphaKeyRepr] = []
      let current_next = for def in defs; current_next = next {
        let (binder, init) = def
        let (init_key, after_init) = key_term(init, next_env, current_next)
        def_keys.push(init_key)
        next_env[binder.id] = after_init
        continue after_init + 1
      } nobreak {
        current_next
      }
      let (body_key, after_body) = key_term(body, next_env, current_next)
      (KModule(def_keys, body_key), after_body)
    }
    Error(message) => (KError(message), next)
    Hole(index) => (KHole(index), next)
  }
}
