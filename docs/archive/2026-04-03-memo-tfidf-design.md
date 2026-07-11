# Echo — TF-IDF Core Library Design

**Status:** Approved
**Date:** 2026-04-03

## Goal

Build the core TF-IDF similarity library ("echo") for an auto-structuring memo system. The library takes text input, tokenizes it, computes TF-IDF vectors, and returns the most similar existing posts by cosine similarity.

This is Phase 1: pure-computation library with bigram tokenization, validated with Japanese text. UI, persistence, and editor integration are out of scope.

## Package Structure

```
echo/              — public API surface (re-exports from store/)
echo/tokenizer/    — internal: bigram tokenizer (TinySegmenter slot for later)
echo/tfidf/        — internal: TF-IDF computation, sparse vectors, cosine similarity
echo/store/        — internal: corpus management, add post, query
```

**Visibility:** Only `echo/` exposes public API. The `tokenizer/`, `tfidf/`, and `store/` packages are internal implementation details. This keeps the tokenizer swappable (bigram → TinySegmenter) without breaking downstream consumers.

## Data Flow

```
add_post(corpus, text)
  → tokenizer::bigram(text) → Array[String]
  → tfidf::term_freq(tokens) → TermFreq
  → store tf alongside post
  → update corpus doc_freq/doc_count
  → recompute ALL post vectors (IDF changed)
  → return updated corpus

query_text(corpus, text, top_n)         ← primary API
  → tokenize + compute TF-IDF vector for input text (ephemeral, not stored)
  → cosine_similarity against all stored post vectors
  → return top-N results sorted by score (self excluded if text matches a post)

query_similar(corpus, post_id, top_n)   ← convenience wrapper
  → look up post by id, delegate to cosine similarity loop
```

## Core Types

```moonbit
// echo/tokenizer/ (internal)
fn bigram(text: String) -> Array[String]

// echo/tfidf/ (internal)
struct TermFreq {
  counts: Map[String, Int]
  total: Int
}

struct SparseVec {
  entries: Map[String, Double]
  norm: Double  // pre-computed, 0.0 for empty vectors
}

fn term_freq(tokens: Array[String]) -> TermFreq
fn to_sparse_vec(tf: TermFreq, doc_count: Int, doc_freq: Map[String, Int]) -> SparseVec
fn cosine_similarity(a: SparseVec, b: SparseVec) -> Double

// echo/store/ (internal, re-exported via echo/)
struct Post {
  id: Int
  text: String
  tf: TermFreq   // stored for recomputation without re-tokenizing
  vec: SparseVec  // recomputed when IDF changes
}

struct Corpus {
  next_id: Int
  doc_freq: Map[String, Int]
  posts: Array[Post]  // mutable buffer, owned by Corpus
}

fn Corpus::new() -> Corpus
fn Corpus::add_post(self: Corpus, text: String) -> Int  // returns post id, mutates self
fn Corpus::query_text(self: Corpus, text: String, top_n~ : Int = 5) -> Array[(Int, Double)]
fn Corpus::query_similar(self: Corpus, post_id: Int, top_n~ : Int = 5) -> Array[(Int, Double)]
```

## Tokenizer Semantics

**Bigram:** 2-codepoint sliding window over the input string.

Rules:
- Iterate by Unicode codepoints (MoonBit `Char`), not bytes
- Window slides by 1 codepoint at each step
- Whitespace and punctuation are included (they carry signal in bigrams: "。C" marks sentence boundaries)
- Empty string → empty array
- 1-character string → empty array (no bigram possible)

Examples:
```
"カレー"     → ["カレ", "レー"]
"CRDTの実装" → ["CR", "RD", "DT", "Tの", "の実", "実装"]
"あ"         → []
""           → []
"a b"        → ["a ", " b"]
```

## Edge Cases and Error Behavior

All functions are total (no errors, no panics):

| Scenario | Behavior |
|----------|----------|
| `add_post("")` | Stores post with empty token list, zero vector. Returns id. |
| `query_text("", ...)` | Returns empty array (zero vector has no similarity). |
| `query_similar(invalid_id, ...)` | Returns empty array. |
| `top_n <= 0` | Returns empty array. |
| `cosine_similarity` with zero norm | Returns `0.0` (guard against division by zero). |
| Self-similarity in `query_similar` | Excluded from results. |

## Design Decisions

1. **Bigram only** — no TinySegmenter until concrete failures found with test data
2. **Full recompute on add** — IDF changes invalidate all vectors. Store `TermFreq` per post to avoid re-tokenizing; only recompute `to_sparse_vec` for each post. Fine for < few thousand posts.
3. **Norm caching** — pre-computed in `SparseVec`, avoids repeated sqrt
4. **No stopword filtering** — bigrams like "のは" get low IDF naturally (appear in many docs)
5. **Pure computation** — zero FFI, fully testable with `inspect` snapshots
6. **Mutable corpus** — `Corpus` owns its `Array[Post]` and mutates in place. Simpler than pretending immutability with mutable containers. Functional style deferred to Phase 4 (`incr` integration).
7. **`query_text` as primary API** — supports the core use case: "I'm writing something, show me related posts" without requiring the text to be stored first.

## Testing

### Fixture Posts

```
Post 0: "MoonBitでインクリメンタル計算のライブラリを作っている"
Post 1: "増分計算の論文を読んだ。Salsaの設計が参考になる"
Post 2: "今日の晩ご飯はカレーにした"
Post 3: "Rustのrowanスタイルのgreen treeをMoonBitに移植したい"
Post 4: "CRDTの実装でFugueMaxアルゴリズムを使う"
Post 5: "カレーのスパイスを新しく買った。クミンとコリアンダー"
Post 6: "incr libraryにMemoプリミティブを追加した"
Post 7: "共同編集にはCRDTかOTが必要"
```

### Expected Rankings (top-3 neighbors, self excluded)

Assertions are **ordering checks** (relative rank), not exact score values. Scores will be snapshot-tested separately for regression detection.

| Query post | Expected top-1 | Must appear in top-3 |
|------------|---------------|---------------------|
| Post 0 (incremental/MoonBit) | Post 6 or Post 1 | {0→6, 0→1, 0→3} |
| Post 2 (curry dinner) | Post 5 | {2→5} |
| Post 4 (CRDT FugueMax) | Post 7 | {4→7} |
| Post 5 (curry spices) | Post 2 | {5→2} |
| Post 7 (CRDT/OT) | Post 4 | {7→4} |

### Additional Test Cases

- Empty string query returns empty results
- Single-character post is stored but has no similarity to anything
- Duplicate posts have high (near-1.0) similarity
- `query_text` with unstored text produces same ranking as if it were stored then queried

## Future Phases

- **Phase 2:** Minimal UI (CLI or web) for validation
- **Phase 3:** Persistence (JSON file)
- **Phase 4:** Incremental optimization via `incr` Signals (IDF per term as Signal, TF-IDF per doc as Memo)
- **Integration:** Block editor and ideal editor (Rabbita) — all editors unify eventually
