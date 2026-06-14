# Teach `edits/` resolvers about nested-block scopes (RFA Step 1 follow-up)

Closes the remaining root-relative blind spot in docs/TODO.md §20 for
inline / extract / binding ops. RFA Step 1 (#636) made the scope-graph builder
model nested-block (`Module`) scopes; #645 taught rename. This does the same for
the remaining `edits/` resolvers, **reusing the builder's per-(node,scope) cutoff
model** rather than adding a fourth resolver.

## Two independent unsoundnesses

**A — def lookup (inline).** `compute_inline_definition` resolves the block-aware
`decl : ModuleDef(def_index)` via `@scope.declaration`, then reads
`module_projection.defs[def_index]` (ROOT defs only). For a block-local def this
returns the root def at that index (or out-of-bounds when the block has more defs
than root). `module_def_references(g, def_index)` likewise matches the *first*
decl at a shared index — root wins.

**B — capture analysis (inline + extract).** `def_cutoff_at_node` +
`declaration_id_for_name_from_scope` apply ONE root-relative `Int` cutoff to every
module scope on the parent chain. Nested blocks each carry their own sequential
cutoff (the builder's `node_cutoffs : Map[NodeId, Map[ScopeId, Int]]`), so a free
var in the inlined init is resolved with the wrong cutoff at a nested use site.
This is a parallel re-implementation of `Builder::resolve`.

Pinned by two failing wbtests in `text_edit_nested_block_wbtest.mbt`.

## Invariants established during orientation (verified, not assumed)

- For ANY `ModuleDef` decl (root or nested), `decl.node_id` is the **LetDef
  projection node**: root via `def.3`, nested via `node.children[i].id()` from
  `module_node_from_defs`. `registry.get(decl.node_id).children[0]` is the init.
- The synthesized tuple `(decl.name, letdef.children[0], letdef.start,
  decl.node_id)` is byte-identical to `module_projection.defs[i]` for a root decl
  — same extraction `from_proj_node` performs (including its legacy
  non-LetDef-child fallback: then init = the node itself, start/id = the node's).
  So ONE unified path replaces the root path too, guarded by existing root tests.
- Binding ops (delete/duplicate/move-up/move-down/InlineAllUsages) enter via
  `find_def_index`, which returns `Err` for a block-local binder (unique node id,
  no false match) → **incapable, not unsound**. Only `compute_inline_definition`
  emits wrong edits. Extract's capture query is unsound via Problem B.

## Design

### Problem A — thread the block-aware `decl` (mirror #645)

1. New edits-local helper, single unified path (no root/nested branch at the call
   site — forbidden by conventions):
   `fn def_view_from_decl(registry, decl) -> (String, ProjNode[@ast.Term], Int, NodeId)?`
   — reads the LetDef node at `decl.node_id`, extracts init child (with the same
   legacy fallback as `from_proj_node`), returns the tuple shape the existing
   text helpers (`get_binding_text_range`, `binding_inline_text`,
   `binding_delete_range`, `binding_rewrite_source`) already consume.
2. `compute_inline_definition`: keep `@scope.declaration(g, node_id)`; for
   `ModuleDef(_)` thread `decl` → `def_view_from_decl` for the tuple, and use
   `@scope.references(g, decl.id)` for the sole-usage count. Drop the `def_index`
   read.
3. `compute_inline_all_usages` + the four binding ops: resolve `binding_node_id`
   to its decl via `g.decls.find_first(d.node_id == id && ModuleDef)` (the #645
   `rename_binding_by_id` pattern), then `def_view_from_decl`. This makes them
   block-capable (capability extension riding on the same mechanism).
   - Move-up/move-down need same-scope SIBLINGS, not `defs[index±1]`: select the
     sibling decls in `decl.scope` ordered by `def_index`, take the neighbour.
     (If sibling selection proves materially larger than the soundness core, it
     may be split to a follow-up with a NAMED boundary — decided at impl time, not
     silently.)
4. Delete `find_def_index`-as-root-only and `module_def_references` once unused.

### Problem B — expose the builder's per-node resolution

1. `@scope` graph.mbt: add `node_scope : Map[NodeId, ScopeId]` and
   `node_cutoffs : Map[NodeId, Map[ScopeId, Int]]` to `ScopeGraph`; persist both
   in `build`. Update builder.mbt's "transient … never stored" comment — that was
   a choice, now retired because hypothetical-position queries need it.
2. Factor `Builder::resolve`'s gating (ModuleDef by cutoff, LamParam always) into
   a shared free function over `(scopes, decls, start_scope, cutoffs, name)`,
   called by both `pass3` and the public query — **one resolver, not a retyped
   copy**.
3. Add `pub fn resolve_name_at(g, node_id, name) -> Decl?`: look up
   `g.node_scope[node_id]` + `g.node_cutoffs[node_id]`, run the shared resolver,
   map `DeclId → Decl`. `None` when `node_id` was not walked (absent from
   `node_scope`). Storing `node_scope` for EVERY walked node makes this total even
   when the target is a non-ref/non-decl node (extract's body target) — the
   current `scope_id_for_node` can't see those.
4. edits/scope.mbt: replace `declaration_id_for_name_at_node` with
   `@scope.resolve_name_at(g, target_node_id, name)`. Delete `def_cutoff_at_node`,
   `declaration_id_for_name_from_scope`, and `root_scope_id` / `scope_id_for_node`
   once unused.

### Problem B — two correctness revisions (Codex design review)

- **Extract "module end" target (HIGH).** Do NOT derive the target from
  `module_projection.final_expr`: `from_proj_node` maps a synthetic root `Unit`
  body to `None`, so a `None`/absent body would make `resolve_name_at` no-op and
  silently SKIP the capture check (e.g. extracting `v` from `let a = v\nlet v = 1`
  would miss the rebind to root `v`). Instead add a dedicated
  `pub fn resolve_at_module_root_end(g, name) -> Decl?` that resolves in the ROOT
  scope (parent `None`) with cutoff = count of `ModuleDef` decls in that scope
  (all root defs visible). Total, no body-node dependency. `compute_extract_to_let`
  inserts the new `let` at root, so root-end resolution is the matching target.
- **Occurrence filter (MEDIUM).** `free_name_would_rebind_to` collects `Var(name)`
  occurrences via `collect_var_usages`, which stops at lambda shadowing but NOT at
  nested-`Module` shadowing — so for init `a + { let a = 1\n  a }` it visits the
  block-local `a` and falsely rejects. Fix: only occurrences FREE in the init can
  rebind. An occurrence is internally bound iff its resolved decl's binder node is
  a structural descendant of the init node. So: compare `@scope.declaration(g,
  occurrence)` against the target resolution ONLY when the occurrence's decl
  `node_id` is NOT in the init subtree (collect the subtree's node ids once); an
  unbound occurrence (`None`) rebinds iff the target binds it. This subsumes both
  lambda and block shadowing uniformly. (`free_vars` already computes the free
  NAME set correctly via sequential Module scoping — this fixes only the
  per-occurrence enumeration.)

## Tests

- A, B: the two pinned inline wbtests (must pass; B must remain non-vacuous — after
  A is fixed it fails via spurious capture REJECTION until B is fixed).
- Extract: add a wbtest extracting an expression inside a block whose free var is
  block-local — sound behavior is to REJECT extraction to the root module (the var
  would become unbound), verifying the capture query sees the rebind.
- Binding ops: add a delete/duplicate wbtest on a block-local binder (now capable).
- Regression: full `edits/` + `scope/` suites stay green (180 baseline).

## Non-goals

- No 4th resolver; no `module_projection`-root indexing left in inline.
- Block-local extract *placement* (inserting the new `let` into the block instead
  of root) is a feature, not this soundness fix — out of scope.
- Incremental layer reading `node_cutoffs` — already future work in the design spec.
