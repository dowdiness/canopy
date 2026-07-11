// echo/realdata_test.mbt
//
// Evaluation on real commit messages from this repository.
// 6 clusters by conventional commit scope (15 commits each, 90 total).
// Ground truth: commits with the same scope should cluster together.

///|
/// Real commit messages grouped by scope. 15 per cluster, 6 clusters.
let commit_posts : Array[String] = [
  // editor (0-14)
  "inject eval annotations into pretty-print layout via post-processing", "wire eval memo into SyncEditor (lambda-specific)",
  "add eval memo with per-definition evaluation and tests", "add property-based tests for pretty-printer ViewNode bridge",
  "add SyncEditor::new_generic for non-FlatProj languages", "set projection_dirty in set_parser_signals — covers all edit paths",
  "add is_dirty/refresh projection boundary to SyncEditor[T]", "add generic Tier-2 tree edit methods (delete_node, commit_edit)",
  "add whitespace-keystroke benchmark + fix proj_flat label", "switch proj memos to BackdateEq/new_no_backdate for O(1) change detection",
  "parameterize SyncEditor[T] with parser factory", "two-phase remove/add and remove zero-change shortcut",
  "detect revision skew in registry/source_map patch paths", "refresh token spans in zero-change source_map fast path",
  "always repopulate all token spans in patch path",
  // ideal (15-29)
   "add eval annotations to outline tree + ML-style examples", "hoist get_text() to single call in view_node_details",
  "simplify inspector view code", "show source range, text preview, and token spans in inspector",
  "add source-preview and token-span-row CSS classes", "keyboard-driven structural navigation in outline tree",
  "add keyboard-driven structural navigation to outline tree", "document persistence — localStorage + SQLite + shareable URLs",
  "add drag handle to mobile action bottom sheet", "add entrance animation to action overlay",
  "clarify action labels, prompts, and error messages", "normalize overlay CSS to design system tokens",
  "add entrance animation to action overlay", "regenerate package-lock.json for npm ci compatibility",
  "correct prebuild:moonbit path to resolve to ideal module root",
  // crdt (30-44)
   "add TODO list for improvement proposals", "add property tests for FugueTree functionality",
  "expand formal specification with system overview and responsibility map", "add formal specification for eg-walker CRDT system",
  "integrate TextSpan for RLE with tombstone support and enhance traversal", "enhance RLE operations with batch optimizations and improved extend behavior",
  "implement versioned cursors and batch construction in RLE", "update RLE design to use causal and visible lengths",
  "introduce changelog management skill and enhance RLE error handling", "update package imports and enhance RLE documentation",
  "enhance RLE error handling and user-friendly messages", "update package imports across multiple modules",
  "update RLE dependencies and introduce new RLE structures", "update RLE structures to use tuple-based representation",
  "update MoonBit package versioning guidelines",
  // projection (45-59)
   "add EditAction[T] struct for UI-discoverable structural edits", "parameterize ProjNode[T] with TreeNode + Renderable traits",
  "add TreeNode and Renderable traits with Term impl", "add SourceMap remove_subtree, patch_subtree, make rebuild_ranges pub",
  "add populate_token_spans_for_indices for incremental token span updates", "track changed_indices in to_flat_proj_incremental",
  "split tree_editor.mbt into model, refresh, and edit files", "add TreeEditorState::has_node for drop target validation",
  "split text_edit.mbt into utils + rename modules", "remove dead stamp comparison in collapsed branch",
  "guard is_descendant_of with loaded_nodes check, clear UI state", "add tree refresh benchmarks (20/80/320/1000 defs)",
  "validate elided descendant count in can_skip_subtree", "add bench import to moon.pkg for CI compatibility",
  "add populate_token_spans_for_indices for incremental updates",
  // echo (60-74)
   "blended tokenizer (bigram+segment) — P@5=0.48, MRR=0.83", "TinySegmenter evaluation - compare against bigram baseline",
  "add tokenizer function parameter to Corpus", "TinySegmenter segment function with tests",
  "character type classification for TinySegmenter", "add weight generation script and TinySegmenter weights",
  "prevent vacuous pass in excludes-self test, add fmt2 precondition", "idiomatic MoonBit - range loops, for-in-map, unwrap_or",
  "hide Corpus fields, fix P@K metric, add deterministic tie-breaking", "extract top_n_by_score, add SparseVec::zero, improve comments",
  "add P@K and MRR evaluation metrics with 30-post benchmark", "expand fixtures from 8 to 30 posts across 6 topic clusters",
  "correct roeywan to rowan in fixture data", "add get_post_text accessor, extract fixture helper, clean warnings",
  "scaffold echo packages",
  // pretty (75-89)
   "add EvalAnnotation and EvalError to SyntaxCategory", "prefix_flat_width, annotated punctuation, pub(all) Cmd",
  "resolve CI failures (--deny-warn)", "suffix-aware Group decision and bracket Empty fix",
  "address code review findings for pretty-printer", "add educational comments to property-based tests",
  "add property-based tests for Layout engine", "fix HardLine sentinel bug and add JSON string escaping",
  "extract tagged() helper, remove module mutation", "add JSON pretty-printing with json_to_layout",
  "add PrettyLayout TermSym integration for lambda", "add render_spans for annotated output",
  "add render_string for pretty-printer", "fix CI warnings in pretty-printer", "add suffix-aware group flattening",
]

