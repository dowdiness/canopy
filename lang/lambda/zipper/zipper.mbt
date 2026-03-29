// Huet Zipper for the lambda calculus AST.
// TermCtx is the derivative of Term — one-hole contexts.
// Navigation decomposes the tree into focus + context path.

///|
pub(all) enum TermCtx {
  CtxLamBody(@ast.VarName)
  CtxAppFunc(@ast.Term)
  CtxAppArg(@ast.Term)
  CtxBopLeft(@ast.Bop, @ast.Term)
  CtxBopRight(@ast.Bop, @ast.Term)
  CtxIfCond(@ast.Term, @ast.Term)
  CtxIfThen(@ast.Term, @ast.Term)
  CtxIfElse(@ast.Term, @ast.Term)
  CtxModuleDef(
    Array[(@ast.VarName, @ast.Term)],
    @ast.VarName,
    Array[(@ast.VarName, @ast.Term)],
    @ast.Term
  )
  CtxModuleBody(Array[(@ast.VarName, @ast.Term)])
} derive(Show)

///|
pub(all) struct Zipper {
  focus : @ast.Term
  path : @list.List[TermCtx]
} derive(Show)

///|
/// Reconstruct parent from context + child.
fn plug(ctx : TermCtx, child : @ast.Term) -> @ast.Term {
  match ctx {
    CtxLamBody(x) => @ast.Lam(x, child)
    CtxAppFunc(arg) => @ast.App(child, arg)
    CtxAppArg(func) => @ast.App(func, child)
    CtxBopLeft(op, right) => @ast.Bop(op, child, right)
    CtxBopRight(op, left) => @ast.Bop(op, left, child)
    CtxIfCond(then_, else_) => @ast.If(child, then_, else_)
    CtxIfThen(cond, else_) => @ast.If(cond, child, else_)
    CtxIfElse(cond, then_) => @ast.If(cond, then_, child)
    CtxModuleDef(before, name, after, body) => {
      let defs : Array[(@ast.VarName, @ast.Term)] = []
      for def in before {
        defs.push(def)
      }
      defs.push((name, child))
      for def in after {
        defs.push(def)
      }
      @ast.Module(defs, body)
    }
    CtxModuleBody(defs) => @ast.Module(defs, child)
  }
}

///|
/// Focus on first child. Returns None for leaf nodes.
pub fn go_down(z : Zipper) -> Zipper? {
  match z.focus {
    @ast.Lam(x, body) =>
      Some({ focus: body, path: @list.cons(CtxLamBody(x), z.path) })
    @ast.App(f, a) =>
      Some({ focus: f, path: @list.cons(CtxAppFunc(a), z.path) })
    @ast.Bop(op, l, r) =>
      Some({ focus: l, path: @list.cons(CtxBopLeft(op, r), z.path) })
    @ast.If(c, t, e) =>
      Some({ focus: c, path: @list.cons(CtxIfCond(t, e), z.path) })
    @ast.Module(defs, body) =>
      if defs.length() > 0 {
        let first_name = defs[0].0
        let first_val = defs[0].1
        let after : Array[(@ast.VarName, @ast.Term)] = []
        for i in 1..<defs.length() {
          after.push(defs[i])
        }
        Some({
          focus: first_val,
          path: @list.cons(CtxModuleDef([], first_name, after, body), z.path),
        })
      } else {
        Some({ focus: body, path: @list.cons(CtxModuleBody([]), z.path) })
      }
    _ => None
  }
}

///|
/// Focus on parent (plug focus into top context).
pub fn go_up(z : Zipper) -> Zipper? {
  match z.path {
    Empty => None
    More(ctx, tail=rest) => Some({ focus: plug(ctx, z.focus), path: rest })
  }
}

///|
/// Focus on right sibling.
pub fn go_right(z : Zipper) -> Zipper? {
  match z.path {
    More(CtxAppFunc(arg), tail=rest) =>
      Some({ focus: arg, path: @list.cons(CtxAppArg(z.focus), rest) })
    More(CtxBopLeft(op, r), tail=rest) =>
      Some({ focus: r, path: @list.cons(CtxBopRight(op, z.focus), rest) })
    More(CtxIfCond(t, e), tail=rest) =>
      Some({ focus: t, path: @list.cons(CtxIfThen(z.focus, e), rest) })
    More(CtxIfThen(c, e), tail=rest) =>
      Some({ focus: e, path: @list.cons(CtxIfElse(c, z.focus), rest) })
    More(CtxModuleDef(before, name, after, body), tail=rest) =>
      if after.length() > 0 {
        let new_before : Array[(@ast.VarName, @ast.Term)] = []
        for def in before {
          new_before.push(def)
        }
        new_before.push((name, z.focus))
        let next_name = after[0].0
        let next_val = after[0].1
        let new_after : Array[(@ast.VarName, @ast.Term)] = []
        for i in 1..<after.length() {
          new_after.push(after[i])
        }
        Some({
          focus: next_val,
          path: @list.cons(
            CtxModuleDef(new_before, next_name, new_after, body),
            rest,
          ),
        })
      } else {
        let all_defs : Array[(@ast.VarName, @ast.Term)] = []
        for def in before {
          all_defs.push(def)
        }
        all_defs.push((name, z.focus))
        Some({ focus: body, path: @list.cons(CtxModuleBody(all_defs), rest) })
      }
    _ => None
  }
}

