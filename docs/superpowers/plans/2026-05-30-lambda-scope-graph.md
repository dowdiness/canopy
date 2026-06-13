# Lambda Scope Graph (Binding Index) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a NodeId-keyed binding index for the lambda language in a new `lang/lambda/scope/` package, consolidating duplicated name-resolution logic, and migrate `rename`'s binder-resolution onto it with proven equivalence.

**Architecture:** A single batch-built `ScopeGraph` (Scope/Decl/Ref keyed by `@core.NodeId`) constructed in three passes from `FlatProj` + registry + `SourceMap`. v1 is non-incremental but correct. The `Resolution` record reserves negative-observation fields (`decl: DeclId?`, `visited_scopes`) for a future incremental layer. Only `declaration()` is wired to a consumer (`rename`) in v1; `references()` / `enclosing_env()` are reserved API surface.

**Tech Stack:** MoonBit; `dowdiness/canopy/core` (NodeId, ProjNode, SourceMap, collect_registry — alias `@core`), `dowdiness/canopy/lang/lambda/proj` (FlatProj, parse_to_proj_node — alias `@lambda_proj`, matching the sibling `edits` package), `dowdiness/lambda/ast` (Term, alias `@ast`). Tests: `inspect` on **scalar projections** + whitebox `*_wbtest.mbt`.

**Design spec:** `docs/superpowers/specs/2026-05-30-lambda-scope-graph-design.md` — read it before starting; this plan implements it.

---

## Verified facts (read these before starting — they fix common wrong guesses)

Confirmed by reading the code. Do NOT substitute your own guesses, and do NOT
trust the *old* assumptions some of these correct:

- **AST type:** `@ast.Term` from package `dowdiness/lambda/ast` (default alias
  `@ast`). Variants: `Int(Int)`, `Var(VarName)`, `Lam(VarName, Term)`,
  `App(Term, Term)`, `Bop(Bop, Term, Term)`, `If(Term, Term, Term)`,
  `Module(Array[(VarName, Term)], Term)`, `Unit`, `Unbound(VarName)`,
  `Error(String)`, `Hole(Int)`. (`VarName = String`.) Always match with the
  type-qualified form `@ast.Term::Var(x)`. Source:
  `loom/examples/lambda/src/ast/ast.mbt:18`.
- **NodeId:** `pub struct NodeId(Int)` in `@core` (`derive(Debug, Eq, Hash,
  Compare)`); construct via `@core.NodeId::from_int(n)` or pattern
  `@core.NodeId(n)`. Source: `core/types.mbt:6`.
- **ProjNode:** `@core.ProjNode[T]` with `.id() -> NodeId`, `.children`,
  `.kind`, `.start`, `.end`; construct via
  `@core.ProjNode::new(kind, start, end, node_id, children)`. Source:
  `core/proj_node.mbt:7,32`.
- **Registry walk:** `@core.collect_registry(node, reg)` fills
  `reg : Map[@core.NodeId, @core.ProjNode[T]]` by walking the tree. Source:
  `core/proj_node.mbt:58`.
- **SourceMap:** lives in `@core`. The accessor is
  `@core.SourceMap::get_range(node_id) -> @core.Range?` with `.start` / `.end`
  fields (`core/source_map.mbt:104`). Construct in tests via
  `@core.SourceMap::from_ast(proj)` — `from_ast` is a `SourceMap` method, so it
  is `@core.`, NOT `@lambda_proj.` (it appears *unqualified* in
  `lang/lambda/edits/scope_wbtest.mbt:21` only because that package pulls it in
  via `using`).
- **FlatProj:** `pub struct FlatProj { defs : Array[(String, ProjNode[@ast.Term], Int, NodeId)]; final_expr : ProjNode[@ast.Term]? }`
  — the def tuple is `(name, init, start, binding_id)`. In `@lambda_proj`. Source:
  `lang/lambda/proj/flat_proj.mbt:5`. Construct via
  `@lambda_proj.FlatProj::from_proj_node(proj)`. **Important id-shape note:**
  `from_proj_node` sets a def's binding id (`.3`) to the **init child's** id
  (`flat_proj.mbt:281`), whereas the live editor path (`to_flat_proj`) allocates
  a *separate* binding id (`flat_proj.mbt:29`). Both the scope graph and
  `resolve_binder` read `flat_proj.defs[i].3`, so they stay consistent on
  whatever FlatProj is passed — but tests built with `from_proj_node` exercise
  the init-child id-shape, while the live path is exercised by Task 8 Step 5's
  integration tests.
- **Module ProjNode child layout:** def inits are the Module node's leading
  children `[0 .. n-1]`; the body is the **last** child
  (`flat_proj.mbt:251-252,278-285`; the working test
  `scope_wbtest.mbt:38` reads the body as
  `proj.children[proj.children.length() - 1]`). A pure expression (no defs)
  produces NO Module wrapper — `from_proj_node` returns the bare expr.
