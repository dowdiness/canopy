# Loomark local archive repository

Issue: #1140

Status: active — local candidate passes targeted, workspace, and browser validation

## Goal

Persist the standalone Loomark active document as one complete application-owned archive in browser-local storage. A successful replacement is acknowledged only after the provider accepts the complete archive. Reopening preserves logical document identity and causal history while creating a fresh writing instance.

## Scope boundary

#1140 owns:

- one active-document archive slot;
- complete archive preparation, atomic replacement, loading, and typed failures;
- a repository-operation acknowledgment;
- immediate persistence after every history-changing commit;
- baseline archive creation for a new active document;
- recovery-blocked startup when an existing archive cannot be safely opened;
- a storage warning after a post-acceptance replacement failure.

#1169 continues to own formal Session durability observations, a single-flight queue, latest-wins coalescing, explicit retry, and durable-version tracking. #1170 continues to own separately versioned Session metadata. Document catalogs, networking, replication, backup, and undo across restart are out of scope.

### #1169 queue contract

The queue is a deterministic functional core with one in-flight archive and one immutable latest pending archive. A completion is accepted only when its queue epoch, request identity, logical document identity, and opaque target version all match the registered write. The queue epoch is the active writing-instance lifetime and must be replaced when a queue is replaced, including when the same logical document is activated again.

Provider write failures and complete-archive preparation failures remain distinct in the persistence failure taxonomy. Every bootstrap, baseline, commit, retry, and promoted write uses one shared imperative-shell Command adapter so completion correlation and persistence tracing cannot drift by call path.

## Decisions

- The first provider is `localStorage`.
- One fixed storage slot contains one complete archive envelope. Logical document identity remains inside that envelope.
- A missing slot creates an empty document with a fresh logical document ID and immediately schedules a baseline replacement.
- Each history-changing commit schedules an immediate complete replacement. Source equality is not the persistence trigger. A true history no-op schedules nothing.
- Existing archive read, decode, version, capacity, or completeness failures preserve the stored value and mount a non-editable recovery panel.
- A replacement failure leaves the accepted in-memory document editable and the previous archive untouched. The next history-changing commit attempts the newest complete archive.
- Production uses an explicit trusted-local restore policy rather than network or test limits. Tests inject restrictive limits.
- Successful writes do not produce a saved badge. The latest failed request produces an honest storage warning; only the latest successful request may clear it.
- Repository requests carry identities so stale completions cannot change current diagnostics.

## Functional core and imperative shell

The repository core owns deterministic archive preparation, load-result classification, request identities, and completion decisions. It receives values and returns values or decisions; it performs no browser I/O.

A private binding-style shell owns `localStorage` access and Rabbita command scheduling. Consumer application code does not call `@cmd.custom_cmd` or JavaScript FFI directly.

Standalone bootstrap reads the active slot before constructing the editor application. A valid archive opens through the Markdown façade with a fresh writing-instance identity and a semantic attachment over that reopened editor. Missing storage creates a new editor. Recovery failure mounts a separate read-only recovery application. The private development host remains storage-independent.

## Behavioral boundary matrix

