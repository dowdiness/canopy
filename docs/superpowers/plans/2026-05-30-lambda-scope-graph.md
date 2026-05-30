# Lambda Scope Graph (Binding Index) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a NodeId-keyed binding index for the lambda language in a new `lang/lambda/scope/` package, consolidating duplicated name-resolution logic, and migrate `rename`'s binder-resolution onto it with proven equivalence.

**Architecture:** A single batch-built `ScopeGraph` (Scope/Decl/Ref keyed by `core.NodeId`) constructed in three passes from `FlatProj` + registry + `SourceMap`. v1 is non-incremental but correct. The `Resolution` record reserves negative-observation fields (`decl: DeclId?`, `visited_scopes`) for a future incremental layer. Only `declaration()` is wired to a consumer (`rename`) in v1; `references()` / `enclosing_env()` are reserved API surface.

**Tech Stack:** MoonBit; `dowdiness/canopy/core` (NodeId, ProjNode, SourceMap), `dowdiness/canopy/lang/lambda/proj` (FlatProj), `dowdiness/loomlambda/ast` (Term). Tests: `inspect` snapshots + whitebox `*_wbtest.mbt`.

**Design spec:** `docs/superpowers/specs/2026-05-30-lambda-scope-graph-design.md` — read it before starting; this plan implements it.

---

## File structure

- `lang/lambda/scope/moon.pkg` — package config (imports core, proj, ast).
- `lang/lambda/scope/graph.mbt` — data model: `ScopeGraph`, `Scope`, `Decl`, `Ref`, `Resolution`, `DeclKind`, `ScopeId`/`DeclId`/`RefId` + constructors. Language-agnostic except `DeclKind`.
- `lang/lambda/scope/builder.mbt` — `build(flat_proj, registry, source_map) -> ScopeGraph`: Pass 1 (parent map), Pass 2 (scopes + decls), Pass 3 (resolve refs).
- `lang/lambda/scope/query.mbt` — `declaration()`, `references()`, `enclosing_env()`.
- `lang/lambda/scope/graph_wbtest.mbt` — Layer 1 hand-written edge-case tests + Layer 3 equivalence test.
- `lang/lambda/scope/oracle_wbtest.mbt` — Layer 2 caimeox differential oracle (last task; non-blocking for the PoC gate).
- `moon.work` — add `lang/lambda/scope` to members.
- `lang/lambda/edits/text_edit_rename.mbt:27` — migrate the `resolve_binder` call in `rename_from_var` to `@scope.declaration()`.

**Naming note:** the new package's MoonBit module path is `dowdiness/canopy/lang/lambda/scope`; consumers alias it `@scope`. Inside the package, imports are aliased `@core`, `@lambda_proj` (for `dowdiness/canopy/lang/lambda/proj`), `@ast` (for `dowdiness/loomlambda/ast`).

---

## Task 1: Package scaffold + data model

**Files:**
- Create: `lang/lambda/scope/moon.pkg`
- Create: `lang/lambda/scope/graph.mbt`
- Modify: `moon.work` (add member)

- [ ] **Step 1: Create the package config**

Create `lang/lambda/scope/moon.pkg`:

```json
{
  "import": [
    "dowdiness/canopy/core",
    "dowdiness/canopy/lang/lambda/proj",
    "dowdiness/loomlambda/ast"
  ]
}
```

- [ ] **Step 2: Register the package in the workspace**

In `moon.work`, add `"lang/lambda/scope"` to the `members` array (place it next to the other `lang/lambda/*` entries). Add it exactly once.

- [ ] **Step 3: Write the data model**

Create `lang/lambda/scope/graph.mbt`:

