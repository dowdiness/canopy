# Loomark account document sync

**Status:** In progress

The user approved revision-checked source synchronization, without automatic
concurrent merging, on 2026-09-16. Protecting the editing experience takes
priority over reducing implementation work. This is the single design and
implementation specification for that scope, not a report of implemented sync.

The user selected Google sign-in through Better Auth and requested MoonBit-first
implementation with minimal TypeScript. Authentication stays library-owned;
document policy and application state belong in MoonBit.

## GitHub Issue

Issue publication requires owner permission. Open and closed issue searches for
Loomark sync and accounts found no issue owning this delivery. After permission,
create one implementation issue and link it here and back to this plan.
[Causal genesis research #1352](https://github.com/dowdiness/canopy/issues/1352)
and [multi-document roadmap #1362](https://github.com/dowdiness/canopy/issues/1362)
are related but do not own this non-causal synchronization path.

## Why

A person must be able to write on a phone, confirm remote saving, close the
phone, and continue the same document on a new PC after signing in. Neither
the phone nor another connected peer may be required to recover the document.

## Scope

In:
- `apps/loomark/app/`: account/session state, per-document sync decisions,
  account-aware Recent documents, conflict preservation, and saving feedback.
- `apps/loomark/app/internal/source_repository/`: atomic local checkpoints,
  remote baselines, durable pending writes/deletes, and legacy record enrollment.
- `apps/loomark/internal/text_area/`: preserve its existing editing contract;
  change only if integration tests expose a necessary boundary adjustment.
- `apps/loomark/server/` (new): same-origin authentication and revision-checked
  document APIs backed by D1. Better Auth configuration and Worker dispatch are
  TypeScript; `server/documents/` owns the MoonBit document API and platform FFI.
- `apps/loomark/wrangler.jsonc` and package tooling: serve assets and APIs from
  the Loomark Worker, with separate disposable local test storage.
- `apps/loomark/examples/vanilla/` and `scripts/`: production-browser integration
  tests, including process restart and independent browser storage.
- Loomark README/CONTEXT and relevant decisions: distinguish local durability,
  remote durability, account ownership, and explicit revision replacement.

Out: CRDT/genesis integration, automatic text merging, collaborative cursors,
cross-device Undo, history browsing/backup, filesystem authority, E2EE, native
apps, multiple login providers, and changes to `apps/relay-server`.
Deploying, configuring shared credentials, and creating external resources
require separate permission. Local-only operation remains supported.

## Current State

- [Repository storage](../../apps/loomark/app/internal/source_repository/storage.mbt)
  uses one IndexedDB store and acknowledges each local transaction.
- [Source codec](../../apps/loomark/app/internal/source_repository/source_codec.mbt)
  stores exactly document identity and text. Opening isolates unsupported data.
- [Save transitions](../../apps/loomark/app/documents_save.mbt) already serialize
  local saves per document and fence delayed work.
- [Application update](../../apps/loomark/app/update.mbt) owns activation and IME
  gating; [textarea policy](../decisions/2026-08-25-loomark-textarea-edit-boundary.md)
  keeps native Undo while the current editor remains mounted.
- The Source repository recognizes account-scoped `sync/` checkpoints that
  atomically contain local text, remote baseline, generation, an immutable
  pending save/delete, and update/conflict state. A length-prefixed frame keeps
  metadata in a small JSON header and stores each distinct text once in a raw
  section, avoiding repeated large-text JSON encoding. Enrollment retires the
  legacy Source in the same IndexedDB transaction, and conflict persistence
  writes one stable local recovery Source with the checkpoint atomically.
  The unversioned format has no migration or compatibility fallback while it
  remains uncommitted.
- A pure per-document persistence lane accepts only Autosave-eligible
  checkpoints, permits one IndexedDB write in flight, and retains only the
  newest follow-up. Edits during a write and an acknowledgment followed by a
  new pending operation therefore require at most one additional encoding and
  write. Successful and failed storage completions both carry the checkpoint
  identity they belong to. Failures retain the newest write for explicit retry,
  non-active completions return explicit stale-event errors, and conflict
  recovery stays attached to its atomic checkpoint write. The lane remains
  disconnected until account state is introduced; it adds no input callback or
  second timer.
- Sync ingress parses raw account IDs, operation UUIDs, server revisions, and
  checkpoint frames into opaque domain values once. Each parser raises only its
  exact MoonBit suberror rather than a shared catch-all error. Synchronous
  receipt, writer, and checkpoint rejections use typed `raise`; `Result` values
  remain at tests or asynchronous boundaries that need errors as data.
  Reconciliation returns a typed conflict draft only for actual divergence;
  only that draft accepts a recovery identity parsed relative to the source
  document. Operation planning requests an operation ID only when a request can
  start. The checkpoint state
  is an exclusive `Ready | Sending | RemoteUpdate | Conflict` phase rather than
  independent pending/block fields, eliminating invalid combinations. A change
  returns its checkpoint write directly; an unchanged edit or reconciliation
  is represented only by `None` or `Unchanged`, without copying the checkpoint
  and a derivable directive into a second outcome object. The indivisible
  conflict recovery write cannot be detached. The writer is an exclusive
  `Available | Storing | RetryPending` state; stale completions are explicit
  errors and compare only account, document, and generation rather than full
  document text. Individual transitions do not repeatedly compare a raw account
  string. The application routes ordinary typed sync messages to retained
  account-owned state; changing the authenticated account changes network
  eligibility without discarding another account's pending local work.
- Pure MoonBit sync transitions resend the exact persisted operation after
  restart, retain edits made during an in-flight operation, reject non-matching
  writer completions, reconcile equal text without false conflict, and keep
  conflicts blocked under one recovery identity. A definitive server revision
  rejection retires the pending operation into reconciliation; an uncertain
  delivery keeps the exact operation for retry. Once an update is available,
  older remote revisions cannot replace it. Scheduling and HTTP integration are
  not yet connected to the editor.
- [Worker configuration](../../apps/loomark/wrangler.jsonc) now includes the
  same-origin API and a local D1 binding. No remote database has been provisioned.
- Better Auth and D1 integration tests exercise authentication, revision checks,
  duplicate receipts, tombstones, and account isolation. The document API is
  compiled from MoonBit; this is not yet connected to the editor UI.
- No auth configuration appeared in the inspected Loomark/relay configuration,
  relevant environment-variable names, or their local `.dev.vars` locations.
  This does not establish what is configured in the Cloudflare dashboard.

### Review corrections

Use Better Auth's public `advanced.database.joins` option with D1/Kysely to
avoid the 1.7.5 fallback join path that logs raw database errors. No third-party
library patch, fork, or version change was made. Keep refreshed
session cookies on document error responses, and replace OAuth callback error
codes/descriptions with a generic failure in the returned redirect.

Reuse check: these corrections use the existing library configuration and Web
Headers/URL APIs. The owned HTTP binding registers reader release with `defer`.
Cancellation testing establishes eventual release after a pending read settles;
the existing Promise wait does not support immediate interruption. A nested
`Promise::from_async` cancellation probe hit an async runtime panic and was
removed, without modifying async. Do not claim client-disconnect cancellation.
Validation: 14 targeted MoonBit tests, 19 workerd/D1 tests, and server TypeScript
checking passed. Oracle's focused follow-up found the two blockers resolved.

### Cloudflare reference comparison

Compared [cloudflare-starterkit-mbt](https://github.com/mizchi/cloudflare-starterkit-mbt)
and its [D1 binding](https://github.com/mizchi/cloudflare.mbt/blob/main/src/d1.mbt)
as design references, not dependencies. The useful addition is explicit D1
success handling, checked against the [official result contract](https://developers.cloudflare.com/d1/worker-api/return-object/).
The existing `worker_platform/d1` boundary now requires a successful envelope
for `all` and each batch result; explicit failure and malformed results become
distinct redacted errors. Regression fixtures include a successful first batch
result followed by a failed or malformed second result.

Reuse check: keep the existing opaque handles, parameter conversion, `js_ffi`
exception/Promise bridge, and core JSON parser. `Any::stringify` already returns
a String, so its unnecessary nullable conversion was removed. Row schemas and
atomic receipt SQL stay application-owned; no extra public result wrapper is
needed. Do not copy global request environment storage, unbounded body reads,
or introduce SQL generation for the current small query set. Existing Wrangler
type generation and required-secret configuration need no replacement.

## Desired State and UX contracts

### Entering and leaving sync

Local documents remain usable without signing in. Signing in retrieves the
account's documents but does not silently upload pre-existing local documents.
An explicit `Sync this document` action enrolls a local document. New documents
created in the account context sync automatically. Recent documents remains one
list; local-only and account-owned documents have clear status, not new folders.

Use Google sign-in through Better Auth. Do not build a password system, OAuth
implementation, or generic provider framework. Better Auth owns provider
identity validation and account/session records; document ownership uses its
verified user ID, not an email address supplied by the client.

Sign-in navigation must checkpoint current edits first. If browser saving fails,
stay in the editor and offer Retry/Export rather than navigate away. Composition
must finish before that checkpoint. A cancelled login returns to the same work.

Logout stops network synchronization, not local recovery. Preserve pending work
under its original account namespace. Switching accounts never uploads it to the
new account or includes the former account's documents in the new account view.
Before leaving an account, make any local-only pending changes legible. Cached
data is not encrypted against other users of the same browser profile; do not
describe logout as secure erasure. Session expiry leaves current text editable
and locally saveable, with a non-blocking sign-in action.

### Saving without blocking editing

Keep the existing immediate input and local Autosave path. Networking, hashing,
JSON encoding, and remote-revision processing never run in the input callback.
Do not instantiate a parser in Text mode or introduce CRDT work.

Display distinct current-document states: saving on this device, saved on this
device/waiting to sync, synced, offline, sign-in required, and conflict. `Synced`
means the exact current committed text has a remote durability acknowledgment;
an older in-flight acknowledgment cannot mark newer text synced. Connection
health or completed request transmission is not a saving receipt.

Transient failures retry with bounded backoff, pause while hidden/offline, and
resume on visibility/connectivity recovery. Provide Retry without a blocking
dialog. Never claim hidden-page flushing guarantees saving before termination.

### Remote changes and conflicts

Fresh startup shows local data without waiting for the network. A remote revision
received before editor activation may supply the activated document. Once an
editor is mounted, never assign remote text behind the person's back, even if
local and remote baselines previously matched. Show a quiet `Update available`
action. Explicitly opening that revision replaces the editor once, after IME
ends and after preserving any intervening local edits. It starts a new native
Undo history, consistent with Document switch. Check the local generation again
at activation; clicking the action does not authorize dropping later input.

Reconcile against the acknowledged baseline: if local and remote text are equal,
advance the baseline without a conflict or editor replacement. If only local
text changed, send a revision-checked save. If only remote text changed, retain
it as the available update. Distinct revisions with equal text are not conflicts.
Resolve any already-persisted pending request first so a lost acknowledgment is
not misclassified as a competing edit.

When local and remote text both diverge from their common acknowledged revision,
and differ from each other, keep the current text editable. Persist the local branch as a distinct recovery
document before advancing its baseline or exposing the server text as a
replacement. Use a stable recovery identity for the conflict so retries and
restarts cannot produce repeated copies. Clearly label the relationship and
allow opening either version; do not append explanatory text to Markdown.
Do not automatically choose a winner or upload a recovery copy without intent.
If recovery persistence fails, retain the current text and stop that document's
sync, with Retry/Export. Other documents continue independently.

Returning to a phone with an already-mounted editor may require tapping `Update
available`; a newly opened document must use the latest retrieved revision.
This deliberate difference protects IME, selection, and native Undo.

### Deletion

For synced documents, confirmation explicitly says deletion applies across
devices. Commit a local pending-delete record before removing the row. Preserve
the server tombstone after acknowledgment so old offline clients cannot recreate
the identity. Deletion checks the expected revision just like saving: if another
device changed the document, do not silently delete the unseen newer text.
Expose that conflict and require a new informed deletion decision.

An offline edit arriving after remote deletion is preserved as a separate
local recovery document, never as resurrection of the original identity.
Retry after a lost delete acknowledgment remains idempotent. Local-only deletion
retains the existing contract.

## Storage and protocol design

Use one D1 database for Better Auth and document storage, avoiding a second
storage service for this scope. Every document and receipt key includes the
verified account owner. Store document identity, revision, text or tombstone,
and operation receipts there.
Derive the account's document list from the same rows; do not split document
creation and list registration into independently committed operations. Return
bounded, paginated document metadata; fetch bodies only when needed rather than
downloading every document on every poll.

The same-origin Worker authenticates every request before calling the MoonBit
document API. Document routes do not accept a client-supplied owner as authority.
All account responses are private/no-store. Reject cross-origin mutations and
enforce strict request shape, body limits, and supported encoding. Size rejection
must preserve locally editable/exportable text and explain why sync is pending.

Each mutation contains document ID, expected remote revision, a stable operation
ID, and text or deletion intent. In one transaction, validate the expected
revision, apply the change, and record its receipt. Reusing an operation ID with
different content is rejected. Repeating an accepted operation returns its
original receipt, even after another device advances the document. A tombstone
cannot be replaced through the create path. A receipt never proves that a newer
local checkpoint is synced.

Use D1's transactional batch for conditional admission, document mutation, and
receipt creation. Await batch completion before sending a success response.
Do not introduce pre-read races or application locks. Test failed writes and
restart, not only in-memory behavior.

For enrolled documents, store text, owning account, remote baseline/revision,
and pending operation in one local checkpoint. Persist an immutable
request before sending it. If edits happen while it is in flight, retain the
latest local text separately from that request; first resolve/retry the original
request, then derive the next one from the new baseline. Apply acknowledgments
and remote checkpoints atomically. Restart must not require reconstructing a
lost request identity from text alone.

The integration boundary must not execute `Send` merely because a transition
produced a sending checkpoint: enqueue that checkpoint, wait for its matching
IndexedDB success, and only then send. A definitive revision-conflict response
uses `reject_conflict`; timeout, disconnect, and other uncertain delivery retain
and resend the persisted operation ID. Conflict recovery must enter the writer
lane before later edits for that document so coalescing cannot detach the
recovery Source from its checkpoint.

Retain existing `source/v1` documents. Enrollment must preserve exact text and
identity and publish the new local record atomically; failure leaves the old
record authoritative. Do not let an inactive old record reappear as a duplicate.
Scope checkpoints and delayed results to account, document, and generation.
Local compare-and-write must detect another tab's newer checkpoint; stale tabs
must preserve a recovery branch instead of silently overwriting it.

The current Rabbita IndexedDB binding supports atomic blind mutation but not a
transaction-local read/compare/write operation. Therefore multi-tab CAS remains
an integration gate rather than a property of the present checkpoint writer;
implement it before claiming multi-tab support and before final sync acceptance,
not as a prerequisite for the initial single-tab integration.

### Authentication boundary

Use Better Auth's Google provider, callback handling, CSRF protections, secure
HttpOnly session cookie, and revocable database sessions. Keep cookie session
caching and automatic account linking disabled. Do not duplicate OAuth, token
verification, cookie cryptography, or session management in MoonBit. Do not log
codes, tokens, cookies, or text. Bind each document request to its expected
account to reject cross-tab account-switch races. Provider failures must not
compromise local editor availability.

### Rabbita message and lifecycle boundary

Keep one stable Rabbita application state so account changes never recreate the
textarea or disturb IME, selection, or native Undo. The model retains the sync
state of every account observed during the page lifetime, loaded lazily from its
account-scoped IndexedDB checkpoints. Authentication selects which retained
account may perform network work; it does not transfer or delete checkpoint
ownership. Logging out therefore pauses network synchronization while local
checkpointing and Export remain available.

Use ordinary nested messages rather than a callback registry, custom event bus,
or account-incarnation framework:

```moonbit nocheck
priv enum Msg {
  // Existing editor messages remain unchanged.
  AccountResolved(Int, AccountResult)
  Sync(SyncEvent)
}

priv enum SyncEvent {
  CheckpointCompleted(CheckpointResult)
  MutationCompleted(AccountId, OperationId, MutationResult)
  DiscoveryCompleted(AccountId, Int, DiscoveryResult)
}
```

The exact constructors may follow the implemented HTTP result types, but the
ownership rule is fixed: every `SyncEvent` contains exactly one parsed account
authority. `CheckpointResult` derives it from its originating checkpoint;
network events carry it directly. Do not duplicate the account in an outer
message and then validate two copies. Each callback only emits `Sync(event)` and
contains no state logic. Root `update` routes the event to that account's
retained state, where the checkpoint writer, operation ID, remote revision, or
discovery request ID decides whether the completion is current. Do not allocate
a second generic request identity when an existing domain identity already
distinguishes the operation.

Account lookup is the one result that cannot yet be routed by `AccountId`,
because it determines that identity. Keep its latest request ID in the session
state and accept only the matching `AccountResolved` message. While account
lookup is pending or unavailable, preserve editing and local checkpoint writes
but start no network synchronization. Refresh account identity after auth
navigation, logout, visibility recovery, and an expected-account rejection; do
not poll it from the input path.

An inactive account may accept a valid completion for work already started and
persist its receipt or newest checkpoint. It must not start another network
request, expose its documents as belonging to the authenticated account, or
replace the mounted editor. When the same account is selected again, its
original writer lanes and request identities continue; A → B → A therefore does
not create a second A state that can collide with an earlier A completion. A
page reload has no surviving callbacks and reconstructs state from IndexedDB.

Use `Val::switch_by` only for disposable account-specific presentation or
subscriptions that have no parent-to-child Autosave input. It is not the sync
correctness boundary. Rabbita intentionally has no consumer API that turns a
changing parent `Val` into an immediate child message; forcing the sync reducer
into such a child would require storing an `Emit`, polling, or adding a custom
event bus. The stable root message loop is smaller and follows Rabbita's normal
`Model` / `Msg` / `update` / `Cmd` contract. Cancellation may release resources
but is not required for correctness.

Do not add a second `moonbitlang/async` worker or queue to the application model.
Rabbita's browser host and HTTP commands already execute on that runtime. Async
task groups are lexical: returning from `with_task_group` guarantees joined
children, but `Task::cancel` is cooperative and does not synchronously prove
that a task can no longer enqueue a result. Rabbita's browser host also launches
each async `Cmd` without exposing its task handle to consumer code. Bridging a
component lifetime to a new task group would therefore require a binding-level
registry, cancellation handle, queue, and the same message identity checks.
That duplicates the existing command loop rather than simplifying it.

Use `moonbitlang/async` inside server code or a focused Rabbita binding when an
actual streaming or structured-child lifetime requires it. Account sync remains
ordinary `Cmd` effects returning typed `Msg` values. Backoff, visibility, and
online policy stay explicit in the pure model so they are durable, inspectable,
and testable; cancellation is only an optional resource optimization.

Better Auth remains the server authorization boundary, and its session ID is
not exposed as application state. Each document request carries its expected
`AccountId` as a precondition; the Worker compares it with Better Auth's verified
user ID before reading or mutating documents. A client-provided account never
grants authority. If another tab changes the shared cookie before a request is
admitted, the mismatch is rejected rather than returning one account's data to
another account's retained state.

Tests must cover delayed checkpoint, mutation, and discovery messages through
A → B → A; valid results return to the original retained A state, stale request
identities are rejected, and no A result starts network work while B is selected.
Account switches must leave the same textarea mounted. Expected-account mismatch
must fail before document access. Existing operation-ID and remote-revision
tests continue to own ordering within one account.

The acceptance matrix is:

- Reverse-ordered account lookups: only the latest lookup selects an account.
- A mutation completes while B is selected: update A's retained checkpoint and
  schedule no A network follow-up.
- A completion arrives after A → B → A: accept it only when its existing
  checkpoint, operation, revision, or discovery identity is still current in
  the same retained A state.
- The shared cookie changes before server admission: expected-account mismatch
  performs no document access and requests a fresh account lookup.
- The page reloads: no callback survives; durable pending operations are parsed
  from IndexedDB and resumed only for the authenticated owner.

### MoonBit / TypeScript boundary and reuse

`server/documents/` compiles to a separate server-only JavaScript module.
It owns request admission and wire encoding, and calls the app-internal
`server/internal/document_store` package for typed documents and commit results.
That store owns row validation, pagination, and atomic CAS/receipt SQL; it never
returns HTTP responses. These app packages do not expose or use `js.Any`.

The reusable `modules/worker-platform` module provides opaque HTTP and D1
handles plus the Web Crypto operations required here. Its public interfaces
contain no dynamic handles or Loomark policy. Existing `dowdiness/js_ffi`
supplies the private dynamic calls, synchronous exception conversion, and
`moonbitlang/async/js_async` Promise bridge. Reuse core Json, ArrayView/map, and
StringBuilder for validated data and bounded accumulation. Local mutation is
restricted to builders and stream consumption. This is a small platform
binding, not a new FFI framework or generic document repository; the D1 batch
remains the atomicity authority. No ORM, second OAuth implementation, or
TypeScript document-service implementation is needed.

Encoding reuse: core `encoding/hex.encode` replaces the manual digest loop;
core `encoding/utf8.encode` replaces the private TextEncoder bridge and public
crypto byte-count helper. On this JS-only target it uses TextEncoder and
replaces lone surrogates with U+FFFD. Explicit byte fixtures and independent
SHA-256 vectors cover Unicode, surrogate boundaries, BOM, NUL, and empty text.
HTTP admission now uses core UTF-8 directly, and revision validation remains
private to the document store. No replacement wrappers are introduced.

Package tests cover the host boundary separately from real workerd/D1 tests.
Malformed result serialization must also cross `try_sync`: a plain MoonBit
catch does not catch arbitrary JavaScript exceptions after async suspension.
Generated TypeScript declarations currently erase external types to `any`;
typed host signatures and runtime integration tests cover that compiler limit.

Async upgrade evidence (2026-09-16): Loomark and worker-platform now request
`moonbitlang/async 0.22.1`. The existing compiler/core pair
`0.10.12+1634b282e` builds it; no toolchain upgrade was needed. Isolated Node
24.14.1 tests passed both already-aborted and suspended-then-aborted exported
Promises, including execution of cleanup. A separate probe of the official
`ReadableStream::from_js` enqueued byte 65 then errored on the next pull.
`io.Reader::read_all` returned without raising (observed `failed=false`), and
`defer stream.close()` produced an unhandled rejection. The HTTP adapter is
therefore retained; a regression checks failure after a valid ASCII prefix,
so decoding truncated UTF-8 cannot accidentally make the test pass.
Do not treat the failed upstream probe as a passing compatibility check or
silence it by treating interrupted content as complete.

The small TypeScript adapter loads the generated module in request scope;
Better Auth configuration and Worker dispatch stay TypeScript so library
options retain SDK type checking. Integration tests remain Vitest tests against
the actual Workers runtime/D1. Future browser sync transitions and scheduling
belong in the existing MoonBit/Rabbita app, with FFI limited to browser APIs.

Local tests use an isolated provider fixture and separate test configuration.
Do not ship a test-login endpoint, account query parameter, or unsigned-token
bypass in the production Worker. Real provider login and phone testing remain
release checks that a fixture cannot prove.

## Implementation order

1. After design review and permission, publish the owning issue and add the
   reciprocal link. Record the accepted sync additions in Loomark's contract.
2. Specify and test pure mutation/reconciliation decisions: stale version,
   duplicate delivery, lost acknowledgment, newer edits, conflict, and deletion.
3. Implement transactional account storage and authenticated API boundaries;
   test storage failure, restart, and cross-account rejection locally.
4. Implement local checkpoint enrollment, pending requests, atomic receipts, and
   account separation. Test interrupted enrollment and quota/write failure.
5. Connect the scheduler to existing Autosave completion and lifecycle events;
   add remote list/open paths without blocking local startup or input.
6. Add account/status/update/conflict actions using existing Rabbita/RUI patterns.
   Verify narrow-screen keyboard use, IME, selection, Undo, and accessibility.
7. Run the full phone-context → close → server restart → fresh PC-context → edit
   → phone reopen sequence. Inspect rendered screenshots and input timings.
8. Report local evidence separately from real-provider, deployed-service, and
   physical-phone checks. Obtain approval before external configuration/deploy.
   Archive this plan only when its owning issue's full scope is complete.

## Acceptance criteria

- [ ] A phone-sized browser creates a document and receives a truthful remote
  saving acknowledgment, then closes completely.
- [ ] Restarting the actual local server process with persistent test storage
  does not lose the acknowledged document or its account association.
- [ ] A new browser context signs into the same account, discovers the document,
  opens exact text, and saves an edit. The original device is not a data source.
- [ ] Reopening the phone retrieves the PC edit. A still-mounted editor offers
  an explicit update instead of disturbing its input/Undo state.
- [ ] Another account cannot list, read, mutate, or delete the document, including
  with a guessed ID or delayed request from a previous account session.
- [ ] Losing responses, retrying after restart, and editing during a request
  neither lose changes nor falsely acknowledge newer text.
- [ ] Divergent edits and edit/delete races preserve the local branch without
  overwriting unseen remote content or resurrecting deleted identities.
- [ ] Existing local records survive login, enrollment failure, logout, and
  account switching; nothing is uploaded to a different account automatically.
- [ ] Local persistence failure prevents unsafe navigation/replacement; network
  failure does not disable editing, Document switch, or Export.
- [ ] Text mode remains parser-lazy; input, IME, selection, native Undo, and
  narrow-screen editing do not regress under pending saves and remote responses.

## Validation

Retain existing production checks:

```bash
./scripts/test-loomark-standalone-e2e.sh
./scripts/check-documentation-lifecycle.sh
```

`npm run test:server` and `npm run typecheck:server` in `apps/loomark` build the
MoonBit server artifact before running integration tests or TypeScript checks.
Run `NEW_MOON_MOD=0 moon test --target js -p dowdiness/loomark/server/documents dowdiness/loomark/server/internal/document_store`
for pure codec/model tests, plus the package tests in the
[worker-platform README](../../modules/worker-platform/README.md).
Still to add: `scripts/test-loomark-sync-e2e.sh` for the authenticated
production artifact and persistent local Worker.
Run affected MoonBit package tests/checks using the repository toolchain.

New tests must include server process replacement, two isolated authenticated
browser contexts, no source peer, partial/offline delivery, crash between remote
commit and local receipt, local storage failure, multi-tab races, and a third
unauthorized account. Exercise the normal UI rather than production test hooks.

Measure input handler time and frame latency separately for short Japanese text,
100 KiB, and 1 MiB text with remote responses and local saves overlapping input.
Use the existing 10 ms Text input target from the accepted source-first decision;
record environment and raw samples rather than claim unmeasured phone performance.
Inspect mobile/desktop renders of synced, offline, conflict, expired-session,
and update-available states. Browser emulation is not physical-phone evidence.

## References

- [Local ownership](../architecture/human-centered-product-principles.md):
  managed sync is optional durability for enrolled documents, not a new
  dependency for retaining and exporting local work. P2P library capabilities
  are not removed or claimed as implemented in Loomark.
- [Source-first input policy](../decisions/2026-08-24-loomark-source-first-interactive-contract.md).
- [D1 database API](https://developers.cloudflare.com/d1/worker-api/d1-database/):
  transactional batch execution.
- [Better Auth Google provider](https://better-auth.com/docs/authentication/google):
  provider configuration and callback setup.
- [Google OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect):
  server flow, state/nonce validation, token verification, and stable subject ID.
