///|
/// Compute the set of free variables in a Term, given a set of bound names.
/// Follows sequential scoping for Module bindings (matching resolve.mbt).
pub fn free_vars(
  term : @ast.Term,
  env : @immut/hashset.HashSet[String],
) -> @immut/hashset.HashSet[String] {
  match term {
    @ast.Term::Var(x) =>
      if env.contains(x) {
        @immut/hashset.new()
      } else {
        @immut/hashset.new().add(x)
      }
    @ast.Term::Lam(x, body) => free_vars(body, env.add(x))
    @ast.Term::App(f, a) => free_vars(f, env).union(free_vars(a, env))
    @ast.Term::Bop(_, l, r) => free_vars(l, env).union(free_vars(r, env))
    @ast.Term::If(c, t, e) =>
      free_vars(c, env).union(free_vars(t, env)).union(free_vars(e, env))
    @ast.Term::Module(defs, body) => {
      let mut result : @immut/hashset.HashSet[String] = @immut/hashset.new()
      let mut cur_env = env
      for def in defs {
        result = result.union(free_vars(def.1, cur_env))
        cur_env = cur_env.add(def.0)
      }
      result.union(free_vars(body, cur_env))
    }
    _ => @immut/hashset.new() // Int, Unit, Error, Unbound
  }
}
