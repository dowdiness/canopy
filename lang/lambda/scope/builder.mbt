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
///
/// `node_cutoffs` is transient pass-2 state (never stored in the graph): for
/// each node it records the sequential cutoff of every enclosing module scope
/// — a `ModuleDef(def_index)` in scope `s` is visible to the node only if
/// `def_index < node_cutoffs[node][s]`. Lambda scopes never appear (they hold
/// no `ModuleDef`). This generalises the former single-`Int` cutoff so nested
/// blocks each carry their own sequential position independently.
priv struct Builder {
  scopes : Array[Scope]
  decls : Array[Decl]
  refs : Array[Ref]
  node_scope : Map[@core.NodeId, ScopeId]
  node_cutoffs : Map[@core.NodeId, Map[ScopeId, Int]]
}

///|
fn Builder::new() -> Builder {
  { scopes: [], decls: [], refs: [], node_scope: {}, node_cutoffs: {} }
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
/// Pass 2: scopes, decls, and per-node scope+cutoff membership.
///
/// - The root module scope holds the flat top-level `ModuleDef` decls (one per
///   `module_projection.defs`, binder id preserved from the projection).
/// - Each `Lam` node opens a child `LamParam` scope.
/// - Each NESTED `Module` node (a block expression) opens a child scope holding
///   its own block-local `ModuleDef` decls — this is what makes the graph an
///   exact resolver for blocks, matching the semantic env-walk.
///
/// Within any module scope, child `i` (definition `i`'s initialiser) sees defs
/// `[0, i)` and the body (`i == def_count`) sees all defs; that per-child
/// cutoff is recorded against the scope in `node_cutoffs`, accumulating the
/// cutoffs of all enclosing module scopes so each gates visibility independently.
fn Builder::pass2(
  self : Builder,
  module_projection : @lambda_proj.ModuleProjection,
  root : @core.ProjNode[@ast.Term],
) -> Unit {
  // Single self-recursive walker (local mutual recursion is unavailable in
  // current MoonBit, so the module-children descent is inlined in both the
  // nested-`Module` arm and the root setup below).
  fn walk(
    node : @core.ProjNode[@ast.Term],
    current : ScopeId,
    cutoffs : Map[ScopeId, Int],
  ) -> Unit {
    self.node_scope[node.id()] = current
    self.node_cutoffs[node.id()] = cutoffs
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
          walk(child, lam_scope, cutoffs)
        }
      }
      @ast.Term::Module(defs, _) => {
        let mod_scope = self.add_scope(Some(current))
        for i, def in defs {
          let _ = self.add_decl(
            mod_scope,
            node.children[i].id(),
            def.0,
            ModuleDef(def_index=i),
          )
        }
        let def_count = defs.length()
        for i, child in node.children {
          let scoped = cutoffs.copy()
          scoped[mod_scope] = if i < def_count { i } else { def_count }
          walk(child, mod_scope, scoped)
        }
      }
      _ =>
        for child in node.children {
          walk(child, current, cutoffs)
        }
    }
  }

  let root_scope = self.add_scope(None)
  for i, def in module_projection.defs {
    let (name, _init, _start, binder_id) = def
    let _ = self.add_decl(root_scope, binder_id, name, ModuleDef(def_index=i))
  }
  match root.kind {
    // Top-level module: its scope and decls are installed above, so descend its
    // children directly (not through the `Module` arm, which would open a
    // second scope and re-install the defs from the wrong binder ids).
    @ast.Term::Module(_, _) => {
      self.node_scope[root.id()] = root_scope
      self.node_cutoffs[root.id()] = {}
      let root_def_count = module_projection.defs.length()
      for i, child in root.children {
        let scoped : Map[ScopeId, Int] = {}
        scoped[root_scope] = if i < root_def_count { i } else { root_def_count }
        walk(child, root_scope, scoped)
      }
    }
    // Bare lambda / expression program: `module_projection.defs` is empty, so
    // `root_scope` holds no `ModuleDef`. Dispatch through `walk` so the root's
    // own binder (a `Lam` param) is installed.
    _ => {
      let scoped : Map[ScopeId, Int] = {}
      scoped[root_scope] = 0
      walk(root, root_scope, scoped)
    }
  }
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
/// Resolve `name` from `start_scope` upward. A `ModuleDef` decl in scope `sid`
/// is visible only if `def_index < cutoffs[sid]` (the sequential rule, applied
/// per module scope so nested blocks gate independently); `LamParam` decls are
/// always visible. Records scopes visited that did not contain the name
/// (negative observation).
///
/// Invariant: every module scope on the parent chain from `start_scope` to the
/// root was entered during pass 2's walk for this reference, so it is present
/// in `cutoffs`; `cutoffs.get(sid).unwrap()` therefore asserts that invariant
/// (a missing entry is a structural defect and a loud abort is correct), and is
/// only ever consulted for `ModuleDef` decls — lambda scopes are never looked up.
fn Builder::resolve(
  self : Builder,
  name : String,
  start_scope : ScopeId,
  cutoffs : Map[ScopeId, Int],
) -> Resolution {
  let visited : Array[ScopeId] = []
  let mut cur : ScopeId? = Some(start_scope)
  while cur is Some(sid) {
    let ScopeId(si) = sid
    let scope = self.scopes[si]
    // later decls win within a scope (shadowing), so search in reverse and take
    // the first match; module-scope decls respect the per-scope cutoff.
    let hit = scope.decl_ids
      .rev_iter()
      .find_first(fn(did) {
        let DeclId(di) = did
        let decl = self.decls[di]
        decl.name == name &&
        (match decl.kind {
          ModuleDef(def_index~) => def_index < cutoffs.get(sid).unwrap()
          LamParam(_) => true
        })
      })
    guard hit is None else { return { decl: hit, visited_scopes: visited } }
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
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
) -> Unit {
  for _id, node in registry {
    let name = match node.kind {
      @ast.Term::Var(x) => Some(x)
      @ast.Term::Unbound(x) => Some(x)
      _ => None
    }
    guard name is Some(n) else { continue }
    let scope = self.node_scope.get(node.id()).unwrap()
    let cutoffs = self.node_cutoffs.get(node.id()).unwrap()
    let resolution = self.resolve(n, scope, cutoffs)
    self.add_ref(scope, node.id(), n, resolution)
  }
}

///|
/// Build the scope graph (Pass 2 then Pass 3).
///
/// `source_map` is the graph's companion coordinate input retained on the public
/// constructor (callers already hold it and `failures()` consumes it for
/// reference locations). Resolution itself is now purely structural — cutoffs
/// come from tree position recorded in pass 2 — so it is not threaded into the
/// passes.
pub fn build(
  module_projection : @lambda_proj.ModuleProjection,
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  source_map : @core.SourceMap,
) -> ScopeGraph {
  let _ = source_map
  let b = Builder::new()
  let root = root_node(registry)
  b.pass2(module_projection, root)
  b.pass3(registry)
  { scopes: b.scopes, decls: b.decls, refs: b.refs, module_node_id: root.id() }
}