///|
fn commit_cluster_of(post_id : Int) -> Int {
  post_id / 15
}

///|
fn commit_precision_at_k(
  results : Array[(Int, Double)],
  query_id : Int,
  k : Int,
) -> Double {
  if k <= 0 || results.is_empty() {
    return 0.0
  }
  let n = if k < results.length() { k } else { results.length() }
  let query_cluster = commit_cluster_of(query_id)
  let mut relevant = 0
  for i in 0..<n {
    if commit_cluster_of(results[i].0) == query_cluster {
      relevant += 1
    }
  }
  relevant.to_double() / k.to_double()
}

///|
fn commit_reciprocal_rank(
  results : Array[(Int, Double)],
  query_id : Int,
) -> Double {
  let query_cluster = commit_cluster_of(query_id)
  for i in 0..<results.length() {
    if commit_cluster_of(results[i].0) == query_cluster {
      return 1.0 / (i + 1).to_double()
    }
  }
  0.0
}

///|
fn eval_commit_corpus(
  tokenize : (String) -> Array[String],
  label : String,
) -> (Double, Double) {
  let corpus = Corpus::new(tokenize~)
  for post in commit_posts {
    let _ = corpus.add_post(post)
  }
  let cluster_names = [
    "editor     ", "ideal      ", "crdt       ", "projection ", "echo       ", "pretty     ",
  ]
  let k = 5
  let mut total_p = 0.0
  let mut total_mrr = 0.0
  let mut count = 0
  let buf = StringBuilder::new()
  buf.write_string(
    "\n=== Commit Messages Eval (\{label}, 90 posts, 6 scopes) ===\n",
  )
  buf.write_string("Scope        | P@\{k}  | MRR\n")
  buf.write_string("------------ | ----- | -----\n")
  for cluster in 0..<6 {
    let start = cluster * 15
    let mut cp = 0.0
    let mut cmrr = 0.0
    for i in start..<(start + 15) {
      let results = corpus.query_similar(i, top_n=k)
      let p = commit_precision_at_k(results, i, k)
      let rr = commit_reciprocal_rank(results, i)
      cp += p
      cmrr += rr
      total_p += p
      total_mrr += rr
      count += 1
    }
    buf.write_string(
      "\{cluster_names[cluster]} | \{fmt2(cp / 15.0)} | \{fmt2(cmrr / 15.0)}\n",
    )
  }
  let overall_p = total_p / count.to_double()
  let overall_mrr = total_mrr / count.to_double()
  buf.write_string("------------ | ----- | -----\n")
  buf.write_string("Overall      | \{fmt2(overall_p)} | \{fmt2(overall_mrr)}\n")
  println(buf.to_string())
  (overall_p, overall_mrr)
}

///|
test "realdata - commit messages three-way comparison" {
  let (bp, bm) = eval_commit_corpus(@tokenizer.bigram, "bigram")
  let (sp, sm) = eval_commit_corpus(@tokenizer.segment, "TinySegmenter")
  let (lp, lm) = eval_commit_corpus(@tokenizer.blended, "blended")
  // Print summary
  println(
    "\n=== Summary ===\nbigram:        P@5=\{fmt2(bp)}, MRR=\{fmt2(bm)}\nTinySegmenter: P@5=\{fmt2(sp)}, MRR=\{fmt2(sm)}\nblended:       P@5=\{fmt2(lp)}, MRR=\{fmt2(lm)}\n",
  )
  // Snapshot for regression
  inspect(
    fmt2(bp),
    content=(
      #|0.39
    ),
  )
  inspect(
    fmt2(sp),
    content=(
      #|0.43
    ),
  )
  inspect(
    fmt2(lp),
    content=(
      #|0.43
    ),
  )
}
