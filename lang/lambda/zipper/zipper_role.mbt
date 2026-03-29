///|
pub(all) enum PositionRole {
  Root
  FunctionPosition
  ArgumentPosition
  BinderBody(@ast.VarName)
  Condition
  ThenBranch
  ElseBranch
  OperandLeft(@ast.Bop)
  OperandRight(@ast.Bop)
  LetDefinition(@ast.VarName)
  LetBody
} derive(Show)

///|
pub fn available_actions(z : Zipper) -> Array[EditAction] {
  let focus = z.focus
  let actions : Array[EditAction] = []
  match focus {
    @ast.Hole(_) => () // Hole is already a placeholder — Delete is a no-op
    _ => actions.push(Delete)
  }
  actions.push(WrapLam("x"))
  actions.push(WrapApp)
  actions.push(WrapIf)
  actions.push(WrapBop(@ast.Plus))
  actions.push(WrapBop(@ast.Minus))
  let n = children_count(focus)
  for i in 0..<n {
    actions.push(Unwrap(i))
  }
  // SwapChildren: Bop and If only (backend only supports these)
  match focus {
    @ast.Bop(_, _, _) | @ast.If(_, _, _) => actions.push(SwapChildren)
    _ => ()
  }
  // ChangeOperator: Bop focus only
  match focus {
    @ast.Bop(@ast.Plus, _, _) => actions.push(ChangeOperator(@ast.Minus))
    @ast.Bop(@ast.Minus, _, _) => actions.push(ChangeOperator(@ast.Plus))
    _ => ()
  }
  actions
}

///|
pub fn position_role(z : Zipper) -> PositionRole {
  match z.path {
    Empty => Root
    More(ctx, tail=_) =>
      match ctx {
        CtxLamBody(param) => BinderBody(param)
        CtxAppFunc(_) => FunctionPosition
        CtxAppArg(_) => ArgumentPosition
        CtxBopLeft(op, _) => OperandLeft(op)
        CtxBopRight(op, _) => OperandRight(op)
        CtxIfCond(_, _) => Condition
        CtxIfThen(_, _) => ThenBranch
        CtxIfElse(_, _) => ElseBranch
        CtxModuleDef(_, name, _, _) => LetDefinition(name)
        CtxModuleBody(_) => LetBody
      }
  }
}
