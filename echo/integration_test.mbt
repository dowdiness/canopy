// echo/integration_test.mbt

///|
test "integration - curry cluster" {
  let corpus = Corpus::new()
  let _ = corpus.add_post(
    "MoonBitでインクリメンタル計算のライブラリを作っている",
  )
  let _ = corpus.add_post(
    "増分計算の論文を読んだ。Salsaの設計が参考になる",
  )
  let _ = corpus.add_post("今日の晩ご飯はカレーにした")
  let _ = corpus.add_post(
    "Rustのroeywanスタイルのgreen treeをMoonBitに移植したい",
  )
  let _ = corpus.add_post("CRDTの実装でFugueMaxアルゴリズムを使う")
  let _ = corpus.add_post(
    "カレーのスパイスを新しく買った。クミンとコリアンダー",
  )
  let _ = corpus.add_post(
    "incr libraryにMemoプリミティブを追加した",
  )
  let _ = corpus.add_post("共同編集にはCRDTかOTが必要")
  // Post 2 (curry dinner) → top-1 should be Post 5 (curry spices)
  let results_2 = corpus.query_similar(2, top_n=3)
  inspect(results_2[0].0, content="5")
  // Post 5 (curry spices) → top-1 should be Post 2 (curry dinner)
  let results_5 = corpus.query_similar(5, top_n=3)
  inspect(results_5[0].0, content="2")
}

///|
test "integration - CRDT cluster" {
  let corpus = Corpus::new()
  let _ = corpus.add_post(
    "MoonBitでインクリメンタル計算のライブラリを作っている",
  )
  let _ = corpus.add_post(
    "増分計算の論文を読んだ。Salsaの設計が参考になる",
  )
  let _ = corpus.add_post("今日の晩ご飯はカレーにした")
  let _ = corpus.add_post(
    "Rustのroeywanスタイルのgreen treeをMoonBitに移植したい",
  )
  let _ = corpus.add_post("CRDTの実装でFugueMaxアルゴリズムを使う")
  let _ = corpus.add_post(
    "カレーのスパイスを新しく買った。クミンとコリアンダー",
  )
  let _ = corpus.add_post(
    "incr libraryにMemoプリミティブを追加した",
  )
  let _ = corpus.add_post("共同編集にはCRDTかOTが必要")
  // Post 4 (CRDT FugueMax) → top-1 should be Post 7 (CRDT/OT)
  let results_4 = corpus.query_similar(4, top_n=3)
  inspect(results_4[0].0, content="7")
  // Post 7 (CRDT/OT) → top-1 should be Post 4 (CRDT FugueMax)
  let results_7 = corpus.query_similar(7, top_n=3)
  inspect(results_7[0].0, content="4")
}

///|
test "integration - query_text finds curry posts" {
  let corpus = Corpus::new()
  let _ = corpus.add_post(
    "MoonBitでインクリメンタル計算のライブラリを作っている",
  )
  let _ = corpus.add_post(
    "増分計算の論文を読んだ。Salsaの設計が参考になる",
  )
  let _ = corpus.add_post("今日の晩ご飯はカレーにした")
  let _ = corpus.add_post(
    "Rustのroeywanスタイルのgreen treeをMoonBitに移植したい",
  )
  let _ = corpus.add_post("CRDTの実装でFugueMaxアルゴリズムを使う")
  let _ = corpus.add_post(
    "カレーのスパイスを新しく買った。クミンとコリアンダー",
  )
  let _ = corpus.add_post(
    "incr libraryにMemoプリミティブを追加した",
  )
  let _ = corpus.add_post("共同編集にはCRDTかOTが必要")
  let results = corpus.query_text("カレーライスが食べたい", top_n=3)
  let ids = results.map(fn(pair) { pair.0 })
  // Post 2 or 5 (curry cluster) should appear in results
  inspect(ids.contains(2) || ids.contains(5), content="true")
}

///|
test "integration - query_text finds CRDT posts" {
  let corpus = Corpus::new()
  let _ = corpus.add_post(
    "MoonBitでインクリメンタル計算のライブラリを作っている",
  )
  let _ = corpus.add_post(
    "増分計算の論文を読んだ。Salsaの設計が参考になる",
  )
  let _ = corpus.add_post("今日の晩ご飯はカレーにした")
  let _ = corpus.add_post(
    "Rustのroeywanスタイルのgreen treeをMoonBitに移植したい",
  )
  let _ = corpus.add_post("CRDTの実装でFugueMaxアルゴリズムを使う")
  let _ = corpus.add_post(
    "カレーのスパイスを新しく買った。クミンとコリアンダー",
  )
  let _ = corpus.add_post(
    "incr libraryにMemoプリミティブを追加した",
  )
  let _ = corpus.add_post("共同編集にはCRDTかOTが必要")
  let results = corpus.query_text("CRDTで共同編集", top_n=3)
  let ids = results.map(fn(pair) { pair.0 })
  inspect(ids.contains(4) || ids.contains(7), content="true")
}

///|
test "integration - duplicate posts produce zero IDF vectors" {
  let corpus = Corpus::new()
  let id0 = corpus.add_post("全く同じ文章を二回投稿する")
  let _ = corpus.add_post("全く同じ文章を二回投稿する")
  // Standard TF-IDF: when a term appears in ALL documents, IDF = ln(N/df) = ln(1) = 0
  // Both posts have identical terms with df == doc_count, so all TF-IDF weights are 0
  // → zero norm vectors → query_similar returns []
  let results = corpus.query_similar(id0, top_n=1)
  inspect(results, content="[]")
}

///|
test "integration - single char post has no similarity" {
  let corpus = Corpus::new()
  let id0 = corpus.add_post("あ")
  let _ = corpus.add_post("カレーを作った")
  // Single char produces 0 bigrams → zero vector → no similarity
  let results = corpus.query_similar(id0)
  inspect(results, content="[]")
}

///|
test "integration - query_text matches stored query_similar" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("カレーを作った")
  let _ = corpus.add_post("プログラミングの勉強")
  let _ = corpus.add_post("カレーのスパイス")
  // query_text with exact text of post 0
  let text_results = corpus.query_text("カレーを作った", top_n=3)
  let similar_results = corpus.query_similar(0, top_n=3)
  // Both should find post 2 (shares "カレ" bigram)
  let text_ids = text_results.map(fn(pair) { pair.0 })
  let similar_ids = similar_results.map(fn(pair) { pair.0 })
  inspect(text_ids.contains(2), content="true")
  inspect(similar_ids.contains(2), content="true")
}