```moonbit
///|
/// Graph-local compact indices. NOT persistent identity — `core.NodeId`
/// carries persistent identity; these index into the graph's own arrays.
pub(all) struct ScopeId(Int) derive(Eq, Hash, Compare, Show)

///|
pub(all) struct DeclId(Int) derive(Eq, Hash, Compare, Show)

///|
pub(all) struct RefId(Int) derive(Eq, Hash, Compare, Show)

///|
/// The kind of binding site a declaration represents. This is the one
/// lambda-specific type in graph.mbt (see design spec). A future loom
/// lift makes `Decl` generic over this (`Decl[K]`).
pub(all) enum DeclKind {
  LamParam(lam_id~ : @core.NodeId)
  ModuleDef(def_index~ : Int)
} derive(Eq, Show)

///|
/// A lexical scope. `parent` is the enclosing scope (None for the root).
pub(all) struct Scope {
  id : ScopeId
  parent : ScopeId?
  decl_ids : Array[DeclId]
  ref_ids : Array[RefId]
} derive(Show)

///|
/// A declaration (binding site), keyed by the projection NodeId it occupies.
pub(all) struct Decl {
  id : DeclId
  node_id : @core.NodeId
  name : String
  scope : ScopeId
  kind : DeclKind
} derive(Show)

///|
/// A reference (use site), keyed by NodeId, with its resolution result.
pub(all) struct Ref {
  id : RefId
  node_id : @core.NodeId
  name : String
  scope : ScopeId
  resolution : Resolution
} derive(Show)

///|
/// Resolution outcome for a reference.
/// `decl: None` is a NEGATIVE OBSERVATION (unresolved / free).
/// `visited_scopes` records scopes checked and found NOT to contain the
/// name — populated in v1 as a by-product of the resolution walk, read
/// only by a future incremental layer (see design spec).
pub(all) struct Resolution {
  decl : DeclId?
  visited_scopes : Array[ScopeId]
} derive(Show)

///|
/// The binding index for one lambda module.
pub(all) struct ScopeGraph {
  scopes : Array[Scope]
  decls : Array[Decl]
  refs : Array[Ref]
} derive(Show)
```

- [ ] **Step 4: Verify it compiles**

