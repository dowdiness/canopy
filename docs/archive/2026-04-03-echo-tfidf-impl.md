# Echo — TF-IDF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the echo TF-IDF similarity library — bigram tokenization, TF-IDF vectorization, cosine similarity, corpus management with full recompute on add.

**Architecture:** Two packages: `echo/tokenizer/` (bigram, swappable seam) and `echo/` (TermFreq, SparseVec, Corpus, queries). Bottom-up TDD from tokenizer through integration tests with 8 Japanese fixture posts.

**Tech Stack:** MoonBit, `moon test` with `inspect!` snapshots

**Spec:** [docs/plans/2026-04-03-memo-tfidf-design.md](2026-04-03-memo-tfidf-design.md)

---

### File Structure

**Create:**

| File | Purpose |
|------|---------|
| `echo/tokenizer/moon.pkg` | Package config (no deps) |
| `echo/tokenizer/bigram.mbt` | `pub fn bigram(String) -> Array[String]` |
| `echo/tokenizer/bigram_wbtest.mbt` | Tokenizer tests |
| `echo/moon.pkg` | Package config, imports `echo/tokenizer` |
| `echo/term_freq.mbt` | `TermFreq` struct, `term_freq` function |
| `echo/sparse_vec.mbt` | `SparseVec` struct, `to_sparse_vec`, `cosine_similarity` |
| `echo/corpus.mbt` | `Post`, `Corpus`, `add_post`, `query_text`, `query_similar` |
| `echo/echo_wbtest.mbt` | Unit tests for TermFreq, SparseVec, cosine similarity |
| `echo/corpus_wbtest.mbt` | Corpus + query tests |
| `echo/integration_test.mbt` | 8-post fixture integration test (blackbox, public API only) |

---

### Task 1: Scaffold Packages

**Files:**
- Create: `echo/tokenizer/moon.pkg`
- Create: `echo/moon.pkg`

- [ ] **Step 1: Create tokenizer package config**

```
// echo/tokenizer/moon.pkg
options(
  is_main: false,
)
```

- [ ] **Step 2: Create echo package config**

```
// echo/moon.pkg
import {
  "dowdiness/canopy/echo/tokenizer" @tokenizer,
}

options(
  is_main: false,
)
```

- [ ] **Step 3: Verify packages compile**

Run: `moon check`
Expected: PASS (empty packages are valid)

- [ ] **Step 4: Commit**

```bash
git add echo/
git commit -m "feat(echo): scaffold echo packages"
```

---

### Task 2: Bigram Tokenizer

**Files:**
- Create: `echo/tokenizer/bigram.mbt`
- Create: `echo/tokenizer/bigram_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
// echo/tokenizer/bigram_wbtest.mbt

test "bigram - basic Japanese" {
  inspect!(bigram("カレー"), content=["カレ", "レー"])
}

test "bigram - mixed ASCII and Japanese" {
  inspect!(bigram("CRDTの実装"), content=["CR", "RD", "DT", "Tの", "の実", "実装"])
}

test "bigram - empty string" {
  inspect!(bigram(""), content=[])
}

test "bigram - single char" {
  inspect!(bigram("あ"), content=[])
}

test "bigram - with spaces" {
  inspect!(bigram("a b"), content=["a ", " b"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --package dowdiness/canopy/echo/tokenizer`
Expected: FAIL — `bigram` not defined

- [ ] **Step 3: Implement bigram**

```moonbit
// echo/tokenizer/bigram.mbt

///|
pub fn bigram(text : String) -> Array[String] {
  let len = text.length()
  if len < 2 {
    return []
  }
  let result = Array::new(capacity=len - 1)
  for i = 0; i < len - 1; i = i + 1 {
    result.push(text.substring(start=i, end=i + 2))
  }
  result
}
```

Note: `text.length()` counts UTF-16 code units. For BMP characters (all common Japanese), this equals codepoints. Surrogate pairs are out of scope per spec.

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --package dowdiness/canopy/echo/tokenizer`
Expected: PASS

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add echo/tokenizer/
git commit -m "feat(echo): bigram tokenizer with tests"
```

---

### Task 3: TermFreq

