///|
priv struct SparseVec {
  entries : Map[String, Double]
  norm : Double
}

///|
fn SparseVec::zero() -> SparseVec {
  { entries: Map::new(), norm: 0.0 }
}

///|
/// Converts term frequencies into a TF-IDF weighted sparse vector.
/// Uses standard TF-IDF: weight = (count/total) * ln(doc_count/df).
/// Terms with zero or negative weight (df >= doc_count) are excluded
/// to maintain sparsity — they carry no discriminative signal.
fn to_sparse_vec(
  tf : TermFreq,
  doc_count : Int,
  doc_freq : Map[String, Int],
) -> SparseVec {
  if tf.total == 0 {
    return SparseVec::zero()
  }
  let entries : Map[String, Double] = Map::new()
  let mut sum_sq = 0.0
  for term, count in tf.counts {
    let tf_val = count.to_double() / tf.total.to_double()
    let df = doc_freq.get(term).unwrap_or(1)
    let idf = @math.ln(doc_count.to_double() / df.to_double())
    let tfidf = tf_val * idf
    if tfidf > 0.0 {
      entries[term] = tfidf
      sum_sq = sum_sq + tfidf * tfidf
    }
  }
  { entries, norm: sum_sq.sqrt() }
}

///|
/// Cosine similarity: dot(a,b) / (‖a‖ × ‖b‖).
/// Returns 0.0 when either vector has zero norm (no shared signal).
fn cosine_similarity(a : SparseVec, b : SparseVec) -> Double {
  if a.norm == 0.0 || b.norm == 0.0 {
    return 0.0
  }
  let mut dot = 0.0
  for term, val_a in a.entries {
    match b.entries.get(term) {
      Some(val_b) => dot = dot + val_a * val_b
      None => ()
    }
  }
  dot / (a.norm * b.norm)
}

///|
/// Sort by score descending, break ties by ascending post ID for determinism.
fn top_n_by_score(
  scores : Array[(Int, Double)],
  top_n : Int,
) -> Array[(Int, Double)] {
  scores.sort_by(fn(a, b) {
    let cmp = b.1.compare(a.1)
    if cmp != 0 {
      cmp
    } else {
      a.0.compare(b.0)
    }
  })
  let n = if top_n < scores.length() { top_n } else { scores.length() }
  Array::makei(n, fn(i) { scores[i] })
}
