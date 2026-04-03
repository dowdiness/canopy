// echo/sparse_vec.mbt

///|
struct SparseVec {
  entries : Map[String, Double]
  norm : Double
}

///|
fn to_sparse_vec(
  tf : TermFreq,
  doc_count : Int,
  doc_freq : Map[String, Int],
) -> SparseVec {
  if tf.total == 0 {
    return { entries: Map::new(), norm: 0.0 }
  }
  let entries : Map[String, Double] = Map::new()
  let mut sum_sq = 0.0
  tf.counts.each(fn(term, count) {
    let tf_val = count.to_double() / tf.total.to_double()
    let df = match doc_freq.get(term) {
      Some(n) => n
      None => 1
    }
    let idf = @math.ln(doc_count.to_double() / df.to_double())
    let tfidf = tf_val * idf
    if tfidf > 0.0 {
      entries[term] = tfidf
      sum_sq = sum_sq + tfidf * tfidf
    }
  })
  { entries, norm: sum_sq.sqrt() }
}

///|
fn cosine_similarity(a : SparseVec, b : SparseVec) -> Double {
  if a.norm == 0.0 || b.norm == 0.0 {
    return 0.0
  }
  let mut dot = 0.0
  a.entries.each(fn(term, val_a) {
    match b.entries.get(term) {
      Some(val_b) => dot = dot + val_a * val_b
      None => ()
    }
  })
  dot / (a.norm * b.norm)
}