- **parse_to_proj_node:** `@lambda_proj.parse_to_proj_node(text) -> (ProjNode[@ast.Term], Array[String]) raise @loom/core.LexError`.
  Source: `lang/lambda/proj/proj_node.mbt:315`. **It is FALLIBLE** (`raise`) and the
  second tuple element is an `Array[String]` of parse errors, NOT a `Ref[Int]`
  counter. Verified 2026-05-30 via `moon ide doc parse_to_proj_node`. Inside a
  `test` block the `raise` auto-propagates (no annotation needed — see
  `scope_wbtest.mbt:19`), but any standalone `fn` that calls it must declare
  `raise` in its signature (bare `) raise {`, the repo idiom — see
  `lang/lambda/semantic/semantic_projection_test.mbt:4,16`). Otherwise MoonBit
  errors [4122] "Function with error can only be used inside a function with
  error types in its signature." The lambda surface syntax uses MoonBit-style arrow lambdas, as in `scope_wbtest.mbt:18` (`"(x) => x"`).
- **Existing binder API (the v1 migration target):**
  `pub fn resolve_binder(var_node_id, var_name, flat_proj, registry, source_map) -> BindingSite?`
  where `pub(all) enum BindingSite { LamBinder(lam_id~ : NodeId); ModuleBinder(binding_node_id~ : NodeId, def_index~ : Int) } derive(Debug, Eq)`.
  Its algorithm (mirror it exactly): (1) walk up the registry tree for an
  enclosing `Lam` binding the name → `LamBinder(lam_id = enclosing-Lam-NodeId)`;
  (2) else find which def-init range (or body) the var sits in via
  `source_map.get_range`, then walk def indices **backward** from there, first
  name match → `ModuleBinder(binding_node_id = flat_proj.defs[i].3, def_index = i)`;
  (3) else `None`. Source: `lang/lambda/edits/scope.mbt:11-62`.
- **The one consumer to migrate:** `rename_from_var` in
  `lang/lambda/edits/text_edit_rename.mbt:99`, calling `resolve_binder` at line
  105 through an `EditContext[T]` bundle:
  `pub(all) struct EditContext[T] { registry; flat_proj; source_map; language; on_structural_edit }`
  (`lang/lambda/edits/text_edit.mbt:7`). It dispatches `LamBinder(lam_id~) ->
  rename_lam_param(...)`, `ModuleBinder(binding_node_id~, def_index~) ->
  rename_module_binding(...)`.
- **`collect_lam_env` semantics:** `lang/lambda/edits/scope.mbt:147` collects
  **only enclosing Lam parameter names** — it does NOT include module defs. The
  reserved `enclosing_env` query (Task 6) returns the *full* lexical environment
  (lam params AND module defs), so it is a **superset**, not a drop-in
  replacement. Do not claim equivalence.
- **derive / inspect convention:** this repo uses `derive(Debug, Eq)` (see
  `BindingSite`), NOT `derive(Show)` (deprecated on container-bearing types).
  Tests therefore `inspect` only **scalar projections** — bools, ints, strings
  — never whole structs/enums/Options. Mirror `scope_wbtest.mbt` (it inspects
  `lam_id == proj.id()` and `def_index`, never the `BindingSite` value).
- **Workspace:** `moon.work` members do NOT list `lang/*`; the root member `.`
  already covers `lang/lambda/scope`. **Do NOT edit `moon.work`.**
- **moon.pkg format:** this repo's moon.pkg files use the
  `import { "path" @alias, ... }` block + `warnings = "..."` form (NOT
  `moon.pkg.json`); see `lang/lambda/edits/moon.pkg`. A bare path takes its
  default alias (last segment, or enough segments to disambiguate — e.g.
  `moonbitlang/core/immut/hashset` → `@immut/hashset`); an explicit `@alias`
  overrides it. The `edits` package aliases proj as `@lambda_proj` — match that.
- **New package module path:** `dowdiness/canopy/lang/lambda/scope`; consumers
  alias it `@scope`.

---

## File structure

- `lang/lambda/scope/moon.pkg` — `import { }` package config (imports core, proj, ast, immut/hashset).
- `lang/lambda/scope/graph.mbt` — data model: `ScopeGraph`, `Scope`, `Decl`, `Ref`, `Resolution`, `DeclKind`, `ScopeId`/`DeclId`/`RefId`. Language-agnostic except `DeclKind`.
- `lang/lambda/scope/builder.mbt` — `build(...)`: Pass 1 (parent map), Pass 2 (scopes + decls), Pass 3 (resolve refs).
- `lang/lambda/scope/query.mbt` — `declaration()`, `references()`, `enclosing_env()`.
- `lang/lambda/scope/graph_wbtest.mbt` — Layer 1 hand tests + test helpers.
- `lang/lambda/scope/oracle_wbtest.mbt` — Layer 2 caimeox differential oracle (last task; non-blocking).
- `lang/lambda/edits/scope_equivalence_wbtest.mbt` — Layer 3 equivalence test (lives in `edits` because the production import goes edits→scope).
- `lang/lambda/edits/text_edit_rename.mbt:99-139` + `lang/lambda/edits/moon.pkg` — migrate the `rename_from_var` binder lookup to `@scope`.

---

## Task 1: Package scaffold + data model

**Files:**
- Create: `lang/lambda/scope/moon.pkg`
- Create: `lang/lambda/scope/graph.mbt`

- [ ] **Step 1: Create the package config**

Create `lang/lambda/scope/moon.pkg` (this repo uses the `import { ... }` /
`warnings = "..."` moon.pkg format, NOT `moon.pkg.json` — copy the shape from
`lang/lambda/edits/moon.pkg`):