| Boundary | Scenario | Required observation |
| --- | --- | --- |
| Repository | missing active slot | classify as missing; do not report durability |
| Repository | baseline replacement succeeds | one complete envelope occupies the active slot; acknowledgment identifies the request |
| Repository | replacement throws or quota rejects | prior slot value remains readable; typed storage failure returned |
| Repository | valid archive load | logical document ID and canonical history are preserved |
| Repository | corrupt envelope/history | typed corrupt failure; stored value unchanged |
| Repository | newer archive schema | typed unsupported-version failure; stored value unchanged |
| Repository | restrictive restore limit exceeded | typed over-limit failure; stored value unchanged |
| Repository | incomplete history | typed incomplete-history failure; stored value unchanged |
| Persistence decision | receipt contains history although source is unchanged | schedule one complete replacement |
| Persistence decision | receipt contains no history | schedule nothing |
| Persistence decision | stale success or failure | ignore it; current warning unchanged |
| Persistence decision | latest replacement fails | show applied-but-not-saved warning; document remains editable |
| Persistence decision | latest replacement succeeds after failure | clear only the storage warning |
| Reopen | persisted document reloads | canonical history equality, stable logical document ID, fresh writing-instance ID |
| Reopen | two reopened writers edit and exchange history | both replicas converge after admission |
| Browser | first clean visit | editor mounts and baseline archive is stored |
| Browser | edit then reload | durable source reopens in one production root |
| Browser | corrupt/unsupported/over-limit/read failure | recovery panel visible, editor absent, slot unchanged |
| Browser | replacement failure after accepted edit | edited source remains visible; warning shown; reload restores prior durable source |
| Product scope | reload after editing | undo restoration is not claimed |

## Test seams

1. **Archive repository seam**: headless MoonBit tests cover complete replacement preparation, load classification, typed errors, explicit policy, history equality, and continued merge.
2. **Persistence decision seam**: deterministic MoonBit tests cover history/no-op scheduling and stale/latest completion decisions.
3. **Standalone browser seam**: Playwright covers baseline creation, durable reload, recovery blocking, storage failure, and prior-archive preservation.

Tests use public package behavior or white-box package boundaries. No public test-only API is added.

## Existing API reuse

- `LoomarkDocumentArchive::{capture,to_json_string,from_json_string}` remains the sole envelope codec.
- `LoomarkDocumentId` remains the logical identity.
- `MarkdownEditor::{commit_with_receipt,history_since,open}` remains the history and reopen façade.
- `MarkdownCommitReceipt::history` distinguishes history advancement from a true no-op.
- `MarkdownArchiveOpenLimits` carries the explicit restore policy.
- `Option`, `Result`, `String`, and immutable archive values carry deterministic core decisions.
- Rabbita `Cmd`, `batch`, `create_state_with_init`, and the binding-side `custom_cmd` pattern schedule effects without putting commands or callbacks in the model.

`MarkdownEditor::open` and `MarkdownEditor::with_semantic_attachment` cannot currently be composed over the same reopened parser. A new façade operation is justified only to open existing history and return its semantic attachment without exposing editor internals.

## Implementation order

1. Add the first failing Markdown façade test for reopening with a semantic attachment, then add the minimal shared open implementation.
2. Add the first failing repository tests for missing/valid/corrupt/unsupported/over-limit load classification and deterministic persistence completion decisions.
3. Implement the pure repository package and review its generated interface.
4. Add the private two-package browser-storage binding and provider-focused JS tests.
5. Wire standalone bootstrap, baseline persistence, history-aware commit scheduling, request completion, and recovery rendering while leaving the private development host storage-independent.
6. Add standalone Playwright scenarios one vertical slice at a time.
7. Run targeted package checks/tests, private-host and standalone browser suites, workspace checks/tests, formatting, generated-interface review, independent review, and the PR-ready gate.

## Validation

```bash
NEW_MOON_MOD=0 moon check modules/canopy/editor/markdown
NEW_MOON_MOD=0 moon test -p dowdiness/canopy/editor/markdown
NEW_MOON_MOD=0 moon check apps/loomark/repository
NEW_MOON_MOD=0 moon test -p dowdiness/loomark/repository
NEW_MOON_MOD=0 moon check apps/loomark/internal/rabbita
NEW_MOON_MOD=0 moon test -p dowdiness/loomark/internal/rabbita
./scripts/test-loomark-dev-host-e2e.sh
./scripts/test-loomark-standalone-e2e.sh
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 moon test
```

Inspect every generated `.mbti` change. In particular, the Markdown façade addition must remain additive, repository types must not expose provider handles or mutable storage, and no private development-host symbol may enter standalone release output.