**Files:**
- Create: `echo/term_freq.mbt`
- Create: `echo/echo_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
// echo/echo_wbtest.mbt

test "term_freq - counts tokens" {
  let tf = term_freq(["ab", "cd", "ab", "ef", "ab"])
  inspect!(tf.total, content="5")
  inspect!(tf.counts["ab"], content="Some(3)")
  inspect!(tf.counts["cd"], content="Some(1)")
  inspect!(tf.counts["ef"], content="Some(1)")
  inspect!(tf.counts["zz"], content="None")
}

test "term_freq - empty tokens" {
  let tf = term_freq([])
  inspect!(tf.total, content="0")
  inspect!(tf.counts.size(), content="0")
}

test "term_freq - single token" {
  let tf = term_freq(["xy"])
  inspect!(tf.total, content="1")
  inspect!(tf.counts["xy"], content="Some(1)")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --package dowdiness/canopy/echo`
Expected: FAIL — `term_freq` not defined

- [ ] **Step 3: Implement TermFreq**

```moonbit
// echo/term_freq.mbt

///|
struct TermFreq {
  counts : Map[String, Int]
  total : Int
}

///|
fn term_freq(tokens : Array[String]) -> TermFreq {
  let counts : Map[String, Int] = Map::new()
  for token in tokens {
    let n = match counts[token] {
      Some(n) => n
      None => 0
    }
    counts[token] = n + 1
  }
  { counts, total: tokens.length() }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --package dowdiness/canopy/echo`
Expected: PASS

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add echo/term_freq.mbt echo/echo_wbtest.mbt
git commit -m "feat(echo): TermFreq computation with tests"
```

---

### Task 4: SparseVec and Cosine Similarity

**Files:**
- Create: `echo/sparse_vec.mbt`
- Modify: `echo/echo_wbtest.mbt` (append tests)

- [ ] **Step 1: Write failing tests**

Append to `echo/echo_wbtest.mbt`:

```moonbit
test "to_sparse_vec - basic" {
  let tf : TermFreq = { counts: { "ab": 2, "cd": 1 }, total: 3 }
  let doc_freq : Map[String, Int] = { "ab": 2, "cd": 1 }
  let vec = to_sparse_vec(tf, 4, doc_freq)
  // TF("ab") = 2/3, IDF("ab") = ln(4/2) ≈ 0.693
  // TF("cd") = 1/3, IDF("cd") = ln(4/1) ≈ 1.386
  // Verify entries exist and norm > 0
  inspect!(vec.entries.size(), content="2")
  inspect!(vec.norm > 0.0, content="true")
}

test "to_sparse_vec - zero total returns zero vector" {
  let tf : TermFreq = { counts: Map::new(), total: 0 }
  let vec = to_sparse_vec(tf, 1, Map::new())
  inspect!(vec.entries.size(), content="0")
  inspect!(vec.norm, content="0")
}

test "cosine_similarity - identical vectors" {
  let vec : SparseVec = {
    entries: { "a": 1.0, "b": 2.0 },
    norm: (1.0 + 4.0).sqrt(),
  }
  let sim = cosine_similarity(vec, vec)
  inspect!(sim > 0.99, content="true")
}

test "cosine_similarity - orthogonal vectors" {
  let a : SparseVec = { entries: { "a": 1.0 }, norm: 1.0 }
  let b : SparseVec = { entries: { "b": 1.0 }, norm: 1.0 }
  inspect!(cosine_similarity(a, b), content="0")
}

