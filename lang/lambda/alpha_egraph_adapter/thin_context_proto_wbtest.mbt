///|
// Test-only prototype substrate for issue #681's thinning/lifting evaluation.
//
// The wrapper keeps binder context metadata outside the generic egraph engine:
// raw `@egraph.Id` values are only unioned after `union_at` has interpreted
// both sides in a common `LambdaContext`. This white-box prototype intentionally
// exposes no public API; it is evidence for the design note, not production
// optimizer surface.
priv struct LambdaContext {
  binders : Array[@alpha.BinderId]
}

///|
priv struct Thin {
  map : Array[Int?]
}

///|
priv struct ContextualId {
  ctx : LambdaContext
  id : @egraph.Id
}

///|
priv struct ThinEGraph {
  eg : @egraph.AnalyzedEGraph[AlphaLang, EvalState]
  entries : Array[ContextualId]
}

///|
priv struct ContextSearchResult {
  candidates : Int
  matches : Array[ContextualId]
}

///|
fn thin_egraph() -> ThinEGraph {
  { eg: @egraph.AnalyzedEGraph::AnalyzedEGraph(eval_analysis()), entries: [] }
}

///|
fn canonical_binder_id(position : Int) -> @alpha.BinderId {
  @alpha.BinderId(position)
}

///|
fn canonical_binder(binder : @alpha.Binder, position : Int) -> @alpha.Binder {
  {
    id: canonical_binder_id(position),
    hint: binder.hint,
    origin: @alpha.BinderOrigin::Generated(position),
  }
}

///|
fn LambdaContext::extend(
  self : LambdaContext,
  binder : @alpha.BinderId,
) -> LambdaContext {
  let binders = self.binders.copy()
  binders.push(binder)
  { binders, }
}

///|
fn LambdaContext::position(
  self : LambdaContext,
  binder : @alpha.BinderId,
) -> Int? {
  for i, candidate in self.binders; found = None {
    match found {
      Some(_) => continue found
      None => if candidate == binder { continue Some(i) } else { continue None }
    }
  } nobreak {
    found
  }
}

///|
fn normalize_ref(
  ctx : LambdaContext,
  alpha_ref : @alpha.AlphaRef,
) -> @alpha.AlphaRef {
  match alpha_ref {
    Bound(id) =>
      match ctx.position(id) {
        Some(position) => Bound(canonical_binder_id(position))
        None => Bound(id)
      }
    Free(_) => alpha_ref
  }
}

///|
fn normalize_defs(
  ctx : LambdaContext,
  defs : Array[(@alpha.Binder, @alpha.AlphaTerm)],
) -> (LambdaContext, Array[(@alpha.Binder, @alpha.AlphaTerm)]) {
  for def in defs; state = (ctx, []) {
    let (current_ctx, normalized_defs) : (
      LambdaContext,
      Array[(@alpha.Binder, @alpha.AlphaTerm)],
    ) = state
    let (binder, init) = def
    let normalized_init = normalize_term(current_ctx, init)
    let position = current_ctx.binders.length()
    let normalized_binder = canonical_binder(binder, position)
    normalized_defs.push((normalized_binder, normalized_init))
    continue (current_ctx.extend(binder.id), normalized_defs)
  } nobreak {
    state
  }
}

///|
fn normalize_term(
  ctx : LambdaContext,
  term : @alpha.AlphaTerm,
) -> @alpha.AlphaTerm {
  match term {
    Int(_) | Unit | Error(_) | Hole(_) => term
    Var(alpha_ref) => @alpha.AlphaTerm::Var(normalize_ref(ctx, alpha_ref))
    Lam(binder, body) => {
      let position = ctx.binders.length()
      let normalized_binder = canonical_binder(binder, position)
      @alpha.AlphaTerm::Lam(
        normalized_binder,
        normalize_term(ctx.extend(binder.id), body),
      )
    }
    App(func, arg) =>
      @alpha.AlphaTerm::App(normalize_term(ctx, func), normalize_term(ctx, arg))
    Bop(op, lhs, rhs) =>
      @alpha.AlphaTerm::Bop(
        op,
        normalize_term(ctx, lhs),
        normalize_term(ctx, rhs),
      )
    If(cond, then_, else_) =>
      @alpha.AlphaTerm::If(
        normalize_term(ctx, cond),
        normalize_term(ctx, then_),
        normalize_term(ctx, else_),
      )
    LetDef(binder, init) => {
      let normalized_binder = canonical_binder(binder, ctx.binders.length())
      @alpha.AlphaTerm::LetDef(normalized_binder, normalize_term(ctx, init))
    }
    Module(defs, body) => {
      let (body_ctx, normalized_defs) = normalize_defs(ctx, defs)
      @alpha.AlphaTerm::Module(normalized_defs, normalize_term(body_ctx, body))
    }
  }
}

