// Lambda semantic projection overlay.
//
// This package derives semantic facts from the current ProjNode + SourceMap.
// It does not own durable state and does not mutate the document; semantic
// actions must still lower to text/CRDT edits through the editor layer.

///|
pub struct SemanticProjection {
  annotations : Map[@core.NodeId, Array[@protocol.ViewAnnotation]]
  decorations : Array[@protocol.Decoration]
  diagnostics : Array[@protocol.Diagnostic]
} derive(Debug)

///|
pub fn SemanticProjection::empty() -> SemanticProjection {
  { annotations: {}, decorations: [], diagnostics: [] }
}

///|
pub impl ToJson for SemanticProjection with fn to_json(self) {
  let annotation_entries : Array[Json] = []
  for node_id, anns in self.annotations {
    let m : Map[String, Json] = {}
    m["node_id"] = node_id.to_json()
    m["annotations"] = Json::array(anns.map(fn(a) { a.to_json() }))
    annotation_entries.push(Json::object(m))
  }
  let m : Map[String, Json] = {}
  m["annotations"] = Json::array(annotation_entries)
  m["decorations"] = Json::array(self.decorations.map(fn(d) { d.to_json() }))
  m["diagnostics"] = Json::array(self.diagnostics.map(fn(d) { d.to_json() }))
  Json::object(m)
}

///|
pub fn build_semantic_projection(
  root : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
) -> SemanticProjection {
  build_semantic_projection_with_module_projection(root, source_map, None)
}

///|
pub fn build_semantic_projection_with_module_projection(
  root : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  module_projection : @lambda_proj.ModuleProjection?,
) -> SemanticProjection {
  let projection = SemanticProjection::empty()
  analyze_node(root, source_map, [], projection, module_projection)
  push_scope_failures(root, source_map, projection)
  projection
}

///|
/// Source the free-variable diagnostics from the lambda scope graph rather than
/// the projection's own environment walk (research note 2026-06-13 §6 Step 1).
/// Each unresolved reference (`resolution.decl == None`) is a witnessed
/// `ReachableFailure`; for today's lexical lambda language that failure is
/// genuinely reachable, so the squiggle now rests on the resolver of record
/// instead of a parallel `env.contains` check.
///
/// The scope graph is reconstructed from `root` via `from_proj_node(root)` — it
/// deliberately does NOT reuse the caller-supplied `module_projection`. Both the
/// registry and the diagnostic ranges derive from `root`, so deriving the
/// module projection from `root` too keeps resolution consistent with the tree
/// the squiggles land on; the caller's projection (which under incremental
/// editing is reconciled separately) could drift from `root` and mis-gate
/// definition visibility. The `module_projection` argument is consulted only by
/// the annotation/decoration walk, whose bound/free overlays deliberately remain
/// on the environment walk — §6 Step 1 regrounds the structured diagnostic only.
/// Incremental maintenance (avoiding this rebuild) is §6 Step 3, benchmark-gated.
fn push_scope_failures(
  root : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  projection : SemanticProjection,
) -> Unit {
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let module_projection = @lambda_proj.ModuleProjection::from_proj_node(root)
  let graph = @lambda_scope.build(module_projection, registry, source_map)
  for failure in @lambda_scope.failures(graph, source_map) {
    guard failure.location is Some(range) else { continue }
    projection.diagnostics.push(
      @protocol.Diagnostic(
        from=range.start,
        to=range.end,
        severity=@protocol.SevWarning,
        message="Free variable '" + failure.name + "'",
      ),
    )
  }
}

///|
fn analyze_node(
  node : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  env : Array[String],
  projection : SemanticProjection,
  module_projection : @lambda_proj.ModuleProjection?,
) -> Unit {
  match node.kind {
    @ast.Term::Module(defs, _) =>
      analyze_module(node, source_map, defs, env, projection, module_projection)
    @ast.Term::Lam(param, _) =>
      analyze_lambda(node, source_map, param, env, projection)
    @ast.Term::Var(name) | @ast.Term::Unbound(name) =>
      analyze_var(node, source_map, name, env, projection)
    @ast.Term::LetDef(_, _) =>
      for child in node.children {
        analyze_node(child, source_map, env, projection, None)
      }
    @ast.Term::App(_, _) | @ast.Term::Bop(_, _, _) =>
      for child in node.children {
        analyze_node(child, source_map, env, projection, None)
      }
    @ast.Term::If(_, _, _) =>
      for child in node.children {
        analyze_node(child, source_map, env, projection, None)
      }
    @ast.Term::Int(_)
    | @ast.Term::Unit
    | @ast.Term::Error(_)
    | @ast.Term::Hole(_) => ()
  }
}

