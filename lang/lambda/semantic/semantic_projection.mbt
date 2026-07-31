// Lambda semantic projection overlay.
//
// This package derives semantic facts from the current ProjNode + SourceMap.
// It does not own durable state and does not mutate the document; semantic
// actions must still lower to text/CRDT edits through the editor layer.

///|
pub struct SemanticProjection {
  annotations : Map[@core.NodeId, Array[@protocol.ViewAnnotation]]
  decorations : Array[@protocol.Decoration]
} derive(Debug)

///|
pub fn SemanticProjection::empty() -> SemanticProjection {
  { annotations: Map([]), decorations: [] }
}

///|
pub impl ToJson for SemanticProjection with fn to_json(self) {
  let annotation_entries : Array[Json] = []
  for node_id, anns in self.annotations {
    let m : Map[String, Json] = Map([])
    m["node_id"] = node_id.to_json()
    m["annotations"] = Json::array(anns.map(fn(a) { a.to_json() }))
    annotation_entries.push(Json::object(m))
  }
  let m : Map[String, Json] = Map([])
  m["annotations"] = Json::array(annotation_entries)
  m["decorations"] = Json::array(self.decorations.map(fn(d) { d.to_json() }))
  Json::object(m)
}

///|
/// Failures at the Lambda-to-neutral diagnostic conversion boundary.
pub(all) suberror SemanticDiagnosticError {
  InvalidSourceRange(Int, Int, Int)
  InvalidUtf16Boundary(Int, Int)
} derive(Eq, Debug)

///|
pub fn build_semantic_projection(
  root : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
) -> SemanticProjection {
  let projection = SemanticProjection::empty()
  analyze_node(root, source_map, [], projection)
  projection
}

///|
/// Convert one producer-native range after validating it against the exact
/// source snapshot. The returned range is half-open UTF-16.
fn semantic_text_range(
  source : String,
  range : @loomcore.Range,
) -> @loomcore.TextRange raise SemanticDiagnosticError {
  let source_length = source.length()
  if range.start < 0 || range.end < range.start || range.end > source_length {
    raise InvalidSourceRange(range.start, range.end, source_length)
  }
  guard source.get_view(start=range.start, end=range.end) is Some(_) else {
    raise InvalidUtf16Boundary(range.start, range.end)
  }
  @loomcore.TextRange::from_offsets(range.start, range.end) catch {
    _ => raise InvalidSourceRange(range.start, range.end, source_length)
  }
}

///|
fn semantic_label(
  source_id : @loomcore.SourceId,
  source : String,
  range : @loomcore.Range,
  style : @loomcore.LabelStyle,
  message : String,
) -> @loomcore.DiagnosticLabel raise SemanticDiagnosticError {
  @loomcore.DiagnosticLabel::DiagnosticLabel(
    style,
    @loomcore.SourceSpan::SourceSpan(
      source_id,
      semantic_text_range(source, range),
    ),
    Some(message),
  )
}

///|
/// Project the existing witnessed scope failures into Loom's neutral model.
/// Source text is used only for boundary validation and is never stored in the
/// returned diagnostics.
pub fn build_semantic_diagnostics(
  source_id : @loomcore.SourceId,
  source : String,
  root : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
) -> @loomcore.DiagnosticSet raise SemanticDiagnosticError {
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
  @core.collect_registry(root, registry)
  let graph = @lambda_scope.build(registry, source_map)
  let diagnostics = @loomcore.DiagnosticSet::empty()
  for failure in @lambda_scope.failures(graph, source_map) {
    guard failure.location is Some(range) else { continue }
    let labels = [
      semantic_label(
        source_id,
        source,
        range,
        @loomcore.LabelStyle::Primary,
        "unresolved identifier",
      ),
    ]
    let notes : Array[String] = []
    failure.witness.each(scope => {
      match @lambda_scope.scope_span(graph, scope, source_map) {
        Some(scope_range) =>
          labels.push(
            semantic_label(
              source_id,
              source,
              scope_range,
              @loomcore.LabelStyle::Secondary,
              "searched lexical scope",
            ),
          )
        None => notes.push("searched lexical scope without source span")
      }
    })
    diagnostics.push(
      @loomcore.Diagnostic::Diagnostic(
        source=@loomcore.DiagnosticSource::DiagnosticSource("lambda.semantic"),
        // Imported enum variants are read-only; `all()` is the public value factory.
        severity=@loomcore.DiagnosticSeverity::all()[1],
        message="Free variable '" + failure.name + "'",
        code=Some(
          @loomcore.DiagnosticCode::DiagnosticCode(
            "lambda.unresolved_reference",
          ),
        ),
        labels~,
        notes~,
      ),
    )
  }
  diagnostics
}

///|
fn analyze_node(
  node : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  env : Array[String],
  projection : SemanticProjection,
) -> Unit {
  match node.kind {
    @ast.Term::Module(defs, _) =>
      analyze_module(node, source_map, defs, env, projection)
    @ast.Term::Lam(param, _) =>
      analyze_lambda(node, source_map, param, env, projection)
    @ast.Term::Var(name) | @ast.Term::Unbound(name) =>
      analyze_var(node, source_map, name, env, projection)
    @ast.Term::LetDef(_, _) =>
      for child in node.children {
        analyze_node(child, source_map, env, projection)
      }
    @ast.Term::App(_, _) | @ast.Term::Bop(_, _, _) =>
      for child in node.children {
        analyze_node(child, source_map, env, projection)
      }
    @ast.Term::If(_, _, _) =>
      for child in node.children {
        analyze_node(child, source_map, env, projection)
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
) -> Unit {
  let scoped = env.copy()
  for i, def in defs {
    let name = def.0
    let binder_id = if i < node.children.length() {
      node.children[i].id()
    } else {
      node.id()
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
      analyze_node(node.children[i], source_map, scoped, projection)
    }
    scoped.push(name)
  }
  let body_index = defs.length()
  if body_index < node.children.length() {
    analyze_node(node.children[body_index], source_map, scoped, projection)
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
    analyze_node(node.children[0], source_map, scoped, projection)
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
