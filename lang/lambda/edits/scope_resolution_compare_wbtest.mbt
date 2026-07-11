// Shared scope-resolution comparison helpers for Lambda edit white-box tests.
//
// The live incremental memo-stack differential and fresh rebuild oracle can
// allocate different node ids. These helpers compare resolution through
// source-range keys instead of raw ids, while still requiring every resolved
// binder to be locatable through `@scope.binder_span`.

///|
/// Collect every Var reference in a node registry, keyed by a
/// pipeline-independent "start:end:name" string. Var occurrences have unique
/// source spans, so this key is injective within a pipeline; equality of the
/// two pipelines' key sets is itself an invariant (same parse → same Vars).
fn collect_var_refs(
  registry : Map[NodeId, ProjNode[@ast.Term]],
) -> Map[String, NodeId] raise {
  let refs : Map[String, NodeId] = {}
  for id, node in registry {
    if node.kind is @ast.Term::Var(name) {
      let key = "\{node.start}:\{node.end}:\{name}"
      // Injectivity guard: a collision would silently overwrite a reference
      // and hide it from the comparison.
      guard refs.get(key) is None else {
        fail("Var key \{key} is not injective within a pipeline")
      }
      refs[key] = id
    }
  }
  refs
}

///|
/// Assert the two pipelines see the same set of Var references (by range+name).
/// A divergence here would let range-matching silently skip a reference, so it
/// is pinned rather than assumed.
fn assert_same_var_refs(
  m1 : Map[String, NodeId],
  m2 : Map[String, NodeId],
) -> Unit raise {
  guard m1.length() == m2.length() else {
    fail(
      "Var-ref count differs across pipelines: \{m1.length()} vs \{m2.length()}",
    )
  }
  for k, _ in m1 {
    guard m2.get(k) is Some(_) else {
      fail("Var ref \{k} present in left pipeline but missing on right")
    }
  }
}

///|
/// Assert no two distinct Lam nodes in a registry share a source range, so the
/// range is a faithful identity for a lambda binder.
fn assert_lam_ranges_unique(
  registry : Map[NodeId, ProjNode[@ast.Term]],
) -> Unit raise {
  let seen : Map[String, NodeId] = {}
  for _, node in registry {
    if node.kind is @ast.Term::Lam(_, _) {
      let key = "\{node.start}:\{node.end}"
      guard seen.get(key) is None else {
        fail("two distinct Lam nodes share range \{key} (range not injective)")
      }
      seen[key] = node.id()
    }
  }
}

///|
/// Source ranges of a Module's LetDef binding rows, indexed by def_index.
/// Empty for a non-Module root (no module defs exist).
fn def_binding_ranges(root : ProjNode[@ast.Term]) -> Array[String] {
  match root.kind {
    Module(term_defs, _) =>
      [
        for i in 0..<term_defs.length() => {
          "\{root.children[i].start}:\{root.children[i].end}"
        }
      ]
    _ => []
  }
}

///|
/// Reduce a resolved declaration to a pipeline-independent key. Module decls
/// use (def_index, name, LetDef row source range); lambda decls use the binder
/// Lam node's source range (looked up in that pipeline's own registry) plus the
/// name. A binder absent from its registry/range array is a hard failure.
fn normalize_decl(
  decl : @scope.Decl?,
  registry : Map[NodeId, ProjNode[@ast.Term]],
  def_ranges : Array[String],
) -> String raise {
  match decl {
    None => "free"
    Some(d) =>
      match d.kind {
        ModuleDef(def_index~) => {
          guard def_index >= 0 && def_index < def_ranges.length() else {
            fail("ModuleDef def_index \{def_index} out of range")
          }
          "module:\{def_index}:\{d.name}:\{def_ranges[def_index]}"
        }
        LamParam(lam_id~) => {
          guard registry.get(lam_id) is Some(n) else {
            fail("LamParam binder absent from registry (range lookup failed)")
          }
          "lam:\{n.start}:\{n.end}:\{d.name}"
        }
      }
  }
}

///|
/// One side of a resolution-agreement comparison. Bundling the graph, registry,
/// source map, and normalized-declaration ranges prevents accidental argument
/// reordering at call sites while keeping the helper whitebox-local.
struct ResolutionSide {
  graph : @scope.ScopeGraph
  registry : Map[NodeId, ProjNode[@ast.Term]]
  source_map : SourceMap
  ranges : Array[String]
  value_label : String
  binder_label : String
}

///|
fn ResolutionSide::ResolutionSide(
  graph~ : @scope.ScopeGraph,
  registry~ : Map[NodeId, ProjNode[@ast.Term]],
  source_map~ : SourceMap,
  ranges~ : Array[String],
  value_label~ : String,
  binder_label~ : String,
) -> ResolutionSide {
  { graph, registry, source_map, ranges, value_label, binder_label }
}

///|
/// Assert two independently-built scope graphs resolve every Var reference to
/// the same pipeline-independent declaration key, and that resolved binders are
/// locatable at the same source span.
fn assert_resolution_agrees(
  left : ResolutionSide,
  right : ResolutionSide,
  context_prefix~ : String,
  binder_span_disagreement~ : String,
) -> Unit raise {
  assert_lam_ranges_unique(left.registry)
  assert_lam_ranges_unique(right.registry)
  let refs_left = collect_var_refs(left.registry)
  let refs_right = collect_var_refs(right.registry)
  assert_same_var_refs(refs_left, refs_right)
  for key, id_left in refs_left {
    let id_right = refs_right.get(key).unwrap()
    let d_left = @scope.declaration(left.graph, id_left)
    let d_right = @scope.declaration(right.graph, id_right)
    let n_left = normalize_decl(d_left, left.registry, left.ranges)
    let n_right = normalize_decl(d_right, right.registry, right.ranges)
    guard n_left == n_right else {
      fail(
        "\{context_prefix}resolution disagrees for Var \{key}: \{left.value_label}=\{n_left} \{right.value_label}=\{n_right}",
      )
    }
    if (d_left, d_right) is (Some(dd_left), Some(dd_right)) {
      let bs_left = @scope.binder_span(left.graph, dd_left, left.source_map)
      let bs_right = @scope.binder_span(right.graph, dd_right, right.source_map)
      guard bs_right is Some(_) else {
        fail(
          "\{context_prefix}\{right.binder_label}: binder not locatable via binder_span for \{key}",
        )
      }
      guard bs_left is Some(_) else {
        fail(
          "\{context_prefix}\{left.binder_label}: binder not locatable via binder_span for \{key}",
        )
      }
      guard bs_left == bs_right else {
        fail("\{context_prefix}\{binder_span_disagreement} for Var \{key}")
      }
    }
  }
}