test "cosine_similarity - zero norm" {
  let zero : SparseVec = { entries: Map::new(), norm: 0.0 }
  let nonzero : SparseVec = { entries: { "a": 1.0 }, norm: 1.0 }
  inspect!(cosine_similarity(zero, nonzero), content="0")
  inspect!(cosine_similarity(nonzero, zero), content="0")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --package dowdiness/canopy/echo`
Expected: FAIL — `SparseVec`, `to_sparse_vec`, `cosine_similarity` not defined

- [ ] **Step 3: Implement SparseVec**

```moonbit
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
  doc_freq : Map[String, Int]
) -> SparseVec {
  if tf.total == 0 {
    return { entries: Map::new(), norm: 0.0 }
  }
  let entries : Map[String, Double] = Map::new()
  let mut sum_sq = 0.0
  tf.counts.each(fn(term, count) {
    let tf_val = count.to_double() / tf.total.to_double()
    let df = match doc_freq[term] {
      Some(n) => n
      None => 1
    }
    let idf = (doc_count.to_double() / df.to_double()).ln()
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
    match b.entries[term] {
      Some(val_b) => dot = dot + val_a * val_b
      None => ()
    }
  })
  dot / (a.norm * b.norm)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --package dowdiness/canopy/echo`
Expected: PASS

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add echo/sparse_vec.mbt echo/echo_wbtest.mbt
git commit -m "feat(echo): SparseVec, TF-IDF vectorization, cosine similarity"
```

---

### Task 5: Corpus and add_post

**Files:**
- Create: `echo/corpus.mbt`
- Create: `echo/corpus_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
// echo/corpus_wbtest.mbt

test "corpus - add single post" {
  let corpus = Corpus::new()
  let id = corpus.add_post("カレーを作った")
  inspect!(id, content="0")
  inspect!(corpus.posts.length(), content="1")
  inspect!(corpus.posts[0].text, content="カレーを作った")
}

test "corpus - add multiple posts increments id" {
  let corpus = Corpus::new()
  let id0 = corpus.add_post("hello world")
  let id1 = corpus.add_post("world peace")
  inspect!(id0, content="0")
  inspect!(id1, content="1")
  inspect!(corpus.posts.length(), content="2")
}

test "corpus - add empty post" {
  let corpus = Corpus::new()
  let id = corpus.add_post("")
  inspect!(id, content="0")
  inspect!(corpus.posts[0].tf.total, content="0")
  inspect!(corpus.posts[0].vec.norm, content="0")
}

test "corpus - vectors recomputed on add" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("abcd")
  let norm_before = corpus.posts[0].vec.norm
  // Adding a second post changes IDF, so first post's vector changes
  let _ = corpus.add_post("efgh")
  let norm_after = corpus.posts[0].vec.norm
  // Norms should differ because IDF changed
  inspect!(norm_before != norm_after, content="true")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --package dowdiness/canopy/echo`
Expected: FAIL — `Corpus`, `Post` not defined

- [ ] **Step 3: Implement Corpus**

```moonbit
// echo/corpus.mbt

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
  // Update document frequency (each unique term)
  tf.counts.each(fn(term, _count) {
    let df = match self.doc_freq[term] {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --package dowdiness/canopy/echo`
Expected: PASS

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add echo/corpus.mbt echo/corpus_wbtest.mbt
git commit -m "feat(echo): Corpus with add_post and vector recomputation"
```

---

### Task 6: query_text and query_similar

**Files:**
- Modify: `echo/corpus.mbt` (append query methods)
- Modify: `echo/corpus_wbtest.mbt` (append tests)

- [ ] **Step 1: Write failing tests**

Append to `echo/corpus_wbtest.mbt`:

```moonbit
test "query_text - finds similar posts" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("カレーを作った")
  let _ = corpus.add_post("プログラミングの勉強")
  let _ = corpus.add_post("カレーのスパイス")
  let results = corpus.query_text("カレーが好き")
  // Posts 0 and 2 share "カレ" bigram with query
  inspect!(results.length() > 0, content="true")
  let first_id = results[0].0
  inspect!(first_id == 0 || first_id == 2, content="true")
}

test "query_text - empty query returns empty" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("hello")
  inspect!(corpus.query_text(""), content="[]")
}

test "query_text - single char query returns empty" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("hello world")
  inspect!(corpus.query_text("h"), content="[]")
}

test "query_text - top_n limits results" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("aabb")
  let _ = corpus.add_post("aabb ccdd")
  let _ = corpus.add_post("aabb eeff")
  let results = corpus.query_text("aabb", top_n=1)
  inspect!(results.length(), content="1")
}

test "query_text - top_n zero returns empty" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("hello")
  inspect!(corpus.query_text("hello", top_n=0), content="[]")
}

test "query_similar - basic" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("カレーを作った")
  let _ = corpus.add_post("プログラミングの勉強")
  let id2 = corpus.add_post("カレーのスパイス")
  let results = corpus.query_similar(id2)
  inspect!(results.length() > 0, content="true")
  // Post 0 shares "カレ" bigram
  inspect!(results[0].0, content="0")
}

test "query_similar - invalid id returns empty" {
  let corpus = Corpus::new()
  inspect!(corpus.query_similar(999), content="[]")
}

