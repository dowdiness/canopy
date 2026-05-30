///|
/// Pass 1: build a `NodeId -> parent NodeId` map by walking the registry's
/// ProjNode tree. Each node appears in exactly one parent's `children`
/// array, so the map is acyclic by construction. O(N).
/// Internal Pass-1 helper (used by `root_node` + whitebox tests) — not part of
/// the package's public surface.
fn build_parent_map(
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
) -> Map[@core.NodeId, @core.NodeId] {
  let parents : Map[@core.NodeId, @core.NodeId] = {}
  for _id, node in registry {
    for child in node.children {
      parents[child.id()] = node.id()
    }
  }
  parents
}

///|
/// Mutable builder state accumulated across passes.
priv struct Builder {
  scopes : Array[Scope]
  decls : Array[Decl]
  refs : Array[Ref]
  node_scope : Map[@core.NodeId, ScopeId]
}

///|
fn Builder::new() -> Builder {
  { scopes: [], decls: [], refs: [], node_scope: {} }
}

///|
fn Builder::add_scope(self : Builder, parent : ScopeId?) -> ScopeId {
  let id = ScopeId(self.scopes.length())
  self.scopes.push({ id, parent, decl_ids: [], ref_ids: [] })
  id
}

///|
fn Builder::add_decl(
  self : Builder,
  scope : ScopeId,
  node_id : @core.NodeId,
  name : String,
  kind : DeclKind,
) -> DeclId {
  let ScopeId(si) = scope
  let id = DeclId(self.decls.length())
  self.decls.push({ id, node_id, name, scope, kind })
  self.scopes[si].decl_ids.push(id)
  id
}

///|
/// The registry's root is the node that is no other node's child.
fn root_node(
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
) -> @core.ProjNode[@ast.Term] {
  let parents = build_parent_map(registry)
  registry
  .values()
  .find_first(fn(node) { parents.get(node.id()) is None })
  .unwrap()
}

///|
/// Pass 2: root module scope, ModuleDef decls (one per flat def), and a child
/// LamParam scope per Lam node. Records node→scope membership.
fn Builder::pass2(
  self : Builder,
  flat_proj : @lambda_proj.FlatProj,
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
) -> Unit {
  let root_scope = self.add_scope(None)
  for i, def in flat_proj.defs {
    let (name, _init, _start, binder_id) = def
    let _ = self.add_decl(root_scope, binder_id, name, ModuleDef(def_index=i))
  }
  fn walk(node : @core.ProjNode[@ast.Term], current : ScopeId) -> Unit {
    self.node_scope[node.id()] = current
    match node.kind {
      @ast.Term::Lam(param, _) => {
        let lam_scope = self.add_scope(Some(current))
        let _ = self.add_decl(
          lam_scope,
          node.id(),
          param,
          LamParam(lam_id=node.id()),
        )
        for child in node.children {
          walk(child, lam_scope)
        }
      }
      _ =>
        for child in node.children {
          walk(child, current)
        }
    }
  }

  walk(root_node(registry), root_scope)
}

///|
fn Builder::add_ref(
  self : Builder,
  scope : ScopeId,
  node_id : @core.NodeId,
  name : String,
  resolution : Resolution,
) -> Unit {
  let ScopeId(si) = scope
  let id = RefId(self.refs.length())
  self.refs.push({ id, node_id, name, scope, resolution })
  self.scopes[si].ref_ids.push(id)
}

///|
/// Which flat-def index a node sits within, by source position; returns the
/// def count (body sentinel) when the node is in the module body. This is now
/// the sole implementation of def-range containment for the lambda language.
fn containing_def_index(
  flat_proj : @lambda_proj.FlatProj,
  source_map : @core.SourceMap,
  node_id : @core.NodeId,
) -> Int {
  guard source_map.get_range(node_id) is Some(r) else {
    return flat_proj.defs.length()
  }
  let pos = r.start
  flat_proj.defs
  .search_by(fn(def) {
    let (_n, init, _s, _id) = def
    source_map.get_range(init.id()) is Some(dr) &&
    pos >= dr.start &&
    pos < dr.end
  })
  .unwrap_or(flat_proj.defs.length())
}

///|
/// Resolve `name` from `start_scope` upward. ModuleDef decls are visible only
/// if def_index < cutoff (sequential rule). Records scopes visited that did
/// not contain the name (negative observation).
fn Builder::resolve(
  self : Builder,
  name : String,
  start_scope : ScopeId,
  cutoff : Int,
) -> Resolution {
  let visited : Array[ScopeId] = []
  let mut cur : ScopeId? = Some(start_scope)
  while cur is Some(sid) {
    let ScopeId(si) = sid
    let scope = self.scopes[si]
    let mut hit : DeclId? = None
    // later decls win within a scope (shadowing); module scope respects cutoff.
    for did in scope.decl_ids {
      let DeclId(di) = did
      let decl = self.decls[di]
      if decl.name == name {
        match decl.kind {
          ModuleDef(def_index~) => if def_index < cutoff { hit = Some(did) }
          LamParam(_) => hit = Some(did)
        }
      }
    }
    if hit is Some(_) {
      return { decl: hit, visited_scopes: visited }
    }
    visited.push(sid)
    cur = scope.parent
  }
  { decl: None, visited_scopes: visited }
}

///|
/// Pass 3: emit a Ref for each Var/Unbound node and resolve it.
/// Invariant: pass2 walks the registry's root tree and records `node_scope`
/// for every node, and the registry itself is that same tree — so every
/// Var/Unbound node here has a recorded scope. `node_scope.get(..).unwrap()`
/// therefore asserts that invariant: a missing scope means the registry held a
/// node not reachable from root (a structural defect), and a loud abort is
/// correct — silently defaulting to the root scope would mis-resolve it.
fn Builder::pass3(
  self : Builder,
  flat_proj : @lambda_proj.FlatProj,
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  source_map : @core.SourceMap,
) -> Unit {
  for _id, node in registry {
    let name = match node.kind {
      @ast.Term::Var(x) => Some(x)
      @ast.Term::Unbound(x) => Some(x)
      _ => None
    }
    guard name is Some(n) else { continue }
    let scope = self.node_scope.get(node.id()).unwrap()
    let cutoff = containing_def_index(flat_proj, source_map, node.id())
    let resolution = self.resolve(n, scope, cutoff)
    self.add_ref(scope, node.id(), n, resolution)
  }
}

///|
/// Build the scope graph (Pass 2 then Pass 3).
pub fn build(
  flat_proj : @lambda_proj.FlatProj,
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  source_map : @core.SourceMap,
) -> ScopeGraph {
  let b = Builder::new()
  b.pass2(flat_proj, registry)
  b.pass3(flat_proj, registry, source_map)
  { scopes: b.scopes, decls: b.decls, refs: b.refs }
}
