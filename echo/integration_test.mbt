// echo/integration_test.mbt
//
// 30 posts across 6 topic clusters:
//   Cooking (0-4), CRDT/collaborative editing (5-9),
//   Incremental computation (10-14), MoonBit/PL (15-19),
//   Reading/books (20-24), Daily life (25-29)

///|
/// 30 fixture posts across 6 clusters. Single source of truth for all evals.
let fixture_posts : Array[String] = [
  // Cooking (0-4)
  "今日の晩ご飯はカレーにした", "カレーのスパイスを新しく買った。クミンとコリアンダー",
  "週末にパスタを作る予定。トマトソースで", "スパイスカレーのレシピを試した。美味しかった",
  "鶏肉のカレーを圧力鍋で煮込んだ",
  // CRDT (5-9)
   "CRDTの実装でFugueMaxアルゴリズムを使う", "共同編集にはCRDTかOTが必要",
  "CRDTのmerge操作は可換で結合的でなければならない", "リアルタイム共同編集のレイテンシを改善したい",
  "eg-walkerアルゴリズムでCRDTの性能が大幅に向上する",
  // Incremental (10-14)
   "MoonBitでインクリメンタル計算のライブラリを作っている",
  "増分計算の論文を読んだ。Salsaの設計が参考になる", "incr libraryにMemoプリミティブを追加した",
  "インクリメンタルパーサーの再解析範囲を最小化する手法",
  "Adaptonの論文を読み直した。変更伝播のモデルが面白い",
  // MoonBit (15-19)
   "RustのrowanスタイルのGreen TreeをMoonBitに移植したい", "MoonBitのパターンマッチングが使いやすい",
  "MoonBitのトレイトシステムでShow traitを実装した", "Wasm-GCターゲットでのMoonBitのパフォーマンスを測定",
  "MoonBitのモジュールシステムとパッケージ管理を調べた",
  // Reading (20-24)
   "Design Patternsの本を読み始めた", "SICPの第4章を読み終わった。メタ循環評価器の章",
  "型システムの入門書としてTaPLがおすすめ", "Crafting Interpretersを読んでいる。Pratt parserの解説がいい",
  "新しい技術書を3冊まとめ買いした",
  // Daily life (25-29)
   "散歩中に近所の猫に会った", "コーヒー豆を新しいのに変えてみた",
  "天気がいいので公園を散歩した", "今日は早起きしてジョギングに行った",
  "近所のカフェで新しいコーヒーを飲んだ",
]

///|
/// Populates a corpus with the 30 fixture posts.
fn populate_fixtures(corpus : Corpus) -> Unit {
  for post in fixture_posts {
    let _ = corpus.add_post(post)
  }
}

///|
fn make_fixture_corpus() -> Corpus {
  let corpus = Corpus::new()
  populate_fixtures(corpus)
  corpus
}

///|
test "integration - curry cluster" {
  let corpus = make_fixture_corpus()
  // Post 0 (curry dinner) → top results should be other curry posts (1, 3, 4)
  let results_0 = corpus.query_similar(0, top_n=5)
  let ids_0 = results_0.map(fn(pair) { pair.0 })
  // At least 2 of the curry cluster should be in top-5
  let curry_count = ids_0.fold(init=0, fn(acc, id) {
    if id == 1 || id == 3 || id == 4 {
      acc + 1
    } else {
      acc
    }
  })
  inspect(curry_count >= 2, content="true")
}

///|
test "integration - CRDT cluster" {
  let corpus = make_fixture_corpus()
  // Post 5 (CRDT FugueMax) → should find other CRDT posts
  let results_5 = corpus.query_similar(5, top_n=5)
  let ids_5 = results_5.map(fn(pair) { pair.0 })
  // At least 2 CRDT posts (6, 7, 8, 9) in top-5
  let crdt_count = ids_5.fold(init=0, fn(acc, id) {
    if id == 6 || id == 7 || id == 8 || id == 9 {
      acc + 1
    } else {
      acc
    }
  })
  inspect(crdt_count >= 2, content="true")
}

///|
test "integration - MoonBit cluster" {
  let corpus = make_fixture_corpus()
  // Post 16 (MoonBit pattern matching) → should find other MoonBit posts
  let results = corpus.query_similar(16, top_n=5)
  let ids = results.map(fn(pair) { pair.0 })
  let moonbit_count = ids.fold(init=0, fn(acc, id) {
    if id == 15 || id == 17 || id == 18 || id == 19 {
      acc + 1
    } else {
      acc
    }
  })
  inspect(moonbit_count >= 2, content="true")
}