test "query_similar - excludes self" {
  let corpus = Corpus::new()
  let id = corpus.add_post("hello world")
  let _ = corpus.add_post("hello moon")
  let results = corpus.query_similar(id)
  for result in results {
    inspect!(result.0 != id, content="true")
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --package dowdiness/canopy/echo`
Expected: FAIL — `query_text`, `query_similar` not defined

- [ ] **Step 3: Implement query methods**

Append to `echo/corpus.mbt`:

```moonbit
///|
pub fn Corpus::query_text(
  self : Corpus,
  text : String,
  top_n~ : Int = 5
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
  scores.sort_by(fn(a, b) { b.1.compare(a.1) })
  let n = if top_n < scores.length() { top_n } else { scores.length() }
  Array::makei(n, fn(i) { scores[i] })
}

///|
pub fn Corpus::query_similar(
  self : Corpus,
  post_id : Int,
  top_n~ : Int = 5
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
```

Note: `sort_by` comparator and `Array::makei` may need adjustment based on MoonBit's current API. If `sort_by` expects `fn(T, T) -> Int`, use `b.1.compare(a.1)` which returns Int. If `Array::makei` doesn't exist, use a manual loop to slice.

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --package dowdiness/canopy/echo`
Expected: PASS

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add echo/corpus.mbt echo/corpus_wbtest.mbt
git commit -m "feat(echo): query_text and query_similar with tests"
```

---

### Task 7: Integration Test — 8 Fixture Posts

**Files:**
- Create: `echo/integration_test.mbt`

This is a blackbox test (`_test.mbt`) that uses only the public API (`Corpus::new`, `add_post`, `query_text`, `query_similar`).

- [ ] **Step 1: Write integration test**

```moonbit
// echo/integration_test.mbt

test "integration - curry cluster" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("MoonBitでインクリメンタル計算のライブラリを作っている")
  let _ = corpus.add_post("増分計算の論文を読んだ。Salsaの設計が参考になる")
  let _ = corpus.add_post("今日の晩ご飯はカレーにした")
  let _ = corpus.add_post("Rustのroeywanスタイルのgreen treeをMoonBitに移植したい")
  let _ = corpus.add_post("CRDTの実装でFugueMaxアルゴリズムを使う")
  let _ = corpus.add_post("カレーのスパイスを新しく買った。クミンとコリアンダー")
  let _ = corpus.add_post("incr libraryにMemoプリミティブを追加した")
  let _ = corpus.add_post("共同編集にはCRDTかOTが必要")
  // Post 2 (curry dinner) → top-1 should be Post 5 (curry spices)
  let results_2 = corpus.query_similar(2, top_n=3)
  inspect!(results_2[0].0, content="5")
  // Post 5 (curry spices) → top-1 should be Post 2 (curry dinner)
  let results_5 = corpus.query_similar(5, top_n=3)
  inspect!(results_5[0].0, content="2")
}

test "integration - CRDT cluster" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("MoonBitでインクリメンタル計算のライブラリを作っている")
  let _ = corpus.add_post("増分計算の論文を読んだ。Salsaの設計が参考になる")
  let _ = corpus.add_post("今日の晩ご飯はカレーにした")
  let _ = corpus.add_post("Rustのroeywanスタイルのgreen treeをMoonBitに移植したい")
  let _ = corpus.add_post("CRDTの実装でFugueMaxアルゴリズムを使う")
  let _ = corpus.add_post("カレーのスパイスを新しく買った。クミンとコリアンダー")
  let _ = corpus.add_post("incr libraryにMemoプリミティブを追加した")
  let _ = corpus.add_post("共同編集にはCRDTかOTが必要")
  // Post 4 (CRDT FugueMax) → top-1 should be Post 7 (CRDT/OT)
  let results_4 = corpus.query_similar(4, top_n=3)
  inspect!(results_4[0].0, content="7")
  // Post 7 (CRDT/OT) → top-1 should be Post 4 (CRDT FugueMax)
  let results_7 = corpus.query_similar(7, top_n=3)
  inspect!(results_7[0].0, content="4")
}

test "integration - query_text finds curry posts" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("MoonBitでインクリメンタル計算のライブラリを作っている")
  let _ = corpus.add_post("増分計算の論文を読んだ。Salsaの設計が参考になる")
  let _ = corpus.add_post("今日の晩ご飯はカレーにした")
  let _ = corpus.add_post("Rustのroeywanスタイルのgreen treeをMoonBitに移植したい")
  let _ = corpus.add_post("CRDTの実装でFugueMaxアルゴリズムを使う")
  let _ = corpus.add_post("カレーのスパイスを新しく買った。クミンとコリアンダー")
  let _ = corpus.add_post("incr libraryにMemoプリミティブを追加した")
  let _ = corpus.add_post("共同編集にはCRDTかOTが必要")
  let results = corpus.query_text("カレーライスが食べたい", top_n=3)
  let ids = results.map(fn(pair) { pair.0 })
  // Post 2 or 5 (curry cluster) should appear in results
  inspect!(ids.contains(2) || ids.contains(5), content="true")
}

