///|
struct Post {
  id : Int
  text : String
  tf : TermFreq
  mut vec : SparseVec
}

///|
pub(all) struct Corpus {
  priv mut next_id : Int
  priv doc_freq : Map[String, Int]
  priv posts : Array[Post]
}

///|
pub fn Corpus::new() -> Corpus {
  { next_id: 0, doc_freq: Map::new(), posts: [] }
}

///|
pub fn Corpus::get_post_text(self : Corpus, post_id : Int) -> String? {
  for post in self.posts {
    if post.id == post_id {
      return Some(post.text)
    }
  }
  None
}

///|
/// Tokenizes text, stores term frequency, updates corpus IDF, and
/// recomputes all vectors. Full recompute is necessary because IDF
/// changes for every term in the new post, affecting all existing vectors.
pub fn Corpus::add_post(self : Corpus, text : String) -> Int {
  let id = self.next_id
  self.next_id += 1
  let tokens = @tokenizer.bigram(text)
  let tf = term_freq(tokens)
  for term, _ in tf.counts {
    self.doc_freq[term] = self.doc_freq.get(term).unwrap_or(0) + 1
  }
  let post : Post = { id, text, tf, vec: SparseVec::zero() }
  self.posts.push(post)
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
/// Primary query API: find posts similar to arbitrary text without storing it.
/// The query vector uses the corpus's current IDF table.
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
  let scores : Array[(Int, Double)] = Array::new(capacity=self.posts.length())
  for post in self.posts {
    let sim = cosine_similarity(query_vec, post.vec)
    if sim > 0.0 {
      scores.push((post.id, sim))
    }
  }
  top_n_by_score(scores, top_n)
}

///|
/// Find posts similar to an already-stored post. Self is excluded from results.
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
      let scores : Array[(Int, Double)] = Array::new(
        capacity=self.posts.length(),
      )
      for post in self.posts {
        if post.id != post_id {
          let sim = cosine_similarity(vec, post.vec)
          if sim > 0.0 {
            scores.push((post.id, sim))
          }
        }
      }
      top_n_by_score(scores, top_n)
    }
  }
}
