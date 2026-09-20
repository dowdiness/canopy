# Loomark

Loomark is a browser Markdown Text editor built with [Rabbita](https://github.com/dowdiness/rabbita).

Read [the product vocabulary and behaviour contract](CONTEXT.md) before
changing Loomark. The accepted decisions below provide the related rationale
and constraints.

## Architecture

Loomark is one standard Rabbita application in `apps/loomark/app`. Its private
`Model`, `Msg`, `update`, and `view` expose one public function:

```moonbit
pub fn app() -> @rabbita.Val[@rabbita.Html]
```

`apps/loomark/main/main.mbt` mounts that application. Browser integration is
split between `apps/loomark/app/internal/source_repository`, which reconciles exact-text Documents
and derives an in-memory Catalog through `open`, `save`, and `delete`,
and `apps/loomark/internal/text_area`, which converts native textarea
input sequences into shared `TextChange` operations.

Recent documents are a demand-driven keyed projection: DocumentLead extraction is retained per document and visible row rendering is disposable while the sidebar is collapsed.

See the [Standard Rabbita Text App plan](../../docs/plans/2026-08-24-loomark-standard-rabbita-text-app.md) and the accepted decisions:

- [Current and saved text](../../docs/decisions/2026-08-24-loomark-source-first-interactive-contract.md)
- [Production E2E boundary](../../docs/decisions/2026-08-24-loomark-production-e2e-boundary.md)
- [Textarea edit ownership](../../docs/decisions/2026-08-25-loomark-textarea-edit-boundary.md)
- [Document deletion](../../docs/decisions/2026-08-31-loomark-document-deletion.md)

## Autosave and Recovery

Text input updates the Document text immediately. Autosave makes latest text
eligible after 250 ms quiet, when one non-restarting 2,000 ms maximum-wait timer
becomes processable, or when the page becomes hidden. The maximum is application
policy rather than a wall-clock acknowledgment guarantee. IME composition
defers persistence until its committed result.

For each document, at most one Source write and one newer pending checkpoint
exist; different documents may persist independently. Transaction completion
starts a latest follow-up only when that checkpoint is already eligible. A
maximum-window identity and per-edit quiet revision reject delayed work even
when text follows an equal-value ABA path. Exact return to the acknowledged Source
restores `Saved` without a redundant write, including after a failed attempt;
other failures require explicit Retry.

Each `source/v1/<document-id>` record contains exactly `document_id` and `text`;
the text is the only durable content authority. Opening scans the complete
store, isolates malformed or unsupported records, derives names into a
rebuildable in-memory Catalog, and orders valid Documents lexically by ID.
The independent `editing-document` string record selects an exact valid
Document after reconciliation; otherwise the lexical first Document is
selected. Opening never repairs or rewrites it. Recent-document recency is
page-local: changed, imported, or promoted Documents move first immediately,
while merely opening one does not reorder the list; reload is deterministic
lexical order.

An empty repository opens an ephemeral New document without writing a Source.
Legacy records are unsupported and remain in IndexedDB. A normal save writes
only the accepted Document and applies its acknowledgment to in-memory state.
Activating a saved Document writes its ID to `editing-document` best-effort.
Source save failures preserve current text and present Retry. A confirmed Delete is ordered within
the target document's persistence lane; deleting the Editing Document activates
and remembers a saved fallback, or opens an ephemeral New document when none
remains. Hidden-page persistence is best effort because the browser may freeze
or terminate before IndexedDB completion.

## Import and Export

Import accepts any browser-selected file whose bytes are strict UTF-8. It
consumes an initial UTF-8 BOM, normalizes CRLF and CR to LF, and preserves every
other decoded character. Filename, extension, and media type are not admission
or identity inputs. Each accepted import creates and activates a fresh document
and starts its normal New-document save immediately; failure keeps the imported
text available through the existing Retry path.

Export downloads the Editing Document's current in-memory text without waiting
for Autosave. The browser receives `<Derived name>.md`, or `untitled.md` when no
name can be derived, as the suggested filename. Export does not create a lasting
relationship with the downloaded file.

## Development

```bash
./scripts/install-local-warren.sh
cd apps/loomark
npm ci
npm run build:styles
../../_build/tools/bin/warren dev --direct
```

Loomark uses Tailwind CSS v4 for its light-DOM utility classes. During style
work, run `npm run dev:styles` in a second terminal so
`public/styles.css` stays current while Warren serves the app. The generated
stylesheet is ignored; `styles/tailwind.css` and static utility bundles in
MoonBit are the sources of truth.

### Account service (integration in progress)

Google authentication uses Better Auth. Its configuration and Worker dispatch
stay in TypeScript. MoonBit's `server/documents/` owns HTTP admission and wire
encoding; `server/internal/document_store/` owns typed document results, SQL,
revision-checked writes, tombstones, and durable retry receipts. Neither
package uses dynamic JavaScript handles. The reusable
[worker-platform module](../../modules/worker-platform/README.md) owns typed
HTTP, D1, and Web Crypto bindings over the existing `js_ffi` bridge.
The server builds separately from the browser bundle.
Authentication and documents share one D1 database, with document access scoped
to the authenticated user.

The Source repository now recognizes account-scoped `sync/` checkpoints.
Each checkpoint is one length-prefixed IndexedDB string with a small JSON header
and a deduplicated raw-text section. The latest local text, acknowledged remote
baseline, immutable pending save or delete, local generation, and any
remote-update or conflict state remain atomic without repeatedly JSON-encoding
large text. Enrollment atomically replaces the legacy `source/v1` record;
conflict preservation atomically writes the stable local recovery document with
the blocked checkpoint. The unversioned sync format has no migration or
compatibility fallback while it remains uncommitted. Account-scoped ownership
keeps durable data separate. Pure MoonBit transitions resend a persisted
operation after restart, keep newer edits separate from an older in-flight
request, retire a definitively rejected operation into reconciliation, and
retain the newest observed remote revision. Uncertain delivery leaves the exact
operation pending for idempotent retry. A separate typed account HTTP boundary
parses a successful response directly into `AccountId`, distinguishes 401 from
an unavailable account service, and classifies malformed success bodies as
unavailable. After local repository open, the root Rabbita model resolves the
account through an ordinary `Sync` message without replacing its editor page.
`SavedDocuments` is the only owner of durable checkpoints. Account-scoped
document keys retain every account's optimistic records while the Recent
documents projection exposes only the selected account beside local-only
documents. Switching accounts therefore changes visibility, not editing or
Autosave ownership.

Checkpoint persistence has a pure per-document causal lane. It never encodes on
text input: the document reducer submits text only after the existing Autosave
quiet/maximum/composition lifecycle makes it eligible. Every transition starts
from the lane's newest waiting write, active write, or durable checkpoint, in
that order; local text and future remote acknowledgments therefore cannot branch
independently from the same stored generation. At most one IndexedDB checkpoint
write is in flight and one newest checkpoint waits behind it, so intermediate
edits collapse without losing durable retry state. Storage failure retains the
newest write for explicit retry; successful and failed completions both carry
their checkpoint identity. A completion that does not match the active write is
an explicit stale-event error and cannot advance the lane. Conflict recovery
first persists divergence, then applies its generated identity to the lane's
newest causal head and stores the checkpoint and recovery document atomically.
Editing remains immediate while storage is pending; success updates the
canonical checkpoint, while failure keeps the optimistic text and newest
retryable write. Once a checkpoint is durable, the root derives its next HTTP
or identity-creation command. The command interpreter requires the current
`SavedDocuments`, so a scheduled recovery cannot silently become `Cmd.none`.
Synchronized deletion controls, account controls, and status UI remain
unconnected.

The sync model parses account IDs, UUID document and operation IDs, server
revisions, and checkpoint frames once at their ingress. Document IDs use one
UUID-shaped identity space locally and remotely; malformed IDs never enter the
model. Each parser declares its exact MoonBit suberror; synchronous receipt,
writer, and checkpoint rejections use typed `raise`, while IndexedDB callbacks
keep failures as message data. Reconciliation returns either a checkpoint write
or `Unchanged`. Operation and recovery identities are requested only when their
effects can start. Transitions receive those domain types rather than
revalidating strings and numbers. A checkpoint has exactly one phase—`Ready`,
`Sending`, `Available`, `Diverged`, or `Conflict`—so invalid combinations cannot
be represented. `Diverged` is durable before recovery identity creation;
recovery completion transforms the newest lane head, preserving edits made
while that effect was running. The next directive is derived from the phase
instead of being copied into every transition result. A writer lane is present
only while `Storing` or `RetryPending`; its absence means the durable checkpoint
is current. A delayed completion that does not match its effect, account,
document, and generation returns an explicit error without comparing full text.

The account-sync state is a small internal package, separate from the HTTP
boundary and root editor package. It owns the session lookup plus transient
writer and network work keyed by account and document. Durable checkpoints are
not copied into it. The root
model is the direct product of its editor `Page` and this sync state. Existing
editor messages remain ordinary `Msg` constructors; `Sync(SyncMsg)` carries
account and checkpoint results without a second page-message wrapper. A → B → A
retains optimistic records and actual in-flight work under account-qualified
document keys, while account/document/generation identity rejects unrelated
delayed completions. No generic account-incarnation token or callback registry
is added. The pure document reducer emits an exact Source operation for
local-only data and an account-qualified eligible Document for synced data.
Only the sync lane derives a checkpoint write, so Autosave, acknowledgments,
and future reconciliation all share one causal transition head.

Account lookup itself carries a latest-request ID because its result determines
the account and cannot yet be routed by one. While that lookup is unresolved,
local editing and checkpointing continue but network synchronization stays
paused. Local repository open deliberately precedes account lookup, so showing
and editing local data never waits for network I/O. The typed document HTTP
binding preserves custom account headers, response status, and response body;
it parses receipts and conflict documents at ingress. Requests use Rabbita's
managed `Cmd` lifecycle rather than a detached async task. An expected-account
rejection triggers a fresh account lookup only when that account is still
selected.

A save first persists its immutable operation ID and payload, then sends it.
Successful receipts enter the same causal writer before becoming canonical.
Uncertain delivery leaves the durable operation available for retry on the next
account resolution or visibility restore. A 409 returns to the reducer before
the current remote document is fetched, so an account switch can defer that
request until its account is current. Conflict recovery is then persisted
atomically. Definitive 413 and 422 responses retire the rejected operation. An
unchanged oversized payload waits for a new edit instead of looping; text
already changed during delivery proceeds immediately, while a rejected
operation identity is replaced automatically. HTTP bodies are accepted only
after complete `arrayBuffer()` consumption and strict UTF-8 decoding; an
interrupted stream cannot produce a receipt from a valid prefix.

Remote discovery is one managed command whose private loop consumes every
lexically paged metadata response before publishing a catalog message. D1 stores
an 80-scalar Markdown lead beside each present revision, so listing never reads
or serializes full document bodies. The transient account catalog is not copied
into IndexedDB; explicit tombstones and only newer revisions update it. Opening
a remote-only row fetches its body, persists a received synchronized checkpoint,
and activates it only after that write succeeds. A newer revision of an existing
checkpoint is fetched and reconciled through the same causal writer. It becomes
`Available`, or persists `Diverged` before recovery, without assigning text to
the mounted textarea. `observed_revision` includes both phases, so an available
update continues observing newer catalog revisions rather than freezing at the
first notice. Reopening a newer remote revision advances the existing writer
head—including a checkpoint that became durable while GET was in flight—instead
of creating another generation-zero checkpoint. A remote-only record is
admitted from that exact durable checkpoint only when its selected revision can
activate; revision and textarea text therefore cannot come from different
snapshots. If IME composition starts while a remote row is loading, admission
and activation remain pending until composition ends. A canceled selection
still allows its already-started checkpoint write to finish without activating
it. Account, discovery, effect, revision, and checkpoint identities fence
delayed results. The expensive remote/local join depends only on a narrow
document-membership projection and the remote catalog, and checkpoint success
does not rescan and reproject the account, so ordinary edits do not rebuild
either graph.

`switch_by` remains appropriate for disposable account-only presentation and
subscriptions, but not as the sync reducer's ownership boundary: parent
Autosave input must enter the normal root `update` without a stored child
`Emit`, polling, or a custom event bus. A separate `moonbitlang/async` task group
or queue would duplicate Rabbita's existing async `Cmd` runtime and still need
the same message identities because cancellation is cooperative. Multi-tab
checkpoint writes still need transaction-local compare-and-write; the current
Rabbita IndexedDB API provides atomic blind mutations but no CAS. That CAS is
required before multi-tab support and final sync acceptance, not before the
initial single-tab integration.

From `apps/loomark`:

```bash
npm run test:server
npm run typecheck:server
NEW_MOON_MOD=0 moon test --target js -p dowdiness/loomark/server/documents dowdiness/loomark/server/internal/document_store
```

The npm commands build the server's MoonBit artifact before consuming it.
Integration tests use disposable local D1 storage and Better Auth's test
utilities, not real Google credentials or a production login bypass. The
Worker build also builds this artifact. Database schema generation is a
development tool, never a public endpoint.

The editor now sends durable pending operations, applies receipts and revision
conflicts, discovers remote metadata, and opens remote-only documents. Periodic
list polling, synchronized delete controls, and sync status UI are not connected
yet, so this does not establish the complete phone-to-PC editing experience or
real Google callback flow. The remaining work is tracked in the
[account sync plan](../../docs/plans/2026-09-16-loomark-account-document-sync.md).
No shared database or deployment is provisioned by these test commands.

## Production validation

```bash
./scripts/test-loomark-standalone-e2e.sh
```

This performs a clean Warren production build, rejects removed Worker and
private-control artifacts, and runs Playwright against the release output.

Demand tests use `npm run test:demand` from `examples/vanilla`. Its
[artifact builder](../../scripts/build-loomark-demand-artifact.sh) copies the
workspace to a temporary directory and adds a test-only JS FFI extraction
counter plus a small query-selected static public-feature
[fixture](examples/vanilla/fixtures/recent-dialog-demand.mbt) only there; no
production source or `dist` is instrumented. The [fixture check](examples/vanilla/tests/demand.spec.ts)
exercises hidden navigation with a dialog-only consumer: its cold dialog needs
all three leads to disambiguate duplicate labels, but it is not reachable from
the current modal user path.

The same app tests cover hiding during pending deletion and reopening without
resurrecting the row, as well as replacing row DOM while retaining leads. That
DOM check is not direct reactive-scope or memory proof; the feature's visible
[`switch_by`](internal/recent_documents/recent_documents.mbt) source establishes
its ownership boundary, and Rabbita's [`assoc`/`switch_by` cleanup tests](../../deps/rabbita/rabbita/internal/duplix/duplix_test.mbt)
cover the framework disposal behavior.
