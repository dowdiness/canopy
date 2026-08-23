# Loomark 10k existing-path diagnosis

**Date:** 2026-08-24

**Base:** `f2ee331d`
**Status:** throwaway diagnosis; no optimization retained

## Result

Three isolated Chromium runs used the existing LocalText prototype with archive
preparation disabled. The 10,000-line source was exact and no persistence write
occurred.

| Phase | p50 | observed p95 |
| --- | ---: | ---: |
| Restore to visible Raw editor | 123,451 ms | 131,246 ms |
| Restore script time | 123,181 ms | 130,986 ms |
| IndexedDB read | 3.7 ms | 4.5 ms |
| Input visible | 826 ms | 1,048 ms |
| Causal ready | 1,440 ms | 1,539 ms |
| Native textarea `beforeinput` to `input` | 812 ms | 939 ms |
| Incremental parser apply | 138 ms | 157 ms |
| Receipt construction after parser mirror | 56 ms | 81 ms |
| Input-period layout | 8.0 ms | 8.3 ms |

An isolated JS-target construction of a 198,928-code-unit
`MarkdownEditor::with_semantic_attachment` took 318.0 seconds. Existing phase
hooks attributed 317.7 seconds to `crdtReplace` and 191.8 ms to parser apply.

## Existing mechanisms checked

- `TextState` exposes empty construction plus ordinary scalar-safe insert,
  replace, admission, and synchronization. It has no bulk text seed API.
- `Document::insert` deliberately creates one operation per Unicode scalar.
- Reusing the existing lazy `IndexedState` rebuild for a multi-character local
  insert did not help: the same isolated construction took 341.9 seconds. The
  attempted change was reverted.
- Ordinary Loomark Raw input already uses
  `MarkdownEditRequest::ReplaceText(start, delete_len, inserted)`. Replacing a
  whole source is not the ordinary native-input path.
- The repository already contains a reusable Rabbita CodeMirror binding, but
  changing the Raw surface cannot solve the 123-second authority construction
  cost and was not attempted.

## Decision

Do not optimize IndexedState, parser, projection, storage, or layout for this
problem. The remaining startup bottleneck is the existing scalar-per-operation
CRDT construction path. Avoid adding another measurement system; the next
product decision is whether initial standalone text must become CRDT authority
eagerly or whether EGW should gain an efficient core-owned construction path.

All temporary benchmark and instrumentation source was removed. Raw retained
results are in
`docs/evidence/2026-08-24-loomark-10k-existing-path-diagnosis.json`.
