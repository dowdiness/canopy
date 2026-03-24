// TreeNode and Renderable implementations for @ast.Term.

///|
pub impl TreeNode for @ast.Term with children(self) {
  match self {
    Lam(_, body) => [body]
    App(f, a) => [f, a]
    Bop(_, l, r) => [l, r]
    If(c, t, e) => [c, t, e]
    Module(defs, body) => {
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
pub impl TreeNode for @ast.Term with same_kind(self, other) {
  match (self, other) {
    (Int(_), Int(_)) => true
    (Var(_), Var(_)) => true
    (Lam(_, _), Lam(_, _)) => true
    (App(_, _), App(_, _)) => true
    (Bop(op1, _, _), Bop(op2, _, _)) => op1 == op2
    (If(_, _, _), If(_, _, _)) => true
    (Module(_, _), Module(_, _)) => true
    (Unit, Unit) => true
    (Error(_), Error(_)) => true
    (Unbound(_), Unbound(_)) => true
    _ => false
  }
}

///|
pub impl Renderable for @ast.Term with kind_tag(self) {
  match self {
    Int(_) => "Int"
    Var(_) => "Var"
    Lam(_, _) => "Lam"
    App(_, _) => "App"
    Bop(_, _, _) => "Bop"
    If(_, _, _) => "If"
    Module(_, _) => "Module"
    Unit => "Unit"
    Unbound(_) => "Unbound"
    Error(_) => "Error"
  }
}

///|
pub impl Renderable for @ast.Term with label(self) {
  match self {
    Int(n) => n.to_string()
    Var(name) => name
    Lam(param, _) => "\u{03BB}" + param
    App(_, _) => "App"
    Bop(op, _, _) => op.to_string()
    If(_, _, _) => "if"
    Module(defs, _) => {
      let names = defs.map(fn(d) { d.0 })
      "module [" + names.join(", ") + "]"
    }
    Unit => "()"
    Unbound(name) => "?" + name
    Error(msg) => "Error: " + msg
  }
}

///|
pub impl Renderable for @ast.Term with placeholder(self) {
  match self {
    Int(_) => "0"
    Var(_) => "x"
    Lam(_, _) => "\u{03BB}x. x"
    App(_, _) => "f x"
    Bop(Plus, _, _) => "0 + 0"
    Bop(Minus, _, _) => "0 - 0"
    If(_, _, _) => "if 0 then 0 else 0"
    Module(_, _) => "let x = 0"
    Unit => "()"
    Unbound(_) => "x"
    Error(_) => "?"
  }
}

///|
pub impl Renderable for @ast.Term with unparse(self) {
  @ast.print_term(self)
}
