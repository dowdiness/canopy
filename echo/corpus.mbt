///|
struct Post {
  id : Int
  text : String
  tf : TermFreq
  mut vec : SparseVec
}

///|
pub struct Corpus {
  mut next_id : Int
  doc_freq : Map[String, Int]
  posts : Array[Post]
}

///|
pub fn Corpus::new() -> Corpus {
  { next_id: 0, doc_freq: Map::new(), posts: [] }
}

///|
pub fn Corpus::add_post(self : Corpus, text : String) -> Int {
  let id = self.next_id
  self.next_id = self.next_id + 1
  // Tokenize and compute term frequency
  let tokens = @tokenizer.bigram(text)
  let tf = term_freq(tokens)
  // Update document frequency (each unique term in tf.counts)
  tf.counts.each(fn(term, _count) {
    let df = match self.doc_freq.get(term) {
      Some(n) => n
      None => 0
    }
    self.doc_freq[term] = df + 1
  })
  // Add post with placeholder vector
  let post : Post = { id, text, tf, vec: { entries: Map::new(), norm: 0.0 } }
  self.posts.push(post)
  // Recompute all vectors (IDF changed)
  self.recompute_vectors()
  id
}

///|
fn Corpus::recompute_vectors(self : Corpus) -> Unit {
  let doc_count = self.posts.length()
  for post in self.posts {
    post.vec = to_sparse_vec(post.tf, doc_count, self.doc_freq)
  }
}

///|
pub fn Corpus::query_text(
  self : Corpus,
  text : String,
  top_n? : Int = 5,
) -> Array[(Int, Double)] {
  if top_n <= 0 {
    return []
  }
  let tokens = @tokenizer.bigram(text)
  let tf = term_freq(tokens)
  if tf.total == 0 {
    return []
  }
  let query_vec = to_sparse_vec(tf, self.posts.length(), self.doc_freq)
  if query_vec.norm == 0.0 {
    return []
  }
  let scores : Array[(Int, Double)] = []
  for post in self.posts {
    let sim = cosine_similarity(query_vec, post.vec)
    if sim > 0.0 {
      scores.push((post.id, sim))
    }
  }
  // Sort descending by score
  scores.sort_by(fn(a, b) { b.1.compare(a.1) })
  // Take top_n
  let n = if top_n < scores.length() { top_n } else { scores.length() }
  Array::makei(n, fn(i) { scores[i] })
}

///|
pub fn Corpus::query_similar(
  self : Corpus,
  post_id : Int,
  top_n? : Int = 5,
) -> Array[(Int, Double)] {
  if top_n <= 0 {
    return []
  }
  let mut target_vec : SparseVec? = None
  for post in self.posts {
    if post.id == post_id {
      target_vec = Some(post.vec)
      break
    }
  }
  match target_vec {
    None => []
    Some(vec) => {
      if vec.norm == 0.0 {
        return []
      }
      let scores : Array[(Int, Double)] = []
      for post in self.posts {
        if post.id != post_id {
          let sim = cosine_similarity(vec, post.vec)
          if sim > 0.0 {
            scores.push((post.id, sim))
          }
        }
      }
      scores.sort_by(fn(a, b) { b.1.compare(a.1) })
      let n = if top_n < scores.length() { top_n } else { scores.length() }
      Array::makei(n, fn(i) { scores[i] })
    }
  }
}
