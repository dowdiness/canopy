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
  let post : Post = {
    id,
    text,
    tf,
    vec: { entries: Map::new(), norm: 0.0 },
  }
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