///|
fn Thin::valid(
  self : Thin,
  source : LambdaContext,
  target : LambdaContext,
) -> Bool {
  guard self.map.length() == target.binders.length() else { return false }
  let seen : Map[Int, Unit] = {}
  for entry in self.map {
    match entry {
      None => ()
      Some(index) => {
        if index < 0 || index >= source.binders.length() || seen.contains(index) {
          return false
        }
        seen[index] = ()
      }
    }
  }
  true
}

///|
fn context_thin(source : LambdaContext, target : LambdaContext) -> Thin? {
  guard source.binders.length() <= target.binders.length() else { return None }
  Some({
    map: target.binders.mapi(fn(i, _) {
      if i < source.binders.length() {
        Some(i)
      } else {
        None
      }
    }),
  })
}

///|
fn ThinEGraph::add_at(
  self : ThinEGraph,
  ctx : LambdaContext,
  term : @alpha.AlphaTerm,
) -> ContextualId {
  let normalized = normalize_term(ctx, term)
  let entry = { ctx, id: alpha_term_add(self.eg, normalized) }
  self.entries.push(entry)
  entry
}

///|
fn ThinEGraph::lift_to(
  self : ThinEGraph,
  target : LambdaContext,
  value : ContextualId,
  thin : Thin,
) -> ContextualId? {
  if thin.valid(value.ctx, target) {
    Some({ ctx: target, id: self.eg.find(value.id) })
  } else {
    None
  }
}

///|
fn ThinEGraph::union_at(
  self : ThinEGraph,
  target : LambdaContext,
  left : ContextualId,
  right : ContextualId,
) -> Bool {
  match (context_thin(left.ctx, target), context_thin(right.ctx, target)) {
    (Some(left_thin), Some(right_thin)) =>
      match
        (
          self.lift_to(target, left, left_thin),
          self.lift_to(target, right, right_thin),
        ) {
        (Some(left_lifted), Some(right_lifted)) => {
          self.eg.union(left_lifted.id, right_lifted.id) |> ignore
          true
        }
        _ => false
      }
    _ => false
  }
}

///|
fn ThinEGraph::extract_at(
  self : ThinEGraph,
  value : ContextualId,
) -> @alpha.AlphaTerm {
  let (_, rec) = self.eg.extract(value.id, @egraph.ast_size())
  rec_expr_to_alpha(rec)
}

///|
fn ThinEGraph::search_at(
  self : ThinEGraph,
  target : LambdaContext,
  pattern : @alpha.AlphaTerm,
) -> ContextSearchResult {
  let pattern_id = alpha_term_add(self.eg, normalize_term(target, pattern))
  let matches : Array[ContextualId] = []
  let candidates = for entry in self.entries; count = 0 {
    match context_thin(entry.ctx, target) {
      None => continue count
      Some(thin) => {
        match self.lift_to(target, entry, thin) {
          Some(lifted) =>
            if self.eg.find(lifted.id) == self.eg.find(pattern_id) {
              matches.push(entry)
            }
          None => ()
        }
        continue count + 1
      }
    }
  } nobreak {
    count
  }
  { candidates, matches }
}

///|
fn proto_binder(id : Int, hint : String) -> @alpha.Binder {
  { id: @alpha.BinderId(id), hint, origin: @alpha.BinderOrigin::Generated(id) }
}