///|
/// Focus on left sibling.
pub fn go_left(z : Zipper) -> Zipper? {
  match z.path {
    More(CtxAppArg(func), tail=rest) =>
      Some({ focus: func, path: @list.cons(CtxAppFunc(z.focus), rest) })
    More(CtxBopRight(op, l), tail=rest) =>
      Some({ focus: l, path: @list.cons(CtxBopLeft(op, z.focus), rest) })
    More(CtxIfThen(c, e), tail=rest) =>
      Some({ focus: c, path: @list.cons(CtxIfCond(z.focus, e), rest) })
    More(CtxIfElse(c, t), tail=rest) =>
      Some({ focus: t, path: @list.cons(CtxIfThen(c, z.focus), rest) })
    More(CtxModuleDef(before, name, after, body), tail=rest) =>
      if before.length() > 0 {
        let prev_name = before[before.length() - 1].0
        let prev_val = before[before.length() - 1].1
        let new_before : Array[(@ast.VarName, @ast.Term)] = []
        for i in 0..<(before.length() - 1) {
          new_before.push(before[i])
        }
        let new_after : Array[(@ast.VarName, @ast.Term)] = []
        new_after.push((name, z.focus))
        for def in after {
          new_after.push(def)
        }
        Some({
          focus: prev_val,
          path: @list.cons(
            CtxModuleDef(new_before, prev_name, new_after, body),
            rest,
          ),
        })
      } else {
        None
      }
    More(CtxModuleBody(defs), tail=rest) =>
      if defs.length() > 0 {
        let last_name = defs[defs.length() - 1].0
        let last_val = defs[defs.length() - 1].1
        let new_before : Array[(@ast.VarName, @ast.Term)] = []
        for i in 0..<(defs.length() - 1) {
          new_before.push(defs[i])
        }
        Some({
          focus: last_val,
          path: @list.cons(
            CtxModuleDef(new_before, last_name, [], z.focus),
            rest,
          ),
        })
      } else {
        None
      }
    _ => None
  }
}

///|
/// Go up repeatedly until root, return focus.
pub fn to_root(z : Zipper) -> @ast.Term {
  let mut current = z
  while true {
    match go_up(current) {
      Some(parent) => current = parent
      None => break
    }
  }
  current.focus
}

///|
/// Create Zipper at root.
pub fn from_root(term : @ast.Term) -> Zipper {
  { focus: term, path: @list.new() }
}

///|
/// Count contexts in path (depth from root).
pub fn depth(z : Zipper) -> Int {
  z.path.length()
}

///|
/// List children of a term.
fn children_of(term : @ast.Term) -> Array[@ast.Term] {
  match term {
    @ast.Lam(_, body) => [body]
    @ast.App(f, a) => [f, a]
    @ast.Bop(_, l, r) => [l, r]
    @ast.If(c, t, e) => [c, t, e]
    @ast.Module(defs, body) => {
      let result : Array[@ast.Term] = []
      for def in defs {
        result.push(def.1)
      }
      result.push(body)
      result
    }
    _ => []
  }
}

///|
/// Child index for the hole position in a context.
fn ctx_to_child_index(ctx : TermCtx) -> Int {
  match ctx {
    CtxLamBody(_) => 0
    CtxAppFunc(_) => 0
    CtxAppArg(_) => 1
    CtxBopLeft(_, _) => 0
    CtxBopRight(_, _) => 1
    CtxIfCond(_, _) => 0
    CtxIfThen(_, _) => 1
    CtxIfElse(_, _) => 2
    CtxModuleDef(before, _, _, _) => before.length()
    CtxModuleBody(defs) => defs.length()
  }
}

///|
/// Go down then go right child_idx times.
fn navigate_to_child(z : Zipper, child_idx : Int) -> Zipper? {
  let first = match go_down(z) {
    Some(f) => f
    None => return None
  }
  let mut current = first
  for _ in 0..<child_idx {
    match go_right(current) {
      Some(next) => current = next
      None => return None
    }
  }
  Some(current)
}

///|
/// Convert path to array of child indices (root to focus order).
pub fn to_path_indices(z : Zipper) -> Array[Int] {
  let indices : Array[Int] = []
  let mut p = z.path
  while true {
    match p {
      Empty => break
      More(ctx, tail=rest) => {
        indices.push(ctx_to_child_index(ctx))
        p = rest
      }
    }
  }
  indices.rev_in_place()
  indices
}

///|
/// Replay path indices with ancestor-walk (never fails — stops at deepest reachable node).
pub fn focus_at(term : @ast.Term, indices : Array[Int]) -> Zipper {
  let mut z = from_root(term)
  for idx in indices {
    match navigate_to_child(z, idx) {
      Some(z2) => z = z2
      None => break
    }
  }
  z
}
