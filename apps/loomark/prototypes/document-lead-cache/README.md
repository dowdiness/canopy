# PROTOTYPE: Document-lead cache lifecycle

This throwaway logic prototype asks whether Loomark's proposed state model feels
coherent when driven through visibility, quiet-update, deletion, and responsive
transitions. In particular, can an app-scoped pure Document-lead cache remain
lazy while hidden and survive UI-scope disposal, while a visible row layer is
rebuilt and reconciled independently?

The program is a pure reducer with a small terminal shell. It simulates the
intended graph contract and exposes every relevant revision, cache key, scope,
and lifecycle counter after each action. It does **not** prove Rabbita runtime or
API behavior; that remains an implementation validation after this state model
is accepted. Lead extraction intentionally uses the first non-empty source line
because Markdown presentation is outside this prototype's question.

Run from the repository root:

```sh
just prototype-loomark-document-lead-cache
```

Pass `wide` as the final argument to start with the wide-screen contract instead:

```sh
just prototype-loomark-document-lead-cache wide
```

Suggested walkthrough:

1. `o` — first demand extracts A and B and mounts their rows.
2. `c`, then `o` — unchanged leads are reused while rows are rebuilt.
3. `c`, `e A # Changed`, `q A` — A becomes dirty without extraction.
4. `o` — only A is extracted.
5. `c`, `d B`, `o` — B's hidden cache survives until demand, then is removed
   before rows mount.
6. `r` — visibility remains stable while presentation changes.
7. `s A` while narrow — selection closes the overlay; the same selection while
   wide leaves the pane open.
8. `a C`, then `e C First\\nSecond` — first input adds C to Recent documents and
   seeds its first lead source immediately.

This prototype belongs only on `prototype/loomark-document-lead-cache`. Once it
answers the question, capture the verdict separately and keep the prototype off
main.