```
import {
  "dowdiness/canopy/core",
  "dowdiness/canopy/lang/lambda/proj" @lambda_proj,
  "dowdiness/lambda/ast",
  "moonbitlang/core/immut/hashset" @immut/hashset,
}
warnings = "-2-6-29"
```

Bare paths take the default alias (`@core`, `@ast`); the explicit `@lambda_proj`
and `@immut/hashset` aliases match the sibling `edits` package.

- [ ] **Step 2: (No moon.work change.)**

Confirm `moon.work` already covers the new package via the root `.` member — do
NOT add an entry. Verify with: `grep -n 'lang/lambda' moon.work` → expect no
output.

- [ ] **Step 3: Write the data model**

Create `lang/lambda/scope/graph.mbt`. Newtypes are `Int`-based so `derive` is
unproblematic; the larger records use `derive(Debug, Eq)` per repo convention
(no `Show`).

```moonbit
///|
/// Graph-local compact indices. NOT persistent identity — `@core.NodeId`
/// carries persistent identity; these index into the graph's own arrays.
pub(all) struct ScopeId(Int) derive(Debug, Eq, Hash, Compare)

///|
pub(all) struct DeclId(Int) derive(Debug, Eq, Hash, Compare)

///|
pub(all) struct RefId(Int) derive(Debug, Eq, Hash, Compare)

///|
/// The kind of binding site a declaration represents. The one lambda-specific
/// type here (see design spec). A future loom lift makes `Decl` generic over
/// this (`Decl[K]`).
pub(all) enum DeclKind {
  LamParam(lam_id~ : @core.NodeId)
  ModuleDef(def_index~ : Int)
} derive(Debug, Eq)

///|
/// A lexical scope. `parent` is the enclosing scope (None for the root).
pub(all) struct Scope {
  id : ScopeId
  parent : ScopeId?
  decl_ids : Array[DeclId]
  ref_ids : Array[RefId]
} derive(Debug)

///|
/// A declaration (binding site), keyed by the projection NodeId it occupies.
pub(all) struct Decl {
  id : DeclId
  node_id : @core.NodeId
  name : String
  scope : ScopeId
  kind : DeclKind
} derive(Debug, Eq)

///|
/// A reference (use site), keyed by NodeId, with its resolution result.
pub(all) struct Ref {
  id : RefId
  node_id : @core.NodeId
  name : String
  scope : ScopeId
  resolution : Resolution
} derive(Debug)

///|
/// Resolution outcome for a reference.
/// `decl: None` is a NEGATIVE OBSERVATION (unresolved / free).
/// `visited_scopes` records scopes checked and found NOT to contain the
/// name — populated in v1 as a by-product of the resolution walk, read only
/// by a future incremental layer (see design spec).
pub(all) struct Resolution {
  decl : DeclId?
  visited_scopes : Array[ScopeId]
} derive(Debug)

///|
/// The binding index for one lambda module.
pub(all) struct ScopeGraph {
  scopes : Array[Scope]
  decls : Array[Decl]
  refs : Array[Ref]
} derive(Debug)
```

- [ ] **Step 4: Verify it compiles**

