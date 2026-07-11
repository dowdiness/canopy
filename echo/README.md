# echo

Experimental similarity engine for short prose. `Corpus` builds a TF-IDF (with bigram + segment features) index over a set of posts and answers `query_similar(post_id, top_n?)` / `query_text(text, top_n?)` queries.

This package is an offline experiment, not part of the editor pipeline. It exists to evaluate "related notes" retrieval for the broader vision in `docs/architecture/product-vision.md`. The integration and realdata tests in this directory report `P@5` / `MRR` scores against fixture corpora.

## Public API

- `Corpus::new(tokenize? : (String) -> Array[String]) -> Corpus`
- `Corpus::add_post(self, text : String) -> Int` — returns the new post ID
- `Corpus::get_post_text(self, id) -> String?`
- `Corpus::query_similar(self, id, top_n?)` — most-similar posts excluding `id`
- `Corpus::query_text(self, text, top_n?)` — ad-hoc query without adding to the corpus

The `Post` type is exported but opaque.

## Consumers

No production package imports `echo`. The included `*_test.mbt` files exercise its evaluation harness; `echo/cmd/` provides a small driver.

## Dependencies

- `dowdiness/canopy/echo/tokenizer` — segmented bigram tokenizer
- `moonbitlang/core/math`

## Stability

Experimental. Tracked under "Echo Similarity Library" in project memory ([`project_echo_improvement_paths`](../../docs/TODO.md)) as a research direction. The API may change as we evaluate BM25, BPE, MeCab, etc.

## Notes

The corpus uses sparse vectors (`sparse_vec.mbt`) so memory is O(unique tokens), not O(corpus × vocab). The baseline reported on the bundled benchmark fixtures is P@5 = 0.48 / 0.43 blended across two evaluation sets — see project memory for the full table and improvement roadmap.