Run: `moon check -p dowdiness/canopy/lang/lambda/scope`
Expected: no errors (an empty package with only type defs compiles clean).

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/scope/moon.pkg lang/lambda/scope/graph.mbt moon.work
git commit -m "feat(scope): scaffold lang/lambda/scope package + data model"
```

---

## Task 2: Builder Pass 1 — NodeId → parent map

**Files:**
- Create: `lang/lambda/scope/builder.mbt`
- Test: `lang/lambda/scope/graph_wbtest.mbt`

- [ ] **Step 1: Write the failing test**

Create `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
/// Pass 1: the parent map links each node to its registry parent.
test "build_parent_map: child maps to parent" {
  // Build a tiny ProjNode tree by hand: root(id=0) with one child(id=1).
  let child = @core.ProjNode::new(@ast.Term::Var("x"), 0, 1, 1, [])
  let root = @core.ProjNode::new(
    @ast.Term::Lam("x", @ast.Term::Var("x")),
    0,
    5,
    0,
    [child],
  )
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let parents = build_parent_map(registry)
  inspect(parents.get(@core.NodeId(1)), content="Some(NodeId(0))")
  inspect(parents.get(@core.NodeId(0)), content="None")
}
```

Note: if `@core.next_proj_node_id` is not needed, delete the two `counter` lines — they are only a guard against an unused-import warning and the test does not require them.

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: FAIL — `build_parent_map` is not defined.

- [ ] **Step 3: Write minimal implementation**

Create `lang/lambda/scope/builder.mbt`:

```moonbit
///|
/// Pass 1: build a `NodeId -> parent NodeId` map by walking the registry's
/// ProjNode tree. Each node appears in exactly one parent's `children`
/// array, so the map is acyclic by construction. O(N).
pub fn build_parent_map(
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/scope/builder.mbt lang/lambda/scope/graph_wbtest.mbt
git commit -m "feat(scope): Pass 1 NodeId->parent map (acyclic by construction)"
```

---

## Task 3: Builder Pass 2 — scopes + decls

**Files:**
- Modify: `lang/lambda/scope/builder.mbt`
- Test: `lang/lambda/scope/graph_wbtest.mbt`

This pass creates: one root module scope; one `ModuleDef` decl per `FlatProj.defs` entry (in that scope); and one child scope + `LamParam` decl per `Lam` node (walking the projection tree). Refs are added empty here (Pass 3 fills resolution). We also record, per node, which scope it belongs to, so Pass 3 can find a ref's starting scope.

- [ ] **Step 1: Write the failing test**

Add to `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
/// Pass 2: a module with two defs yields one root scope + two ModuleDef decls.
test "build: module defs become ModuleDef decls in root scope" {
  let src = "let a = 1\nlet b = 2\nb"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  // two module defs → two decls, both ModuleDef, in the root scope (id 0)
  inspect(g.decls.length(), content="2")
  inspect(g.decls[0].kind, content="ModuleDef(def_index=0)")
  inspect(g.decls[1].kind, content="ModuleDef(def_index=1)")
  inspect(g.decls[0].scope, content="ScopeId(0)")
}
```

`build_test_projection` is the shared test helper used by `lang/lambda/edits/scope_wbtest.mbt`; copy its definition into this test file (see "Test helpers" section at the end of this plan for the exact code).

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: FAIL — `build` is not defined.

- [ ] **Step 3: Write minimal implementation**

Add to `lang/lambda/scope/builder.mbt`:

```moonbit
///|
/// Mutable builder state accumulated across passes.
priv struct Builder {
  scopes : Array[Scope]
  decls : Array[Decl]
  refs : Array[Ref]
  // node_id -> the scope a node lexically sits in (filled in Pass 2).
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
  let id = DeclId(self.decls.length())
  self.decls.push({ id, node_id, name, scope, kind })
  self.scopes[scope.0].decl_ids.push(id)
  id
}

///|
/// Pass 2: create the root module scope, ModuleDef decls (one per flat def),
/// and a child LamParam scope per Lam node. Records node→scope membership.
fn Builder::pass2(
  self : Builder,
  flat_proj : @lambda_proj.FlatProj,
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
) -> ScopeId {
  let root_scope = self.add_scope(None)
  // Module defs: one ModuleDef decl per flat def, in the root scope.
  for i, def in flat_proj.defs {
    let (name, _init, _start, binder_id) = def
    self.add_decl(root_scope, binder_id, name, ModuleDef(def_index=i))
  }
  // Lambda scopes: walk every node; each Lam opens a child scope binding param.
  fn walk(node : @core.ProjNode[@ast.Term], current : ScopeId) -> Unit {
    self.node_scope[node.id()] = current
    match node.kind {
      @ast.Term::Lam(param, _) => {
        // The Lam node itself sits in `current` (already recorded above);
        // its param decl and body live in the new child scope.
        let lam_scope = self.add_scope(Some(current))
        let _ = self.add_decl(lam_scope, node.id(), param, LamParam(lam_id=node.id()))
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

  for _id, node in registry {
    // Only walk from the root to keep scope nesting correct; find the root.
    if node.id() == @core.NodeId(root_node_id(registry)) {
      walk(node, root_scope)
    }
  }
  root_scope
}

///|
/// The registry's root is the node that is no other node's child.
fn root_node_id(
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
) -> Int {
  let parents = build_parent_map(registry)
  let mut found = 0
  for id, _node in registry {
    if parents.get(id) is None {
      found = id.raw()
    }
  }
  found
}

///|
/// Build the scope graph (Pass 2 only for now; Pass 3 added next task).
pub fn build(
  flat_proj : @lambda_proj.FlatProj,
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  source_map : @core.SourceMap,
) -> ScopeGraph {
  let _ = source_map // used in Pass 3
  let b = Builder::new()
  let _root = b.pass2(flat_proj, registry)
  { scopes: b.scopes, decls: b.decls, refs: b.refs }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: PASS. If the `Show` output for `DeclKind` differs (e.g. spacing), run `moon test -p dowdiness/canopy/lang/lambda/scope --update` to capture the actual snapshot, then read the diff to confirm it matches the intended `ModuleDef(def_index=0)` shape before accepting.

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/scope/builder.mbt lang/lambda/scope/graph_wbtest.mbt
git commit -m "feat(scope): Pass 2 build scopes + decls (module + lambda)"
```

---

## Task 4: Builder Pass 3 — resolve refs (with negative observations)

**Files:**
- Modify: `lang/lambda/scope/builder.mbt`
- Test: `lang/lambda/scope/graph_wbtest.mbt`

Pass 3 walks every `Var`/`Unbound` node, emits a `Ref`, and resolves it: walk the scope chain from the node's scope upward; at each scope, look for a `Decl` with the matching name **subject to the sequential-module cutoff** (a `ModuleDef` decl is visible to a ref only if the decl's `def_index` is strictly less than the def index the ref sits in, or the ref is in the module body). Record visited scopes that did not contain the name.

- [ ] **Step 1: Write the failing tests (the core binding rules)**

Add to `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
/// Lambda param resolves to its LamParam decl.
test "resolve: lambda param" {
  let src = "\\x. x"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  let var_node = find_var_node(root, "x")
  let d = declaration(g, var_node)
  inspect(d is Some(_), content="true")
  guard d is Some(decl)
  inspect(decl.kind, content="LamParam(lam_id=NodeId(0))")
}

///|
/// Self-reference is unbound: `let x = x` — the inner x sees no preceding x.
test "resolve: self-reference is unbound" {
  let src = "let x = x\nx"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  // the x in the INIT of def 0 must not resolve to def 0 itself
  let init_var = find_var_in_def_init(g, root, 0, "x")
  let d = declaration(g, init_var)
  inspect(d, content="None")
}

///|
/// Sequential shadowing: `let x = 1; let x = x` — second init binds to first x.
test "resolve: second def init binds to first def" {
  let src = "let x = 1\nlet x = x\nx"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  let init_var = find_var_in_def_init(g, root, 1, "x")
  let d = declaration(g, init_var)
  guard d is Some(decl)
  inspect(decl.kind, content="ModuleDef(def_index=0)")
}
```

`find_var_node` and `find_var_in_def_init` are test helpers — see "Test helpers" at the end of this plan for exact code.

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: FAIL — `declaration` not defined, and refs not yet resolved.

- [ ] **Step 3: Write the Pass 3 implementation**

Add to `lang/lambda/scope/builder.mbt`, and extend `build` to call it:

```moonbit
///|
fn Builder::add_ref(
  self : Builder,
  scope : ScopeId,
  node_id : @core.NodeId,
  name : String,
  resolution : Resolution,
) -> Unit {
  let id = RefId(self.refs.length())
  self.refs.push({ id, node_id, name, scope, resolution })
  self.scopes[scope.0].ref_ids.push(id)
}

///|
/// Which flat-def index a node sits within, by source position; returns the
/// number of defs (a body sentinel) when the node is in the module body.
fn containing_def_index(
  flat_proj : @lambda_proj.FlatProj,
  source_map : @core.SourceMap,
  node_id : @core.NodeId,
) -> Int {
  guard source_map.get_range(node_id) is Some(r) else {
    return flat_proj.defs.length()
  }
  let pos = r.start
  for i, def in flat_proj.defs {
    let (_n, init, _s, _id) = def
    if source_map.get_range(init.id()) is Some(dr) &&
      pos >= dr.start &&
      pos < dr.end {
      return i
    }
  }
  flat_proj.defs.length()
}

///|
/// Resolve a single ref name from `start_scope` upward. A ModuleDef decl is
/// visible only if its def_index < cutoff (sequential-module rule). Records
/// every scope visited that did not contain the name (negative observation).
fn Builder::resolve(
  self : Builder,
  name : String,
  start_scope : ScopeId,
  cutoff : Int,
) -> Resolution {
  let visited : Array[ScopeId] = []
  let mut cur : ScopeId? = Some(start_scope)
  while cur is Some(sid) {
    let scope = self.scopes[sid.0]
    let mut hit : DeclId? = None
    // innermost-match within a scope: later decls win (shadowing); for the
    // module scope, respect the cutoff.
    for did in scope.decl_ids {
      let decl = self.decls[did.0]
      if decl.name == name {
        match decl.kind {
          ModuleDef(def_index~) => if def_index < cutoff { hit = Some(did) }
          LamParam(..) => hit = Some(did)
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
    let scope = self.node_scope.get(node.id()).unwrap_or(ScopeId(0))
    let cutoff = containing_def_index(flat_proj, source_map, node.id())
    let resolution = self.resolve(n, scope, cutoff)
    self.add_ref(scope, node.id(), n, resolution)
  }
}
```

Replace the body of `build` with:

```moonbit
pub fn build(
  flat_proj : @lambda_proj.FlatProj,
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  source_map : @core.SourceMap,
) -> ScopeGraph {
  let b = Builder::new()
  let _root = b.pass2(flat_proj, registry)
  b.pass3(flat_proj, registry, source_map)
  { scopes: b.scopes, decls: b.decls, refs: b.refs }
}
```

- [ ] **Step 4: Write a minimal `declaration` so the tests can run**

Create `lang/lambda/scope/query.mbt`:

```moonbit
///|
/// The declaration a reference resolves to, or None if unresolved (free).
pub fn declaration(g : ScopeGraph, ref_node : @core.NodeId) -> Decl? {
  for r in g.refs {
    if r.node_id == ref_node {
      return match r.resolution.decl {
        Some(did) => Some(g.decls[did.0])
        None => None
      }
    }
  }
  None
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: PASS for all three resolution tests. If `Show` snapshots differ in spacing, `--update` and verify the diff matches the intended values (`LamParam(lam_id=NodeId(0))`, `None`, `ModuleDef(def_index=0)`) before accepting.

- [ ] **Step 6: Commit**

```bash
git add lang/lambda/scope/builder.mbt lang/lambda/scope/query.mbt lang/lambda/scope/graph_wbtest.mbt
git commit -m "feat(scope): Pass 3 resolve refs with sequential cutoff + negative observations"
```

---

## Task 5: Layer 1 — remaining hand-derived edge cases

**Files:**
- Modify: `lang/lambda/scope/graph_wbtest.mbt`

Pin the remaining binding rules from the spec's Layer 1 list: innermost lambda shadowing, module-def shadowing of body usages, and "later def is not visible to an earlier def".

- [ ] **Step 1: Write the failing tests**

Add to `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
/// Innermost lambda shadows outer: `\x. \x. x` — inner x binds to inner lam.
test "resolve: innermost lambda shadowing" {
  let src = "\\x. \\x. x"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  let var_node = find_var_node(root, "x")
  let d = declaration(g, var_node)
  guard d is Some(decl)
  // the binder is the INNER lambda — assert it is a LamParam (identity check
  // is exercised by the equivalence test in Task 8).
  inspect(
    (match decl.kind {
      LamParam(..) => true
      _ => false
    }),
    content="true",
  )
}

///|
/// Body usage resolves to the LATEST preceding def (module shadowing).
test "resolve: body binds to latest def" {
  let src = "let x = 1\nlet x = 2\nx"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  let body_var = find_var_in_body(g, root, "x")
  let d = declaration(g, body_var)
  guard d is Some(decl)
  inspect(decl.kind, content="ModuleDef(def_index=1)")
}

///|
/// A def's init cannot see a LATER def: `let a = b\nlet b = 1` — a's b unbound.
test "resolve: earlier def cannot see later def" {
  let src = "let a = b\nlet b = 1\na"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  let init_var = find_var_in_def_init(g, root, 0, "b")
  inspect(declaration(g, init_var), content="None")
}
```

- [ ] **Step 2: Run tests to verify they fail or pass**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: these may already PASS (the Pass 3 logic should handle them). If any FAIL, the resolution logic has a gap — fix `Builder::resolve` / `containing_def_index` until they pass. Do NOT weaken a test to match buggy output; the values above are hand-derived and authoritative (design spec Layer 1).

- [ ] **Step 3: Commit**

```bash
git add lang/lambda/scope/graph_wbtest.mbt
git commit -m "test(scope): Layer 1 hand-derived binding edge cases"
```

---

## Task 6: Reserved query API — references() + enclosing_env()

**Files:**
- Modify: `lang/lambda/scope/query.mbt`
- Test: `lang/lambda/scope/graph_wbtest.mbt`

These are reserved API surface (no v1 consumer) but must be correct and tested so later consumer migrations are safe. `references()` is identity-based; `enclosing_env()` returns a set.

- [ ] **Step 1: Write the failing tests**

Add to `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
/// references() is identity-based: shadowed uses do NOT all collapse to one decl.
test "references: identity-based, shadowing-aware" {
  let src = "let x = 1\nlet x = 2\nx"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  // the body `x` resolves to def 1; references(def1) includes the body x,
  // references(def0) does NOT (def0 is shadowed for the body).
  let def1 = g.decls[1].node_id
  let def0 = g.decls[0].node_id
  inspect(references(g, def1).length() >= 1, content="true")
  inspect(references(g, def0).length(), content="0")
}

///|
/// enclosing_env() returns lambda-bound names in scope at a node.
test "enclosing_env: lambda params in scope" {
  let src = "\\x. \\y. x"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  let var_node = find_var_node(root, "x")
  let env = enclosing_env(g, var_node)
  inspect(env.contains("x"), content="true")
  inspect(env.contains("y"), content="true")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: FAIL — `references` / `enclosing_env` not defined.

- [ ] **Step 3: Write the implementation**

Add to `lang/lambda/scope/query.mbt`:

```moonbit
///|
/// All reference NodeIds whose resolution points at the decl at `decl_node`.
/// Identity-based (NOT a name match), so shadowing is respected.
/// Reserved API surface; consumer migration deferred (see design spec).
pub fn references(g : ScopeGraph, decl_node : @core.NodeId) -> Array[@core.NodeId] {
  let mut target : DeclId? = None
  for d in g.decls {
    if d.node_id == decl_node {
      target = Some(d.id)
      break
    }
  }
  guard target is Some(tid) else { return [] }
  let out : Array[@core.NodeId] = []
  for r in g.refs {
    if r.resolution.decl is Some(rid) && rid == tid {
      out.push(r.node_id)
    }
  }
  out
}

///|
/// The set of names bound in scopes enclosing `node` (lambda params + module
/// defs). Set semantics (membership, not order). Replaces collect_lam_env.
/// Reserved API surface; consumer migration deferred (see design spec).
pub fn enclosing_env(
  g : ScopeGraph,
  node : @core.NodeId,
) -> @immut/hashset.HashSet[String] {
  let mut env : @immut/hashset.HashSet[String] = @immut/hashset.new()
  // find the scope the node sits in via the ref/decl tables
  let mut start : ScopeId? = None
  for r in g.refs {
    if r.node_id == node {
      start = Some(r.scope)
      break
    }
  }
  if start is None {
    for d in g.decls {
      if d.node_id == node {
        start = Some(d.scope)
        break
      }
    }
  }
  let mut cur = start
  while cur is Some(sid) {
    let scope = g.scopes[sid.0]
    for did in scope.decl_ids {
      env = env.add(g.decls[did.0].name)
    }
    cur = scope.parent
  }
  env
}
```

Add `"moonbitlang/core/immut/hashset"` to the `import` array in `lang/lambda/scope/moon.pkg` if `moon check` reports the `@immut/hashset` path is unresolved.

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/scope/query.mbt lang/lambda/scope/moon.pkg lang/lambda/scope/graph_wbtest.mbt
git commit -m "feat(scope): reserved query API references() + enclosing_env()"
```

---

## Task 7: Generate interfaces + full package check

**Files:**
- Generated: `lang/lambda/scope/scope.mbti` (or `pkg.generated.mbti`)

- [ ] **Step 1: Generate interface + format**

Run: `moon info -p dowdiness/canopy/lang/lambda/scope && moon fmt`
Expected: a `.mbti` file is generated/updated; formatting applied.

- [ ] **Step 2: Review the generated interface**

Run: `git diff --stat lang/lambda/scope/`
Read the generated `.mbti`. Confirm the public surface is exactly: `ScopeGraph`, `Scope`, `Decl`, `Ref`, `Resolution`, `DeclKind`, `ScopeId`/`DeclId`/`RefId`, `build`, `declaration`, `references`, `enclosing_env` (plus `build_parent_map`). No accidental internal exposure.

- [ ] **Step 3: Full workspace check + test**

Run: `moon check && moon test -p dowdiness/canopy/lang/lambda/scope`
Expected: no errors; all scope tests pass.

- [ ] **Step 4: Commit**

```bash
git add lang/lambda/scope/
git commit -m "chore(scope): generate .mbti + format"
```

---

## Task 8: Layer 3 — migrate rename + equivalence test

**Files:**
- Modify: `lang/lambda/edits/text_edit_rename.mbt:27` (the `resolve_binder` call in `rename_from_var`)
- Modify: `lang/lambda/edits/moon.pkg` (add scope import)
- Test: `lang/lambda/scope/graph_wbtest.mbt` (equivalence test)

The migration swaps `resolve_binder` → `@scope.declaration()` mapped to `BindingSite`. The equivalence test pins that the new path returns the SAME `BindingSite` as the old `resolve_binder` across fixtures (behavior-preserving, bugs included — correctness is Layer 1's job).

- [ ] **Step 1: Write the equivalence test FIRST (old still live)**

Add to `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
/// Map a scope-graph Decl back to the edits-layer BindingSite shape.
fn decl_to_binding_site(decl : Decl) -> (String, @core.NodeId, Int) {
  // returns (tag, node_id, def_index) — def_index is -1 for lambda params.
  match decl.kind {
    LamParam(lam_id~) => ("lam", lam_id, -1)
    ModuleDef(def_index~) => ("module", decl.node_id, def_index)
  }
}

///|
/// Equivalence: declaration() agrees with the old resolve_binder on a fixture.
/// (resolve_binder lives in lang/lambda/edits; this test imports it.)
test "equivalence: declaration matches resolve_binder (lambda param)" {
  let src = "\\x. x"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  let var_node = find_var_node(root, "x")
  // new path
  let new_site = match declaration(g, var_node) {
    Some(d) => Some(decl_to_binding_site(d))
    None => None
  }
  // old path
  let old_site = match @edits.resolve_binder(
      var_node, "x", flat_proj, registry, source_map,
    ) {
    Some(@edits.LamBinder(lam_id~)) => Some(("lam", lam_id, -1))
    Some(@edits.ModuleBinder(binding_node_id~, def_index~)) =>
      Some(("module", binding_node_id, def_index))
    None => None
  }
  inspect(new_site == old_site, content="true")
}
```

Note: this test requires the scope test build to import `dowdiness/canopy/lang/lambda/edits`. Add `"dowdiness/canopy/lang/lambda/edits"` to a `test-import` (not `import`, to avoid a production cycle) in `lang/lambda/scope/moon.pkg`. If MoonBit reports a dependency cycle (edits will soon import scope), keep this equivalence test in the `edits` package instead — create `lang/lambda/edits/scope_equivalence_wbtest.mbt` with the same body, importing `@scope`. Decide based on which direction the production import goes (Step 3 makes edits→scope), so the equivalence test belongs in `edits` (test-only use of both is fine there).

- [ ] **Step 2: Run the equivalence test (old behavior, new graph)**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt` (or the edits package if relocated).
Expected: PASS — both paths return the lambda binder. If FAIL, the graph disagrees with `resolve_binder`; investigate which is right against Layer 1 before changing either.

- [ ] **Step 3: Migrate the consumer**

In `lang/lambda/edits/moon.pkg`, add `"dowdiness/canopy/lang/lambda/scope"` to `import`.

In `lang/lambda/edits/text_edit_rename.mbt`, replace the `resolve_binder` call in `rename_from_var` (around line 27) with a call through the graph. Build the graph from the same inputs and map `Decl -> BindingSite`:

```moonbit
pub fn rename_from_var(
  var_node_id : NodeId,
  var_name : String,
  flat_proj : FlatProj,
  registry : Map[NodeId, ProjNode[@ast.Term]],
  source_map : SourceMap,
) -> RenameResult? {
  let g = @scope.build(flat_proj, registry, source_map)
  guard @scope.declaration(g, var_node_id) is Some(decl) else { return None }
  match decl.kind {
    @scope.LamParam(lam_id~) =>
      rename_lam_param(lam_id, var_name, registry, source_map)
    @scope.ModuleDef(def_index~) =>
      rename_module_binding(
        decl.node_id,
        def_index,
        var_name,
        flat_proj,
        registry,
        source_map,
      )
  }
}
```

Leave `resolve_binder` and the other `resolve_binder` caller (`rename_lam_param`'s internal use, if any) in place — only `rename_from_var`'s binder lookup is migrated in v1 (design spec Non-goals). Do NOT delete `resolve_binder` yet; the equivalence test depends on it.

- [ ] **Step 4: Run the full rename + scope test suites**

Run: `moon check && moon test -p dowdiness/canopy/lang/lambda/edits && moon test -p dowdiness/canopy/lang/lambda/scope`
Expected: all existing `text_edit_rename_test.mbt` tests still PASS (behavior preserved), plus the equivalence test passes.

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/edits/text_edit_rename.mbt lang/lambda/edits/moon.pkg lang/lambda/scope/
git commit -m "feat(scope): migrate rename_from_var binder lookup to scope graph (equivalent)"
```

---

## Task 9: Layer 2 — caimeox differential oracle (last; non-blocking)

**Files:**
- Create: `lang/lambda/scope/oracle_wbtest.mbt`
- Modify: `moon.mod.json` (add caimeox dependency) — only if integration is feasible

This task adds the caimeox scope_graph implementation as a batch oracle. It is sequenced LAST because Layer 1 (correctness) and Layer 3 (migration) are the actual gates; if vendoring caimeox proves heavy, the PoC still ships and this lands as a follow-up. Do NOT block the PoC on it.

- [ ] **Step 1: Assess dependency integration**

Run: `cat moon.mod.json` and check how external MoonBit deps are declared. caimeox/scope_graph is at `https://github.com/caimeox/scope_graph` (Apache-2.0). Determine whether it is mooncakes-published or must be vendored. If neither path is clean in under ~30 min, STOP and report: "Layer 2 oracle deferred to follow-up; Layer 1 + Layer 3 are the shipping gates per design spec." Do not force a fragile dependency.

- [ ] **Step 2: Write the adapter + one differential test (if dep integrated)**

Create `lang/lambda/scope/oracle_wbtest.mbt`. Write an INDEPENDENT `Term -> @lm.LmProgram` adapter (does NOT route through `builder.mbt`/`query.mbt`), restricted to the shared subset (Var / Lam / App / Module / let-equivalent). For a fixture, build both the canopy graph and the caimeox graph, resolve a chosen reference in each, and assert they agree via a NodeId↔caimeox-index side table:

```moonbit
///|
test "oracle: caimeox agrees on let shadowing (shared subset)" {
  // build canopy graph
  let src = "let x = 1\nlet x = 2\nx"
  let (root, source_map) = build_test_projection(src)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(root, registry)
  let flat_proj = @lambda_proj.build_flat_proj(root, source_map)
  let g = build(flat_proj, registry, source_map)
  let body_var = find_var_in_body(g, root, "x")
  let canopy_def_index = match declaration(g, body_var) {
    Some(d) => match d.kind { ModuleDef(def_index~) => def_index; _ => -1 }
    None => -2
  }
  // caimeox path: adapt to LmProgram, resolve the corresponding ref,
  // map its resolved decl back to a def index.
  // (adapter + resolution omitted here; implement per caimeox API:
  //  build_scope_graph(program) then resolve_ref(ref_id).)
  let caimeox_def_index = oracle_resolve_body_x(src)
  inspect(canopy_def_index == caimeox_def_index, content="true")
}
```

Implement `oracle_resolve_body_x` using caimeox's `build_scope_graph` + `resolve_ref` (see `/tmp/scope_graph_probe/scope_graph/` for the API: `ScopeGraph::resolve_ref(ref_id) -> HashSet[Int]`). Keep the adapter in this test file only.

- [ ] **Step 3: Apply the adjudication rule on disagreement**

If caimeox and canopy disagree on a fixture, per the design spec: Layer 1 + Layer 3 win, and the caimeox fixture is REMOVED from the differential set with a one-line comment recording why (documented, not silently dropped).

- [ ] **Step 4: Run + commit (if integrated)**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f oracle_wbtest.mbt`
Expected: PASS on the shared subset.

```bash
git add lang/lambda/scope/oracle_wbtest.mbt moon.mod.json
git commit -m "test(scope): caimeox differential oracle on shared subset"
```

If deferred at Step 1, instead commit a stub note:

```bash
# create lang/lambda/scope/oracle_wbtest.mbt with a top comment:
#   // Layer 2 caimeox oracle deferred to follow-up — see design spec.
#   // Layer 1 (graph_wbtest) + Layer 3 (equivalence) are the shipping gates.
git add lang/lambda/scope/oracle_wbtest.mbt
git commit -m "docs(scope): note Layer 2 oracle deferred to follow-up"
```

---

## Task 10: Final verification + PR prep

- [ ] **Step 1: Full workspace gate**

Run: `moon check && moon test && moon fmt && moon info`
Expected: clean across the workspace; all tests pass.

- [ ] **Step 2: Confirm the migration is real and scoped**

Run: `git diff main --stat`
Expected: only `lang/lambda/scope/*`, `moon.work`, `lang/lambda/edits/text_edit_rename.mbt`, `lang/lambda/edits/moon.pkg`, and the design spec. No unintended files. Confirm `resolve_binder` still exists (not deleted in v1).

- [ ] **Step 3: Reuse-check note for the PR**

Confirm in the PR description: `declaration()` reuses the existing `BindingSite` consumer contract; no duplicate types were introduced (checked `@core.NodeId`, `@lambda_proj.FlatProj` reused, not re-defined).

- [ ] **Step 4: Open the PR**

```bash
git push -u origin design/lambda-scope-graph
gh pr create --title "feat(scope): NodeId-keyed binding index for lambda (v1, rename migrated)" --body "Implements docs/superpowers/specs/2026-05-30-lambda-scope-graph-design.md. v1: non-incremental binding index; rename_from_var binder lookup migrated with equivalence test. references()/enclosing_env() reserved. Layer 2 oracle per Task 9 status."
```

---

## Test helpers (copy into the test file that needs them)

These mirror the helpers in `lang/lambda/edits/scope_wbtest.mbt`. The scope package's test files need their own copies (test helpers are not exported across packages). Read `lang/lambda/edits/scope_wbtest.mbt:13-` for the canonical `build_test_projection` body and copy it verbatim, adjusting the `@`-aliases to the scope package's imports. The additional finders:

```moonbit
///|
/// Find the first Var node with the given name anywhere in the tree.
fn find_var_node(
  root : @core.ProjNode[@ast.Term],
  name : String,
) -> @core.NodeId {
  let mut found : @core.NodeId? = None
  fn walk(n : @core.ProjNode[@ast.Term]) -> Unit {
    if found is Some(_) {
      return
    }
    if n.kind is @ast.Term::Var(x) && x == name {
      found = Some(n.id())
      return
    }
    for c in n.children {
      walk(c)
    }
  }
  walk(root)
  found.unwrap()
}

///|
/// Find the Var with `name` inside the init expression of flat def `idx`.
fn find_var_in_def_init(
  g : ScopeGraph,
  root : @core.ProjNode[@ast.Term],
  idx : Int,
  name : String,
) -> @core.NodeId {
  let _ = g
  // The init of def idx is the Module's child at position idx. Walk into it.
  match root.kind {
    @ast.Term::Module(_, _) => {
      let init = root.children[idx]
      find_var_node(init, name)
    }
    _ => find_var_node(root, name)
  }
}

///|
/// Find the Var with `name` in the module body (the final expression).
fn find_var_in_body(
  g : ScopeGraph,
  root : @core.ProjNode[@ast.Term],
  name : String,
) -> @core.NodeId {
  let _ = g
  match root.kind {
    @ast.Term::Module(defs, _) => {
      // body is the last child (after the def inits)
      let body = root.children[root.children.length() - 1]
      let _ = defs
      find_var_node(body, name)
    }
    _ => find_var_node(root, name)
  }
}
```

**Important on `find_var_in_def_init` / `find_var_in_body`:** the exact mapping from `FlatProj.defs[i]` / body to `ProjNode` children depends on how `build_flat_proj` lays out the Module projection. Before relying on `root.children[idx]`, verify the child layout by reading `lang/lambda/proj/flat_proj.mbt:18-` (the `build_flat_proj` body) and `lang/lambda/proj/proj_node.mbt` Module construction. If the body is not the last child, adjust `find_var_in_body` accordingly. This verification is part of Task 4 Step 1 (writing the test) — do it before asserting positions.