Run: `moon check -p dowdiness/canopy/lang/lambda/scope`
Expected: no errors. `@immut/hashset` is used in Task 6; the `-2-6-29`
warning-list suppresses the interim unused-import warning.

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/scope/moon.pkg lang/lambda/scope/graph.mbt
git commit -m "feat(scope): scaffold lang/lambda/scope package + data model"
```

---

## Task 2: Test helpers + Builder Pass 1 (NodeId → parent map)

**Files:**
- Create: `lang/lambda/scope/builder.mbt`
- Create: `lang/lambda/scope/graph_wbtest.mbt`

> **Test-assertion rule (applies to every test in this plan):** `inspect` only
> scalar projections (bool / int / string). Never `inspect` a struct, enum, or
> Option whole — the types derive `Debug`, not `Show`. To check an enum variant,
> use `x is Variant(_)` (a bool) or destructure with `guard ... is Variant(f~)`
> then inspect `f`. To check a newtype, destructure: `let ScopeId(n) = s`.

- [ ] **Step 1: Write the test helpers + first failing test**

Create `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
/// Build (proj, flat_proj, registry, source_map) from source.
fn build_fixture(
  text : String,
) -> (
  @core.ProjNode[@ast.Term],
  @lambda_proj.FlatProj,
  Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  @core.SourceMap,
) raise {
  let (proj, _errs) = @lambda_proj.parse_to_proj_node(text)
  let flat_proj = @lambda_proj.FlatProj::from_proj_node(proj)
  let source_map = @core.SourceMap::from_ast(proj)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(proj, registry)
  (proj, flat_proj, registry, source_map)
}

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
test "build_parent_map: child maps to parent" {
  // Hand-built tree: root(id=0) Lam with one child Var(id=1).
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
  inspect(parents.get(@core.NodeId::from_int(1)) is Some(_), content="true")
  guard parents.get(@core.NodeId::from_int(1)) is Some(p)
  inspect(p == @core.NodeId::from_int(0), content="true")
  inspect(parents.get(@core.NodeId::from_int(0)) is None, content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: FAIL — `build_parent_map` not defined.

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
git commit -m "feat(scope): test helpers + Pass 1 NodeId->parent map"
```

---

## Task 3: Builder Pass 2 — scopes + decls

**Files:**
- Modify: `lang/lambda/scope/builder.mbt`
- Test: `lang/lambda/scope/graph_wbtest.mbt`

Pass 2 creates: one root module scope; one `ModuleDef` decl per `FlatProj.defs`
entry (in the root scope); one child scope + `LamParam` decl per `Lam` node
(walking the projection tree). It records, per node, which scope it lexically
sits in, so Pass 3 can find a ref's starting scope.

- [ ] **Step 1: Write the failing test**

Add to `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
test "build: module defs become ModuleDef decls in root scope" {
  let (_proj, flat_proj, registry, source_map) = build_fixture(
    "let a = 1\nlet b = 2\nb",
  )
  let g = build(flat_proj, registry, source_map)
  inspect(g.decls.length(), content="2")
  guard g.decls[0].kind is ModuleDef(def_index=d0)
  inspect(d0, content="0")
  guard g.decls[1].kind is ModuleDef(def_index=d1)
  inspect(d1, content="1")
  let ScopeId(s0) = g.decls[0].scope
  inspect(s0, content="0")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: FAIL — `build` not defined.

- [ ] **Step 3: Write minimal implementation**

Add to `lang/lambda/scope/builder.mbt`:

```moonbit
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
  let mut root : @core.ProjNode[@ast.Term]? = None
  for id, node in registry {
    if parents.get(id) is None {
      root = Some(node)
    }
  }
  root.unwrap()
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
          lam_scope, node.id(), param, LamParam(lam_id=node.id()),
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
/// Build the scope graph (Pass 2 only for now; Pass 3 added next task).
pub fn build(
  flat_proj : @lambda_proj.FlatProj,
  registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  source_map : @core.SourceMap,
) -> ScopeGraph {
  let _ = source_map // used in Pass 3
  let b = Builder::new()
  b.pass2(flat_proj, registry)
  { scopes: b.scopes, decls: b.decls, refs: b.refs }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/scope/builder.mbt lang/lambda/scope/graph_wbtest.mbt
git commit -m "feat(scope): Pass 2 build scopes + decls (module + lambda)"
```

---

## Task 4: Builder Pass 3 + declaration() — resolve refs

**Files:**
- Modify: `lang/lambda/scope/builder.mbt`
- Create: `lang/lambda/scope/query.mbt`
- Test: `lang/lambda/scope/graph_wbtest.mbt`

Pass 3 walks every `Var`/`Unbound` node, emits a `Ref`, and resolves it: from the
node's scope, walk parents upward; in each scope, match a `Decl` by name, with a
**sequential-module cutoff** — a `ModuleDef` decl is visible to a ref only if its
`def_index` is strictly less than the def index the ref sits in (body refs see
all defs). This mirrors `resolve_binder`'s backward walk exactly (Verified facts).
Visited scopes lacking the name are recorded (negative observation).

- [ ] **Step 1: Write the failing tests (core binding rules)**

Add to `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
/// Find the Var with `name` in the module body (the final/last child).
fn find_var_in_body(
  root : @core.ProjNode[@ast.Term],
  name : String,
) -> @core.NodeId {
  match root.kind {
    @ast.Term::Module(_, _) =>
      find_var_node(root.children[root.children.length() - 1], name)
    _ => find_var_node(root, name)
  }
}

///|
/// Find the Var with `name` inside the init expression of flat def `idx`.
/// def inits are the Module's leading children (before the body).
fn find_var_in_def_init(
  root : @core.ProjNode[@ast.Term],
  idx : Int,
  name : String,
) -> @core.NodeId {
  match root.kind {
    @ast.Term::Module(_, _) => find_var_node(root.children[idx], name)
    _ => find_var_node(root, name)
  }
}

///|
test "resolve: lambda param" {
  let (proj, flat_proj, registry, source_map) = build_fixture("(x) => x")
  let g = build(flat_proj, registry, source_map)
  let var_node = find_var_node(proj, "x")
  guard declaration(g, var_node) is Some(decl)
  inspect(decl.kind is LamParam(_), content="true")
}

///|
test "resolve: self-reference is unbound" {
  let (proj, flat_proj, registry, source_map) = build_fixture("let x = x\nx")
  let g = build(flat_proj, registry, source_map)
  let init_var = find_var_in_def_init(proj, 0, "x")
  inspect(declaration(g, init_var) is None, content="true")
}

///|
test "resolve: second def init binds to first def" {
  let (proj, flat_proj, registry, source_map) = build_fixture(
    "let x = 1\nlet x = x\nx",
  )
  let g = build(flat_proj, registry, source_map)
  let init_var = find_var_in_def_init(proj, 1, "x")
  guard declaration(g, init_var) is Some(decl)
  guard decl.kind is ModuleDef(def_index~)
  inspect(def_index, content="0")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: FAIL — `declaration` not defined; refs unresolved.

- [ ] **Step 3: Write Pass 3 in builder.mbt**

Add to `lang/lambda/scope/builder.mbt` and extend `build`:

```moonbit
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
/// def count (body sentinel) when the node is in the module body. Mirrors
/// resolve_binder's def-range containment (scope.mbt:30-39).
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
```

Replace the body of `build`:

```moonbit
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
```

- [ ] **Step 4: Write declaration() in query.mbt**

Create `lang/lambda/scope/query.mbt`:

```moonbit
///|
/// The declaration a reference resolves to, or None if unresolved (free).
pub fn declaration(g : ScopeGraph, ref_node : @core.NodeId) -> Decl? {
  for r in g.refs {
    if r.node_id == ref_node {
      return match r.resolution.decl {
        Some(did) => {
          let DeclId(di) = did
          Some(g.decls[di])
        }
        None => None
      }
    }
  }
  None
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: PASS for all three. If `resolve: self-reference is unbound` FAILS (the
init x resolves to def 0), the cutoff logic is wrong — fix
`containing_def_index` / `resolve`, do NOT weaken the test (the values are
hand-derived per the design spec Layer 1).

- [ ] **Step 6: Commit**

```bash
git add lang/lambda/scope/builder.mbt lang/lambda/scope/query.mbt lang/lambda/scope/graph_wbtest.mbt
git commit -m "feat(scope): Pass 3 resolve refs (sequential cutoff + negative obs) + declaration()"
```

---

## Task 5: Layer 1 — remaining hand-derived edge cases

**Files:**
- Modify: `lang/lambda/scope/graph_wbtest.mbt`

- [ ] **Step 1: Write the tests**

Add to `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
test "resolve: innermost lambda shadowing" {
  let (proj, flat_proj, registry, source_map) = build_fixture("(x) => (x) => x")
  let g = build(flat_proj, registry, source_map)
  let var_node = find_var_node(proj, "x")
  guard declaration(g, var_node) is Some(decl)
  inspect(decl.kind is LamParam(_), content="true")
}

///|
test "resolve: body binds to latest def" {
  let (proj, flat_proj, registry, source_map) = build_fixture(
    "let x = 1\nlet x = 2\nx",
  )
  let g = build(flat_proj, registry, source_map)
  let body_var = find_var_in_body(proj, "x")
  guard declaration(g, body_var) is Some(decl)
  guard decl.kind is ModuleDef(def_index~)
  inspect(def_index, content="1")
}

///|
test "resolve: earlier def cannot see later def" {
  let (proj, flat_proj, registry, source_map) = build_fixture(
    "let a = b\nlet b = 1\na",
  )
  let g = build(flat_proj, registry, source_map)
  let init_var = find_var_in_def_init(proj, 0, "b")
  inspect(declaration(g, init_var) is None, content="true")
}
```

- [ ] **Step 2: Run tests**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: PASS (Pass 3 should already handle them). If any FAIL, fix
`Builder::resolve` / `containing_def_index` — do NOT weaken a test.

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

- [ ] **Step 1: Write the failing tests**

Add to `lang/lambda/scope/graph_wbtest.mbt`:

```moonbit
///|
test "references: identity-based, shadowing-aware" {
  let (_proj, flat_proj, registry, source_map) = build_fixture(
    "let x = 1\nlet x = 2\nx",
  )
  let g = build(flat_proj, registry, source_map)
  let def1 = g.decls[1].node_id
  let def0 = g.decls[0].node_id
  inspect(references(g, def1).length() >= 1, content="true")
  inspect(references(g, def0).length(), content="0")
}

///|
test "enclosing_env: lambda params in scope" {
  let (proj, flat_proj, registry, source_map) = build_fixture("(x, y) => x")
  let g = build(flat_proj, registry, source_map)
  let var_node = find_var_node(proj, "x")
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
pub fn references(
  g : ScopeGraph,
  decl_node : @core.NodeId,
) -> Array[@core.NodeId] {
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
/// The set of names bound in scopes enclosing `node` — the FULL lexical
/// environment (lambda params AND module defs). This is a SUPERSET of the
/// existing `collect_lam_env` (which returns only lambda params); it is NOT a
/// drop-in replacement. Set semantics (membership, not order).
/// Reserved API surface; consumer migration deferred (see design spec).
pub fn enclosing_env(
  g : ScopeGraph,
  node : @core.NodeId,
) -> @immut/hashset.HashSet[String] {
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
  let mut env : @immut/hashset.HashSet[String] = @immut/hashset.new()
  let mut cur = start
  while cur is Some(sid) {
    let ScopeId(si) = sid
    let scope = g.scopes[si]
    for did in scope.decl_ids {
      let DeclId(di) = did
      env = env.add(g.decls[di].name)
    }
    cur = scope.parent
  }
  env
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/canopy/lang/lambda/scope -f graph_wbtest.mbt`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/scope/query.mbt lang/lambda/scope/graph_wbtest.mbt
git commit -m "feat(scope): reserved query API references() + enclosing_env()"
```

---

## Task 7: Generate interface + full package check

- [ ] **Step 1: Generate interface + format**

Run: `moon info && moon fmt`
Expected: `lang/lambda/scope/scope.mbti` (or `pkg.generated.mbti`) generated;
formatting applied.

- [ ] **Step 2: Review the generated interface**

Run: `git diff --stat lang/lambda/scope/` and read the generated `.mbti`. Confirm
the public surface is exactly: `ScopeGraph`, `Scope`, `Decl`, `Ref`,
`Resolution`, `DeclKind`, `ScopeId`/`DeclId`/`RefId`, `build`, `build_parent_map`,
`declaration`, `references`, `enclosing_env`. No accidental internal exposure
(`Builder` must stay `priv`).

- [ ] **Step 3: Full check + test**

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
- Create: `lang/lambda/edits/scope_equivalence_wbtest.mbt`
- Modify: `lang/lambda/edits/moon.pkg` (add scope import)
- Modify: `lang/lambda/edits/text_edit_rename.mbt:99-139` (`rename_from_var`)

The equivalence test lives in the `edits` package: the production import will be
edits→scope, and `edits` already brings `resolve_binder`, `FlatProj`,
`SourceMap`, `parse_to_proj_node`, `NodeId` into bare scope (via `using`) and
provides the `scope_test_registry` helper (`scope_wbtest.mbt:2`). Reuse those.

- [ ] **Step 1: Add the scope import to edits**

In `lang/lambda/edits/moon.pkg`, add `"dowdiness/canopy/lang/lambda/scope"` as
a new line inside the existing `import { ... }` block (default alias `@scope`).

Run: `moon check -p dowdiness/canopy/lang/lambda/edits`
Expected: no errors (import resolves; nothing uses it yet — `-2-6-29`
suppresses the unused-import warning).

- [ ] **Step 2: Write the table-driven equivalence test FIRST (old resolve_binder still live)**

Create `lang/lambda/edits/scope_equivalence_wbtest.mbt`. It covers EVERY Layer-1
binding rule, so the migration in Step 4 is proven safe across self-refs, later
defs, shadowing, and free refs (not just the two happy paths). Bare names
(`parse_to_proj_node`, `FlatProj`, `SourceMap`, `NodeId`, `scope_test_registry`,
`BindingSite`, `resolve_binder`) resolve in the `edits` package; only the new
package is qualified `@scope`.

```moonbit
///|
/// Normalize a scope-graph Decl to (tag, node_id, def_index); def_index = -1
/// for lambda params.
fn norm_decl(decl : @scope.Decl) -> (String, NodeId, Int) {
  match decl.kind {
    @scope.LamParam(lam_id~) => ("lam", lam_id, -1)
    @scope.ModuleDef(def_index~) => ("module", decl.node_id, def_index)
  }
}

///|
/// Normalize an edits BindingSite to the same shape.
fn norm_binder(b : BindingSite) -> (String, NodeId, Int) {
  match b {
    LamBinder(lam_id~) => ("lam", lam_id, -1)
    ModuleBinder(binding_node_id~, def_index~) =>
      ("module", binding_node_id, def_index)
  }
}

///|
/// One equivalence check: declaration() must agree with resolve_binder on the
/// chosen Var node. Returns true if both sides normalize to the same value
/// (including both-None).
fn agree(text : String, locate : (@core.ProjNode[@ast.Term]) -> NodeId) -> Bool raise {
  let (proj, _errs) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let sm = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(fp, registry, sm)
  let var_id = locate(proj)
  let new_site = match @scope.declaration(g, var_id) {
    Some(d) => Some(norm_decl(d))
    None => None
  }
  let old_site = match resolve_binder(var_id, var_name_of(proj, var_id), fp, registry, sm) {
    Some(b) => Some(norm_binder(b))
    None => None
  }
  new_site == old_site
}

///|
/// Look up the Var name at a NodeId (resolve_binder needs the name string).
fn var_name_of(root : @core.ProjNode[@ast.Term], id : NodeId) -> String {
  let mut out = ""
  fn walk(n : @core.ProjNode[@ast.Term]) -> Unit {
    if n.id() == id {
      match n.kind {
        @ast.Term::Var(x) => out = x
        @ast.Term::Unbound(x) => out = x
        _ => ()
      }
    }
    for c in n.children {
      walk(c)
    }
  }

  walk(root)
  out
}

///|
/// Find first Var named `name` (helper for locators).
fn find_var(root : @core.ProjNode[@ast.Term], name : String) -> NodeId {
  let mut found : NodeId? = None
  fn walk(n : @core.ProjNode[@ast.Term]) -> Unit {
    if found is Some(_) {
      return
    }
    if n.kind is @ast.Term::Var(x) && x == name {
      found = Some(n.id())
    }
    for c in n.children {
      walk(c)
    }
  }

  walk(root)
  found.unwrap()
}

///|
test "equivalence: declaration() matches resolve_binder across all binding rules" {
  // (description, source, locator)
  inspect(agree("(x) => x", root => root.children[0].id()), content="true") // lam param (locate returns NodeId, so .id())
  inspect(agree("let x = 0\nx", root => find_var(root, "x")), content="true") // module body
  inspect(agree("let x = x\nx", root => find_var(root, "x")), content="true") // self-ref (first x is init → unbound)
  inspect(agree("let x = 1\nlet x = 2\nx", root => find_var(root, "x")), content="true") // shadowing / latest
  inspect(agree("let a = b\nlet b = 1\na", root => find_var(root, "b")), content="true") // earlier can't see later (free)
  inspect(agree("(x) => (x) => x", root => find_var(root, "x")), content="true") // nested lam shadow
}
```

Note: `agree` builds FlatProj via `from_proj_node` (init-child id-shape).
Production uses the live `to_flat_proj` id-shape, but both `@scope.build` and
`resolve_binder` read `flat_proj.defs[i].3`, so equivalence holds on either; the
live path is additionally exercised by Step 5's `text_edit_rename` integration
tests. If the module case ever disagrees because the two NodeIds differ, that is
a real finding — STOP and report which NodeId each side uses (design spec: file
the bug; do not paper over).

- [ ] **Step 3: Run the equivalence test (old behavior, new graph)**

Run: `moon test -p dowdiness/canopy/lang/lambda/edits -f scope_equivalence_wbtest.mbt`
Expected: PASS. If any case FAILS, investigate against Layer 1 before changing
production code.

- [ ] **Step 4: Migrate the consumer**

Replace `rename_from_var`'s body in `lang/lambda/edits/text_edit_rename.mbt`
(lines 99-139) so the binder lookup goes through `@scope`. Keep the SAME dispatch
into `rename_lam_param` / `rename_module_binding` and the SAME error messages:

```moonbit
fn rename_from_var(
  ctx : EditContext[@ast.Term],
  var_node_id : NodeId,
  old_name : String,
  new_name : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let g = @scope.build(ctx.flat_proj, ctx.registry, ctx.source_map)
  guard @scope.declaration(g, var_node_id) is Some(decl) else {
    return Err("No binding found for variable: " + old_name)
  }
  match decl.kind {
    @scope.LamParam(lam_id~) =>
      match ctx.registry.get(lam_id) {
        Some(lam_node) =>
          rename_lam_param(ctx, lam_id, lam_node, old_name, new_name)
        None => Err("Lambda node not found in registry")
      }
    @scope.ModuleDef(def_index~) => {
      let mut module_id : NodeId? = None
      for pid, pnode in ctx.registry {
        if pnode.kind is @ast.Term::Module(_, _) {
          module_id = Some(pid)
          break
        }
      }
      match module_id {
        Some(mid) =>
          rename_module_binding(ctx, mid, def_index, old_name, new_name)
        None => Err("Module node not found in registry")
      }
    }
  }
}
```

If the bare `@scope.LamParam(..)` / `@scope.ModuleDef(..)` patterns fail to
compile (MoonBit cross-package enum-constructor matching), add
`"dowdiness/canopy/lang/lambda/scope"` already imported, then `using @scope {
type DeclKind }` to `edits/moon.pkg` and match `DeclKind::LamParam(..)` /
`DeclKind::ModuleDef(..)`. Verify the original line range — read
`text_edit_rename.mbt:99-139` before replacing.

Do NOT delete `resolve_binder` — `text_edit_refactor.mbt` and `scope_wbtest.mbt`
still use it, and the equivalence test depends on it (design spec Non-goals: only
`rename_from_var`'s binder lookup migrates in v1).

- [ ] **Step 5: Run the full edits + scope suites**

Run: `moon check && moon test -p dowdiness/canopy/lang/lambda/edits && moon test -p dowdiness/canopy/lang/lambda/scope`
Expected: all existing `text_edit*` / `scope_wbtest` tests still PASS (behavior
preserved — these exercise the live `ctx` path), plus the equivalence tests pass.

- [ ] **Step 6: Commit**

```bash
git add lang/lambda/edits/scope_equivalence_wbtest.mbt lang/lambda/edits/moon.pkg lang/lambda/edits/text_edit_rename.mbt
git commit -m "feat(scope): migrate rename_from_var binder lookup to scope graph (equivalent)"
```

---

## Task 9: Layer 2 — caimeox differential oracle (last; non-blocking)

**Files:**
- Create: `lang/lambda/scope/oracle_wbtest.mbt`
- Modify: `moon.mod.json` (add caimeox dependency) — only if integration is clean

Sequenced LAST: Layer 1 (correctness) + Layer 3 (migration) are the shipping
gates. If vendoring caimeox is heavy, ship the PoC and land this as follow-up.

- [ ] **Step 1: Assess dependency integration**

Run: `cat moon.mod.json` and inspect the `deps` block. caimeox/scope_graph is at
`https://github.com/caimeox/scope_graph` (Apache-2.0; module name
`CAIMEOX/scope_graph`). Determine whether it is mooncakes-published or must be
vendored. If neither path is clean within ~30 min, STOP and do Step 4's deferred
path. Do not force a fragile dependency.

- [ ] **Step 2: Write an INDEPENDENT adapter + one differential test (if integrated)**

Create `lang/lambda/scope/oracle_wbtest.mbt`. Write a `@ast.Term -> @lm.LmProgram`
adapter that does NOT route through `builder.mbt`/`query.mbt`, restricted to the
shared subset (Var / Lam / App / Module / let-equivalent). caimeox's API (read
`/tmp/scope_graph_probe/scope_graph/`): `build_scope_graph(program) -> ScopeGraph`,
then `ScopeGraph::resolve_ref(ref_id) -> @hashset.HashSet[Int]`. For a fixture,
resolve a chosen reference in BOTH graphs and compare the resolved def index via a
side table.

```moonbit
///|
test "oracle: caimeox agrees on let shadowing (shared subset)" {
  let (proj, flat_proj, registry, source_map) = build_fixture(
    "let x = 1\nlet x = 2\nx",
  )
  let g = build(flat_proj, registry, source_map)
  let body_var = find_var_in_body(proj, "x")
  let canopy_idx = match declaration(g, body_var) {
    Some(d) =>
      match d.kind {
        ModuleDef(def_index~) => def_index
        _ => -1
      }
    None => -2
  }
  let caimeox_idx = oracle_resolve_body_x("let x = 1\nlet x = 2\nx")
  inspect(canopy_idx == caimeox_idx, content="true")
}
```

Implement `oracle_resolve_body_x` (adapter + caimeox build/resolve) in this file
only.

- [ ] **Step 3: Apply the adjudication rule on disagreement**

If caimeox and canopy disagree on a fixture: per the design spec, Layer 1 + Layer
3 win; REMOVE the caimeox fixture from the differential set with a one-line
comment recording why (documented, not silently dropped).

- [ ] **Step 4: Run + commit (integrated) OR commit deferral note**

Integrated:

```bash
moon test -p dowdiness/canopy/lang/lambda/scope -f oracle_wbtest.mbt
git add lang/lambda/scope/oracle_wbtest.mbt moon.mod.json
git commit -m "test(scope): caimeox differential oracle on shared subset"
```

Deferred — create `lang/lambda/scope/oracle_wbtest.mbt` containing only a
top-of-file comment:

```
// Layer 2 caimeox differential oracle deferred to follow-up — see
// docs/superpowers/specs/2026-05-30-lambda-scope-graph-design.md.
// Layer 1 (graph_wbtest) + Layer 3 (scope_equivalence_wbtest) are the
// shipping gates.
```

```bash
git add lang/lambda/scope/oracle_wbtest.mbt
git commit -m "docs(scope): note Layer 2 oracle deferred to follow-up"
```

---

## Task 10: Final verification + PR prep

- [ ] **Step 1: Full workspace gate**

Run: `moon check && moon test && moon fmt && moon info`
Expected: clean across the workspace; all tests pass. (If `moon info` changes any
`.mbti`, review `git diff *.mbti` for unintended trait-bound widening per
CLAUDE.md, then commit.)

- [ ] **Step 2: Confirm the migration is real and scoped**

Run: `git diff main --stat`
Expected: only `lang/lambda/scope/*`, `lang/lambda/edits/text_edit_rename.mbt`,
`lang/lambda/edits/moon.pkg`, `lang/lambda/edits/scope_equivalence_wbtest.mbt`,
and the design/plan docs. No `moon.work` change. Confirm `resolve_binder` still
exists (`grep -n 'pub fn resolve_binder' lang/lambda/edits/scope.mbt`).

- [ ] **Step 3: Reuse-check note for the PR**

In the PR description, state: `declaration()` reproduces the existing
`BindingSite` contract; reused `@core.NodeId`, `@core.ProjNode`,
`@core.SourceMap`, `@lambda_proj.FlatProj` (no duplicate types introduced).

- [ ] **Step 4: Open the PR**

```bash
git push -u origin design/lambda-scope-graph
gh pr create --title "feat(scope): NodeId-keyed binding index for lambda (v1, rename migrated)" --body "$(cat <<'BODY'
Implements docs/superpowers/specs/2026-05-30-lambda-scope-graph-design.md.

v1: non-incremental NodeId-keyed binding index (scope/graph.mbt + builder + query).
rename_from_var binder lookup migrated to @scope.declaration() with table-driven
equivalence tests proving behavior preservation across all binding rules.
references()/enclosing_env() are reserved API surface (no v1 consumer).
Layer 2 caimeox oracle per Task 9 status.

## Reuse check
declaration() reproduces the existing BindingSite contract; reused @core.NodeId,
@core.ProjNode, @core.SourceMap, @lambda_proj.FlatProj — no duplicate types.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

---

## Self-review notes (spec coverage)

- **Spec §Architecture (3 files):** Tasks 1/3/4/6 (graph, builder, query). ✓
- **Spec §"Sequential-scope encoding" (cutoff):** Task 4 + Task 5; mirrors `resolve_binder` (Verified facts). ✓
- **Spec §"DeclKind" (BindingSite reconstruction):** Task 1 data model + Task 8 `norm_decl`. ✓
- **Spec §"Var vs Unbound":** Task 4 Pass 3 emits Ref for both. ✓
- **Spec §"visited_scopes by-product":** Task 4 `Builder::resolve` records visited. ✓
- **Spec §Testing Layer 1/2/3:** Tasks 5 / 9 / 8 (Layer 3 now table-driven over all rules). ✓
- **Spec §Non-goals (only rename, only declaration):** Task 8 migrates one call; references/enclosing_env reserved (Task 6), enclosing_env documented as superset of collect_lam_env (not replacement). ✓
- **Spec §"acyclic by construction":** relied on in Task 2 `build_parent_map` doc; no runtime cycle guard in v1 because the tree-derived parent map cannot cycle.
- **Codex review (2026-05-30) findings folded:** from_ast→`@core` (C1); `derive(Debug,Eq)`+scalar-inspect idiom (C2); table-driven equivalence (C3); enclosing_env superset comment (C4); id-shape note (C5); plus moon.pkg `import { }` format + `@lambda_proj` alias (matching `edits`).