///|
fn proto_bound(id : @alpha.BinderId) -> @alpha.AlphaTerm {
  @alpha.AlphaTerm::Var(Bound(id))
}

///|
fn proto_free(name : String) -> @alpha.AlphaTerm {
  @alpha.AlphaTerm::Var(Free({ name, origin: @alpha.FreeOrigin::SourceVar }))
}

///|
test "thin context prototype: open alpha bodies union only after context lift" {
  let left_binder = proto_binder(10, "x")
  let right_binder = proto_binder(20, "y")
  let raw = @egraph.AnalyzedEGraph::AnalyzedEGraph(eval_analysis())
  let raw_left = alpha_term_add(raw, proto_bound(left_binder.id))
  let raw_right = alpha_term_add(raw, proto_bound(right_binder.id))
  raw.rebuild()
  assert_true(raw.find(raw_left) != raw.find(raw_right))

  let proto = thin_egraph()
  let left_ctx : LambdaContext = { binders: [left_binder.id] }
  let right_ctx : LambdaContext = { binders: [right_binder.id] }
  let target_ctx : LambdaContext = { binders: [@alpha.BinderId(0)] }
  let left = proto.add_at(left_ctx, proto_bound(left_binder.id))
  let right = proto.add_at(right_ctx, proto_bound(right_binder.id))
  assert_true(proto.union_at(target_ctx, left, right))
  proto.eg.rebuild()
  assert_true(proto.eg.find(left.id) == proto.eg.find(right.id))
  guard proto.extract_at({ ctx: target_ctx, id: left.id })
    is @alpha.AlphaTerm::Var(Bound(@alpha.BinderId(0))) else {
    fail("expected canonical one-binder body")
  }
}

///|
test "thin context prototype: contextual search bounds thinning candidates" {
  let left_binder = proto_binder(10, "x")
  let right_binder = proto_binder(20, "y")
  let free_ctx_binder = proto_binder(30, "z_scope")
  let deep_outer = proto_binder(40, "outer")
  let deep_inner = proto_binder(41, "inner")
  let proto = thin_egraph()
  let target_ctx : LambdaContext = { binders: [@alpha.BinderId(0)] }
  ignore(
    proto.add_at({ binders: [left_binder.id] }, proto_bound(left_binder.id)),
  )
  ignore(
    proto.add_at({ binders: [right_binder.id] }, proto_bound(right_binder.id)),
  )
  ignore(proto.add_at({ binders: [free_ctx_binder.id] }, proto_free("z")))
  ignore(
    proto.add_at(
      { binders: [deep_outer.id, deep_inner.id] },
      proto_bound(deep_inner.id),
    ),
  )
  let result = proto.search_at(target_ctx, proto_bound(@alpha.BinderId(0)))
  inspect(proto.entries.length(), content="4")
  inspect(result.candidates, content="3")
  inspect(result.matches.length(), content="2")
}

///|
test "thin context prototype: renamed capture fixtures stay alpha-equivalent" {
  let (left_proj, left_graph) = parse_fixture("((x) => (y) => x) y")
  let (right_proj, right_graph) = parse_fixture("((a) => (b) => a) y")
  let left = optimize_alpha(@alpha.lower_root(left_proj, left_graph))
  let right = optimize_alpha(@alpha.lower_root(right_proj, right_graph))
  let expected = @alpha.AlphaTerm::Lam(proto_binder(99, "y1"), proto_free("y"))
  assert_true(@alpha.alpha_eq(left, expected))
  assert_true(@alpha.alpha_eq(right, expected))
  assert_true(@alpha.alpha_key(left) == @alpha.alpha_key(right))
  guard @alpha.reify(left, Source)
    is @ast.Term::Lam(left_param, @ast.Term::Var(left_body)) else {
    fail("expected left fixture to reify as lambda")
  }
  guard @alpha.reify(right, Source)
    is @ast.Term::Lam(right_param, @ast.Term::Var(right_body)) else {
    fail("expected right fixture to reify as lambda")
  }
  if left_param == left_body || right_param == right_body {
    fail("free y was captured by the result binder")
  }
  inspect(left_body, content="y")
  inspect(right_body, content="y")
}
