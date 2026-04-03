test "corpus - add single post" {
  let corpus = Corpus::new()
  let id = corpus.add_post("カレーを作った")
  inspect(id, content="0")
  inspect(corpus.posts.length(), content="1")
  inspect(corpus.posts[0].text, content="カレーを作った")
}

test "corpus - add multiple posts increments id" {
  let corpus = Corpus::new()
  let id0 = corpus.add_post("hello world")
  let id1 = corpus.add_post("world peace")
  inspect(id0, content="0")
  inspect(id1, content="1")
  inspect(corpus.posts.length(), content="2")
}

test "corpus - add empty post" {
  let corpus = Corpus::new()
  let id = corpus.add_post("")
  inspect(id, content="0")
  inspect(corpus.posts[0].tf.total, content="0")
  inspect(corpus.posts[0].vec.norm, content="0")
}

test "corpus - vectors recomputed on add" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("abcd")
  let norm_before = corpus.posts[0].vec.norm
  // Adding a second post changes IDF, so first post's vector changes
  let _ = corpus.add_post("efgh")
  let norm_after = corpus.posts[0].vec.norm
  // Norms should differ because IDF changed
  inspect(norm_before != norm_after, content="true")
}
