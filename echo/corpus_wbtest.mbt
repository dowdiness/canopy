///|
test "corpus - add single post" {
  let corpus = Corpus::new()
  let id = corpus.add_post("カレーを作った")
  inspect(id, content="0")
  inspect(corpus.posts.length(), content="1")
  inspect(corpus.posts[0].text, content="カレーを作った")
}

///|
test "corpus - add multiple posts increments id" {
  let corpus = Corpus::new()
  let id0 = corpus.add_post("hello world")
  let id1 = corpus.add_post("world peace")
  inspect(id0, content="0")
  inspect(id1, content="1")
  inspect(corpus.posts.length(), content="2")
}

///|
test "corpus - add empty post" {
  let corpus = Corpus::new()
  let id = corpus.add_post("")
  inspect(id, content="0")
  inspect(corpus.posts[0].tf.total, content="0")
  inspect(corpus.posts[0].vec.norm, content="0")
}

///|
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

///|
test "query_text - finds similar posts" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("カレーを作った")
  let _ = corpus.add_post("プログラミングの勉強")
  let _ = corpus.add_post("カレーのスパイス")
  let results = corpus.query_text("カレーが好き")
  // Posts 0 and 2 share "カレ" bigram with query
  inspect(results.length() > 0, content="true")
  let first_id = results[0].0
  inspect(first_id == 0 || first_id == 2, content="true")
}

///|
test "query_text - empty query returns empty" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("hello")
  inspect(corpus.query_text(""), content="[]")
}

///|
test "query_text - single char query returns empty" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("hello world")
  inspect(corpus.query_text("h"), content="[]")
}

///|
test "query_text - top_n limits results" {
  let corpus = Corpus::new()
  // Use distinct bigrams so TF-IDF is non-zero
  let _ = corpus.add_post("カレーを作った")
  let _ = corpus.add_post("カレーのスパイス")
  let _ = corpus.add_post("プログラミングの勉強")
  // "カレー" bigrams appear in only 2 docs, so IDF > 0
  let results = corpus.query_text("カレーが好き", top_n=1)
  inspect(results.length(), content="1")
}

///|
test "query_text - top_n zero returns empty" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("hello")
  inspect(corpus.query_text("hello", top_n=0), content="[]")
}

///|
test "query_similar - basic" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("カレーを作った")
  let _ = corpus.add_post("プログラミングの勉強")
  let id2 = corpus.add_post("カレーのスパイス")
  let results = corpus.query_similar(id2)
  inspect(results.length() > 0, content="true")
  // Post 0 shares "カレ" bigram
  inspect(results[0].0, content="0")
}

///|
test "query_similar - invalid id returns empty" {
  let corpus = Corpus::new()
  inspect(corpus.query_similar(999), content="[]")
}

///|
test "query_similar - excludes self" {
  let corpus = Corpus::new()
  let id = corpus.add_post("hello world")
  let _ = corpus.add_post("hello moon")
  // Third post ensures shared bigrams ("he","el","ll","lo") get IDF > 0
  // (with only 2 posts, shared terms have df=N → IDF=ln(1)=0 → zero similarity)
  let _ = corpus.add_post("completely different")
  let results = corpus.query_similar(id)
  inspect(results.length() > 0, content="true")
  for result in results {
    inspect(result.0 != id, content="true")
  }
}