///|
test "integration - daily life cluster" {
  let corpus = make_fixture_corpus()
  // Post 25 (cat during walk) → should find other daily life posts
  let results = corpus.query_similar(25, top_n=5)
  let ids = results.map(fn(pair) { pair.0 })
  let daily_count = ids.fold(init=0, fn(acc, id) {
    if id == 26 || id == 27 || id == 28 || id == 29 {
      acc + 1
    } else {
      acc
    }
  })
  inspect(daily_count >= 1, content="true")
}

///|
test "integration - query_text finds curry posts" {
  let corpus = make_fixture_corpus()
  let results = corpus.query_text("カレーライスが食べたい", top_n=5)
  let ids = results.map(fn(pair) { pair.0 })
  // At least one curry post (0, 1, 3, 4) should appear
  let has_curry = ids.fold(init=false, fn(acc, id) {
    acc || id == 0 || id == 1 || id == 3 || id == 4
  })
  inspect(has_curry, content="true")
}

///|
test "integration - query_text finds CRDT posts" {
  let corpus = make_fixture_corpus()
  let results = corpus.query_text("CRDTで共同編集する", top_n=5)
  let ids = results.map(fn(pair) { pair.0 })
  let has_crdt = ids.fold(init=false, fn(acc, id) {
    acc || id == 5 || id == 6 || id == 7 || id == 8 || id == 9
  })
  inspect(has_crdt, content="true")
}

///|
test "integration - cross-cluster: MoonBit + incremental" {
  let corpus = make_fixture_corpus()
  // Post 10 mentions both MoonBit and incremental — should bridge clusters
  let results = corpus.query_similar(10, top_n=5)
  let ids = results.map(fn(pair) { pair.0 })
  // Should find either incremental (11-14) or MoonBit (15-19) posts
  let has_related = ids.fold(init=false, fn(acc, id) {
    acc || (id >= 11 && id <= 14) || (id >= 15 && id <= 19)
  })
  inspect(has_related, content="true")
}

///|
test "integration - coffee posts cluster across daily life" {
  let corpus = make_fixture_corpus()
  // Post 26 (new coffee beans) should find Post 29 (cafe coffee)
  let results = corpus.query_similar(26, top_n=3)
  let ids = results.map(fn(pair) { pair.0 })
  inspect(ids.contains(29), content="true")
}

///|
test "integration - duplicate posts produce zero IDF vectors" {
  let corpus = Corpus::new()
  let id0 = corpus.add_post("全く同じ文章を二回投稿する")
  let _ = corpus.add_post("全く同じ文章を二回投稿する")
  // Standard TF-IDF: IDF = ln(N/df) = ln(1) = 0 for terms in all docs
  let results = corpus.query_similar(id0, top_n=1)
  inspect(results, content="[]")
}

///|
test "integration - single char post has no similarity" {
  let corpus = Corpus::new()
  let id0 = corpus.add_post("あ")
  let _ = corpus.add_post("カレーを作った")
  let results = corpus.query_similar(id0)
  inspect(results, content="[]")
}

///|
fn make_segment_fixture_corpus() -> Corpus {
  let corpus = Corpus::new(tokenize=@tokenizer.segment)
  populate_fixtures(corpus)
  corpus
}

///|
fn make_blended_fixture_corpus() -> Corpus {
  let corpus = Corpus::new(tokenize=@tokenizer.blended)
  populate_fixtures(corpus)
  corpus
}

///|
test "integration - snapshot all cluster scores" {
  let corpus = make_fixture_corpus()
  // Snapshot full rankings for representative posts from each cluster
  // This captures the actual behavior for regression detection
  let curry = corpus.query_similar(0, top_n=5)
  inspect(
    curry.map(fn(p) { p.0 }),
    content=(
      #|[3, 4, 28, 1, 27]
    ),
  )
  let crdt = corpus.query_similar(5, top_n=5)
  inspect(
    crdt.map(fn(p) { p.0 }),
    content=(
      #|[9, 7, 6, 17, 8]
    ),
  )
  let moonbit = corpus.query_similar(16, top_n=5)
  inspect(
    moonbit.map(fn(p) { p.0 }),
    content=(
      #|[18, 17, 19, 10, 15]
    ),
  )
  let daily = corpus.query_similar(27, top_n=5)
  inspect(
    daily.map(fn(p) { p.0 }),
    content=(
      #|[25, 23, 26, 0, 24]
    ),
  )
}
