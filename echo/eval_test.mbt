// echo/eval_test.mbt
//
// Standard IR evaluation metrics for the TF-IDF pipeline.
// Uses cluster membership as ground truth relevance labels.
//
// Clusters: Cooking (0-4), CRDT (5-9), Incremental (10-14),
//           MoonBit (15-19), Reading (20-24), Daily life (25-29)

///|
/// Returns the cluster id (0-5) for a given post id.
fn cluster_of(post_id : Int) -> Int {
  post_id / 5
}

///|
/// Precision@K: fraction of top-K results that are relevant (same cluster as query).
fn precision_at_k(
  results : Array[(Int, Double)],
  query_id : Int,
  k : Int,
) -> Double {
  if k <= 0 || results.is_empty() {
    return 0.0
  }
  // Standard P@K divides by K, not by actual result count.
  // Fewer than K results means missing results count as irrelevant.
  let n = if k < results.length() { k } else { results.length() }
  let query_cluster = cluster_of(query_id)
  let mut relevant = 0
  for i = 0; i < n; i = i + 1 {
    if cluster_of(results[i].0) == query_cluster {
      relevant = relevant + 1
    }
  }
  relevant.to_double() / k.to_double()
}

///|
/// Reciprocal Rank: 1/rank of the first relevant result (same cluster).
///  Returns 0.0 if no relevant result found.
fn reciprocal_rank(results : Array[(Int, Double)], query_id : Int) -> Double {
  let query_cluster = cluster_of(query_id)
  for i = 0; i < results.length(); i = i + 1 {
    if cluster_of(results[i].0) == query_cluster {
      return 1.0 / (i + 1).to_double()
    }
  }
  0.0
}

///|
/// Format a Double to 2 decimal places as a string.
/// Assumes v >= 0 (metrics like P@K and MRR are in [0,1]).
fn fmt2(v : Double) -> String {
  let scaled = (v * 100.0 + 0.5).to_int()
  let whole = scaled / 100
  let frac = scaled % 100
  if frac < 10 {
    "\{whole}.0\{frac}"
  } else {
    "\{whole}.\{frac}"
  }
}

///|
test "evaluation - precision@K and MRR report" {
  let corpus = make_fixture_corpus()
  let cluster_names = [
    "Cooking    ", "CRDT       ", "Incremental", "MoonBit    ", "Reading    ", "Daily Life ",
  ]
  let k = 5
  let mut total_p_at_k = 0.0
  let mut total_mrr = 0.0
  let mut query_count = 0
  let buf = StringBuilder::new()
  buf.write_string(
    "\n=== Echo TF-IDF Evaluation (bigram, 30 posts, 6 clusters) ===\n",
  )
  buf.write_string("Cluster      | P@\{k}  | MRR   | Per-post P@\{k}\n")
  buf.write_string("------------ | ----- | ----- | -------------------------\n")
  for cluster = 0; cluster < 6; cluster = cluster + 1 {
    let start = cluster * 5
    let mut cluster_p = 0.0
    let mut cluster_mrr = 0.0
    let mut per_post = ""
    for i = start; i < start + 5; i = i + 1 {
      let results = corpus.query_similar(i, top_n=k)
      let p = precision_at_k(results, i, k)
      let rr = reciprocal_rank(results, i)
      cluster_p = cluster_p + p
      cluster_mrr = cluster_mrr + rr
      total_p_at_k = total_p_at_k + p
      total_mrr = total_mrr + rr
      query_count = query_count + 1
      if per_post.length() > 0 {
        per_post = per_post + " "
      }
      per_post = per_post + fmt2(p)
    }
    let avg_p = cluster_p / 5.0
    let avg_mrr = cluster_mrr / 5.0
    buf.write_string(
      "\{cluster_names[cluster]} | \{fmt2(avg_p)} | \{fmt2(avg_mrr)} | \{per_post}\n",
    )
  }
  let overall_p = total_p_at_k / query_count.to_double()
  let overall_mrr = total_mrr / query_count.to_double()
  buf.write_string("------------ | ----- | ----- |\n")
  buf.write_string(
    "Overall      | \{fmt2(overall_p)} | \{fmt2(overall_mrr)} |\n",
  )
  println(buf.to_string())
  // Snapshot overall metrics for regression detection
  inspect(
    fmt2(overall_p),
    content=(
      #|0.44
    ),
  )
  inspect(fmt2(overall_mrr), content="0.81")
}