///|
fn analyze_module(
  node : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  defs : Array[(@ast.VarName, @ast.Term)],
  env : Array[String],
  projection : SemanticProjection,
  module_projection : @lambda_proj.ModuleProjection?,
) -> Unit {
  let scoped = env.copy()
  for i, def in defs {
    let name = def.0
    let binder_id = if i < node.children.length() {
      node.children[i].id()
    } else {
      module_binding_node_id(module_projection, i).unwrap_or(node.id())
    }
    add_annotation(
      projection,
      binder_id,
      @protocol.ViewAnnotation(kind="semantic-binder", label="let " + name),
    )
    let binder_span = match
      source_map.get_token_span(binder_id, @lambda_proj.LET_DEF_NAME_ROLE) {
      Some(range) => Some(range)
      None =>
        source_map.get_token_span(node.id(), @lambda_proj.module_name_role(i))
    }
    match binder_span {
      Some(range) =>
        add_decoration(
          projection,
          range.start,
          range.end,
          "semantic-binder",
          name,
        )
      None => ()
    }
    if i < node.children.length() {
      analyze_node(node.children[i], source_map, scoped, projection, None)
    }
    scoped.push(name)
  }
  let body_index = defs.length()
  if body_index < node.children.length() {
    analyze_node(
      node.children[body_index],
      source_map,
      scoped,
      projection,
      None,
    )
  }
}

///|
fn module_binding_node_id(
  module_projection : @lambda_proj.ModuleProjection?,
  def_index : Int,
) -> @core.NodeId? {
  match module_projection {
    Some(fp) if def_index < fp.defs.length() => Some(fp.defs[def_index].3)
    _ => None
  }
}

///|
fn analyze_lambda(
  node : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  param : String,
  env : Array[String],
  projection : SemanticProjection,
) -> Unit {
  add_annotation(
    projection,
    node.id(),
    @protocol.ViewAnnotation(kind="semantic-binder", label="(" + param + ") =>"),
  )
  match source_map.get_token_span(node.id(), @lambda_proj.PARAM_ROLE) {
    Some(range) =>
      add_decoration(
        projection,
        range.start,
        range.end,
        "semantic-binder",
        param,
      )
    None => ()
  }
  let scoped = env.copy()
  scoped.push(param)
  if node.children.length() > 0 {
    analyze_node(node.children[0], source_map, scoped, projection, None)
  }
}

///|
fn analyze_var(
  node : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  name : String,
  env : Array[String],
  projection : SemanticProjection,
) -> Unit {
  if env.contains(name) {
    add_annotation(
      projection,
      node.id(),
      @protocol.ViewAnnotation(kind="semantic-ref", label="bound " + name),
    )
    add_node_decoration(
      projection,
      source_map,
      node.id(),
      "semantic-bound",
      name,
    )
  } else {
    add_annotation(
      projection,
      node.id(),
      @protocol.ViewAnnotation(
        kind="semantic-ref",
        label="free " + name,
        severity="warning",
      ),
    )
    add_node_decoration(
      projection,
      source_map,
      node.id(),
      "semantic-free",
      name,
    )
  }
}

///|
fn add_node_decoration(
  projection : SemanticProjection,
  source_map : @core.SourceMap,
  node_id : @core.NodeId,
  css_class : String,
  data : String,
) -> Unit {
  match source_map.get_range(node_id) {
    Some(range) =>
      add_decoration(projection, range.start, range.end, css_class, data)
    None => ()
  }
}

///|
fn add_decoration(
  projection : SemanticProjection,
  from : Int,
  to : Int,
  css_class : String,
  data : String,
) -> Unit {
  if to > from {
    projection.decorations.push(
      @protocol.Decoration(from~, to~, css_class~, data~),
    )
  }
}

///|
fn add_annotation(
  projection : SemanticProjection,
  node_id : @core.NodeId,
  annotation : @protocol.ViewAnnotation,
) -> Unit {
  match projection.annotations.get(node_id) {
    Some(existing) => existing.push(annotation)
    None => projection.annotations[node_id] = [annotation]
  }
}