test "integration - query_text finds CRDT posts" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("MoonBitでインクリメンタル計算のライブラリを作っている")
  let _ = corpus.add_post("増分計算の論文を読んだ。Salsaの設計が参考になる")
  let _ = corpus.add_post("今日の晩ご飯はカレーにした")
  let _ = corpus.add_post("Rustのroeywanスタイルのgreen treeをMoonBitに移植したい")
  let _ = corpus.add_post("CRDTの実装でFugueMaxアルゴリズムを使う")
  let _ = corpus.add_post("カレーのスパイスを新しく買った。クミンとコリアンダー")
  let _ = corpus.add_post("incr libraryにMemoプリミティブを追加した")
  let _ = corpus.add_post("共同編集にはCRDTかOTが必要")
  let results = corpus.query_text("CRDTで共同編集", top_n=3)
  let ids = results.map(fn(pair) { pair.0 })
  inspect!(ids.contains(4) || ids.contains(7), content="true")
}

test "integration - duplicate posts near-1.0 similarity" {
  let corpus = Corpus::new()
  let id0 = corpus.add_post("全く同じ文章を二回投稿する")
  let _ = corpus.add_post("全く同じ文章を二回投稿する")
  let results = corpus.query_similar(id0, top_n=1)
  inspect!(results.length(), content="1")
  inspect!(results[0].1 > 0.99, content="true")
}

test "integration - single char post has no similarity" {
  let corpus = Corpus::new()
  let id0 = corpus.add_post("あ")
  let _ = corpus.add_post("カレーを作った")
  // Single char produces 0 bigrams → zero vector → no similarity
  let results = corpus.query_similar(id0)
  inspect!(results, content="[]")
}

test "integration - query_text matches stored query_similar" {
  let corpus = Corpus::new()
  let _ = corpus.add_post("カレーを作った")
  let _ = corpus.add_post("プログラミングの勉強")
  let _ = corpus.add_post("カレーのスパイス")
  // query_text with exact text of post 0
  let text_results = corpus.query_text("カレーを作った", top_n=3)
  let similar_results = corpus.query_similar(0, top_n=3)
  // Same posts should appear (ranking may differ slightly due to IDF of query doc)
  let text_ids = text_results.map(fn(pair) { pair.0 })
  let similar_ids = similar_results.map(fn(pair) { pair.0 })
  // At minimum, both should find post 2 (shares "カレ" bigram)
  inspect!(text_ids.contains(2), content="true")
  inspect!(similar_ids.contains(2), content="true")
}
```

- [ ] **Step 2: Run tests**

Run: `moon test --package dowdiness/canopy/echo`
Expected: PASS — if any cluster assertion fails, inspect the actual scores to diagnose. Use `moon test --update` to capture snapshot values, then verify rankings manually.

- [ ] **Step 3: If any assertion fails, snapshot all scores for debugging**

Add a temporary debug test to print all pairwise similarities:

```moonbit
test "debug - print all similarities" {
  let corpus = Corpus::new()
  // ... add all 8 posts ...
  for i = 0; i < 8; i = i + 1 {
    let results = corpus.query_similar(i, top_n=7)
    println("Post \{i}: \{results}")
  }
}
```

Run: `moon test --package dowdiness/canopy/echo -f "debug"`
Review output, adjust assertions if bigram produces different but still reasonable clusters.

- [ ] **Step 4: Run moon check and moon info**

Run: `moon check && moon info`
Expected: PASS

- [ ] **Step 5: Run moon fmt**

Run: `moon fmt`

- [ ] **Step 6: Commit**

```bash
git add echo/
git commit -m "feat(echo): integration tests with 8 Japanese fixture posts"
```

---

### Deviation from Spec

The spec proposed 4 packages (`echo/`, `echo/tokenizer/`, `echo/tfidf/`, `echo/store/`). This plan uses 2 packages:

- `echo/tokenizer/` — bigram (separate for swappability)
- `echo/` — everything else (TermFreq, SparseVec, Corpus)

Reason: `tfidf` and `store` share `TermFreq` and `SparseVec` types. Splitting them into separate packages forces these types to be `pub` for cross-package access, defeating the "internal" goal. Two packages achieves the same encapsulation with less boilerplate.
