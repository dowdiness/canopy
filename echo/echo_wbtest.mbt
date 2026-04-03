///|
test "term_freq - counts tokens" {
  let tf = term_freq(["ab", "cd", "ab", "ef", "ab"])
  inspect(tf.total, content="5")
  inspect(tf.counts.get("ab"), content="Some(3)")
  inspect(tf.counts.get("cd"), content="Some(1)")
  inspect(tf.counts.get("ef"), content="Some(1)")
  inspect(tf.counts.get("zz"), content="None")
}

///|
test "term_freq - empty tokens" {
  let tf = term_freq([])
  inspect(tf.total, content="0")
  inspect(tf.counts.length(), content="0")
}

///|
test "term_freq - single token" {
  let tf = term_freq(["xy"])
  inspect(tf.total, content="1")
  inspect(tf.counts.get("xy"), content="Some(1)")
}

///|
test "to_sparse_vec - basic" {
  let tf : TermFreq = { counts: { "ab": 2, "cd": 1 }, total: 3 }
  let doc_freq : Map[String, Int] = { "ab": 2, "cd": 1 }
  let vec = to_sparse_vec(tf, 4, doc_freq)
  // TF("ab") = 2/3, IDF("ab") = ln(4/2) ≈ 0.693
  // TF("cd") = 1/3, IDF("cd") = ln(4/1) ≈ 1.386
  // Verify entries exist and norm > 0
  inspect(vec.entries.length(), content="2")
  inspect(vec.norm > 0.0, content="true")
}

///|
test "to_sparse_vec - zero total returns zero vector" {
  let tf : TermFreq = { counts: Map::new(), total: 0 }
  let vec = to_sparse_vec(tf, 1, Map::new())
  inspect(vec.entries.length(), content="0")
  inspect(vec.norm, content="0")
}

///|
test "cosine_similarity - identical vectors" {
  let vec : SparseVec = {
    entries: { "a": 1.0, "b": 2.0 },
    norm: (1.0 + 4.0).sqrt(),
  }
  let sim = cosine_similarity(vec, vec)
  inspect(sim > 0.99, content="true")
}

///|
test "cosine_similarity - orthogonal vectors" {
  let a : SparseVec = { entries: { "a": 1.0 }, norm: 1.0 }
  let b : SparseVec = { entries: { "b": 1.0 }, norm: 1.0 }
  inspect(cosine_similarity(a, b), content="0")
}

///|
test "cosine_similarity - zero norm" {
  let zero : SparseVec = { entries: Map::new(), norm: 0.0 }
  let nonzero : SparseVec = { entries: { "a": 1.0 }, norm: 1.0 }
  inspect(cosine_similarity(zero, nonzero), content="0")
  inspect(cosine_similarity(nonzero, zero), content="0")
}
