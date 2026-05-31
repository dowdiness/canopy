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
  build_semantic_projection_with_flat_proj(root, source_map, None)
}

///|
pub fn build_semantic_projection_with_flat_proj(
  root : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  flat_proj : @lambda_proj.FlatProj?,
) -> SemanticProjection {
  let projection = SemanticProjection::empty()
  analyze_node(root, source_map, [], projection, flat_proj)
  projection
}

///|
fn analyze_node(
  node : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
  env : Array[String],
  projection : SemanticProjection,
  flat_proj : @lambda_proj.FlatProj?,
) -> Unit {
  match node.kind {
    @ast.Term::Module(defs, _) =>
      analyze_module(node, source_map, defs, env, projection, flat_proj)
    @ast.Term::Lam(param, _) =>
      analyze_lambda(node, source_map, param, env, projection)
    @ast.Term::Var(name) | @ast.Term::Unbound(name) =>
      analyze_var(node, source_map, name, env, projection)
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
  flat_proj : @lambda_proj.FlatProj?,
) -> Unit {
  let scoped = env.copy()
  for i, def in defs {
    let name = def.0
    let binder_id = module_binding_node_id(flat_proj, i).unwrap_or(node.id())
    add_annotation(
      projection,
      binder_id,
      @protocol.ViewAnnotation(kind="semantic-binder", label="let " + name),
    )
    match
      source_map.get_token_span(node.id(), @lambda_proj.module_name_role(i)) {
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
  flat_proj : @lambda_proj.FlatProj?,
  def_index : Int,
) -> @core.NodeId? {
  match flat_proj {
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
    @protocol.ViewAnnotation(kind="semantic-binder", label="λ" + param),
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
    match source_map.get_range(node.id()) {
      Some(range) =>
        projection.diagnostics.push(
          @protocol.Diagnostic(
            from=range.start,
            to=range.end,
            severity=@protocol.SevWarning,
            message="Free variable '" + name + "'",
          ),
        )
      None => ()
    }
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
