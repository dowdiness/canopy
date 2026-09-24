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

For each local-only document, at most one Source write is active and one newer
Autosave window is retained; different documents may persist independently.
Transaction completion starts a latest follow-up only when that window is
already eligible. A
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

### Google sign-in and account service

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

The header's **Sign in with Google** button saves pending local edits before
leaving the editor. Failed saves keep the document open; failed authentication
offers a retry. Signed-in users can sign out without removing local documents.

For local authentication, copy `.env.example` to `.env`, set
`BETTER_AUTH_URL=http://localhost:8787`, and register
`http://localhost:8787/api/auth/callback/google` as an authorized redirect URI
on the Google OAuth client. Then run:

```bash
cd apps/loomark
npm ci
npm run db:migrate:local
npm run dev:worker
```

The Source repository now recognizes account-scoped `replica/` records.
Each replica is one length-prefixed IndexedDB string with a small JSON header
and a deduplicated raw-text section. The latest local text, acknowledged remote
baseline, immutable pending save or delete, local generation, and any
remote-update or conflict state remain atomic without repeatedly JSON-encoding
large text. Starting sync atomically replaces the local `source/v1` record;
conflict preservation atomically writes the stable local recovery document with
the blocked replica. The in-progress sync format intentionally has no migration
or compatibility fallback; disposable development records may be discarded.
Account-scoped ownership keeps durable data separate. Pure MoonBit transitions
resend a persisted operation after restart, keep newer edits separate from an
older in-flight request, retire a definitively rejected operation into
reconciliation, and retain the newest observed remote revision. Uncertain
delivery leaves the exact operation pending for idempotent retry. A separate
typed account HTTP boundary
parses a successful response directly into `AccountId`, distinguishes 401 from
an unavailable account service, and classifies malformed success bodies as
unavailable. After local repository open, the root Rabbita model resolves the
account through an ordinary `Sync` message without replacing its editor page.
`SavedDocuments` is the only owner of durable replicas. Account-scoped
document keys retain every account's optimistic records while the Recent
documents projection exposes only the selected account beside local-only
documents. Switching accounts therefore changes visibility, not editing or
Autosave ownership.

Replica persistence is a separate pure per-document causal state machine. It
never encodes on text input: the document reducer submits text only after the
existing Autosave quiet/maximum/composition lifecycle makes it eligible. Every transition starts
from the lane's causal head. While persistence is active that is the newest
waiting or active write; after failure it is deliberately the durable Replica,
so a later edit supersedes the failed candidate instead of branching from data
that never reached IndexedDB. At most one IndexedDB replica write is in flight
and one newest replica waits behind it, so intermediate edits collapse. The lane
alone retains an exact failed write and exposes an opaque retry capability;
Documents stores only failure feedback. Completions are accepted only through
their opaque attempt capability. A completion that does not match the active
write is an explicit stale-event error and cannot advance the lane. Retrying
creates a new attempt, so failure of that attempt cannot make an older retry
capability valid again.
Conflict recovery
first persists divergence, then applies its generated identity to the lane's
newest causal head and stores the replica and recovery document atomically.
Editing remains immediate while storage is pending; success updates the
canonical replica, while failure leaves the durable Replica editable and keeps
the failed write retryable only in the persistence lane. A
Replica completion updates repository truth but never acknowledges or clears a
newer working-copy Autosave window, even when both contain equal text. Once a
replica is eligible, the Documents reducer returns a synchronous action carrying
its durable base and optimistic working copy. Root `update` applies that action
to the Replica lane in the same transition; it does not queue another Rabbita
message that could arrive after a fork, tombstone, or newer edit. Only actual
IndexedDB and HTTP work becomes a `Cmd`. All nondeleted durable replicas are
materialized once when the repository opens; account projection changes only
visibility, so A → B → A cannot reconstruct a record removed by an accepted
tombstone or fork. Once a replica is durable, the root derives its next HTTP
or identity-creation command. The command interpreter requires the current
`SavedDocuments`, so a scheduled recovery cannot silently become `Cmd.none`.
The header derives narrow account and active-document status values from the
root model. It exposes ordinary messages for account retry, replica retry,
and explicit local-document sync start. Sync start and retry messages carry
opaque capabilities projected from the current state instead of arbitrary
account/document pairs. Persistence retries and network retries remain distinct
capabilities. Mutation and conflict retries retain their causal operation
identity; failed freshness reads retain retryability but coalesce their minimum
revision to the newest catalog fact. Replica persistence status is projected from the
document's persistence owner independently of the account session, including
the original Replica owner retained by a recovery Source. Account resolution
restarts failed local persistence before network work; an Undo made during that
write stays queued behind it. Sync start is a documents-owned lifecycle: only an
acknowledged Source may enter it, edits remain optimistic while its atomic
IndexedDB mutation is pending, success transfers pending text to replica
persistence, and failure resumes Source persistence. The active textarea keeps
its activation generation while the durable owner changes, so selection,
composition, and native Undo remain mounted. A remote revision never replaces
the mounted editor automatically. The header instead exposes an opaque
`Open update` action derived from the current Replica and working copy. The
action expires after another edit, account change, or newer Replica revision;
accepting it starts a fresh editor activation and native Undo history. A remote
tombstone similarly remains explicit through `Remove deleted document`.

When both local and remote text diverge, the sync transition first persists
`Diverged`, obtains one recovery UUID, and produces one atomic `Fork` write. The
original identity advances to the server branch while the current local text
moves to a local-only recovery document. While that transaction is pending, a
private `Forking` document state owns further edits and retains the textarea's
activation generation, composition, selection, and native Undo. Completion
resumes ordinary Source persistence for edits newer than the recovery snapshot.
Confirmed synchronized deletion enters one durable `Deleting` phase. The
active textarea remains mounted until that intent reaches IndexedDB; other rows
disappear optimistically. A failed local write leaves the durable `Live` Replica
editable and the lane retains the exact retry; the page holds only failure
feedback. A successful write removes the row and lets the existing scheduler
create and deliver the DELETE. Deletion of an unpublished Replica physically
removes its IndexedDB record and creates no revision-zero remote request. A
remote acknowledgment persists a text-free `Tombstone`, which remains inactive
while preventing stale devices from resurrecting the identity.

The sync model parses account IDs, UUID document and operation IDs, server
revisions, and replica frames once at their ingress. Document IDs use one
UUID-shaped identity space locally and remotely; malformed IDs never enter the
model. Each parser declares its exact MoonBit suberror; synchronous receipt,
writer, and replica rejections use typed `raise`, while IndexedDB callbacks
keep failures as message data. Reconciliation returns either a replica write
or `Unchanged`. Operation and recovery identities are requested only when their
effects can start. Transitions receive those domain types rather than
revalidating strings and numbers. A replica is exactly one outer `Live |
Deleting | Tombstone` state. `Live` alone owns its `Ready | Sending | Available
| Diverged` phase, while `Deleting` owns only the save-resolution and
delete-delivery phases that can occur after deletion intent. Tombstones carry
identity and revision but no document text. Recovery identity is an orthogonal
relation on a live Replica rather than another blocking phase. `Diverged` is
durable before recovery identity creation; recovery completion transforms the
newest lane head, preserving edits made while that effect was running. The next
directive is derived from state instead of being copied into every transition
result. A persistence lane is present only while `Persisting` or `Failed`; its
absence means the durable replica is current. A delayed completion that does
not carry the lane's active attempt returns an explicit error without comparing
full text.

The account-sync state owns session lookup, an account-bound transient remote
catalog, and network work keyed by account and document. Catalog entries and
their last observation outcome remain independent from an active discovery ID.
A matching discovery may therefore complete while session lookup is unresolved;
a later lookup of the same account exposes that result, while another account
replaces the entire catalog. New discovery IDs supersede delayed completions.
The sync state does not copy durable replicas.
Every admitted operation preparation, delivery, remote read, recovery, and
remote open is represented by its own opaque typed attempt. Rabbita commands
round-trip that attempt unchanged, so callbacks cannot reconstruct or mix
account, document, operation, read-purpose, or selected-open identity. A failed
attempt remains in the protocol until an explicit retry creates a fresh attempt;
UUID-generation failure therefore remains actionable instead of deleting work.
Remote-open failure retains only its page-local selection intent and exposes a
separate opaque retry capability; it is not durable mutation work and is not
stored in IndexedDB. Another selection, cancellation, or account lookup expires
that capability structurally. Selection is a demand for an openable durable
Replica, not a competing synchronization lane. An existing Replica therefore
continues through its ordinary operation, conflict, recovery, or freshness work;
only a remote-only document uses a selection-specific GET. Failed ordinary work
remains retryable while selected, and a newer catalog revision updates the
freshness requirement instead of preserving a stale read snapshot. After each
durable write, the replication aggregate first reevaluates the selection from
the canonical Replica and current catalog, then derives ordinary network work.
The root model owns its editor `Page` and one replication aggregate. That
aggregate coordinates the account-sync protocol with per-document Replica
persistence: a remote effect can be exposed only after its Replica lane is
current, and account recovery retries local durability before considering
network work. Remote selection records only account, document, and intent in
that aggregate; the current catalog supplies the required revision. `Persisting`
waits, failed durability retries, and only a current lane can advance the
selection or ordinary sync. IndexedDB and HTTP remain command effects interpreted by
the root, rather than dependencies of the pure aggregate. Existing
editor messages remain ordinary `Msg` constructors; `Sync(SyncMsg)` carries
account and replica results without a second page-message wrapper. A → B → A
retains optimistic records and actual in-flight work under account-qualified
document keys, while account/document/generation identity rejects unrelated
delayed completions. No generic account-incarnation token or callback registry
is added. The pure document reducer emits an exact Source operation for
local-only data and an account-qualified eligible Document for synced data.
Sync protocol transitions derive replica writes but never execute them. All
Autosave, acknowledgment, reconciliation, sync-start, and recovery writes enter
the aggregate's one persistence state machine; the root only interprets the
already-admitted persistence or network effect.

Account lookup itself carries a latest-request ID because its result determines
the account and cannot yet be routed by one. While that lookup is unresolved,
local editing and replica persistence continue but network synchronization stays
paused. Local repository open deliberately precedes account lookup, so showing
and editing local data never waits for network I/O. The typed document HTTP
binding preserves custom account headers, response status, and response body;
it parses receipts and conflict documents at ingress. Requests use Rabbita's
managed `Cmd` lifecycle rather than a detached async task. An expected-account
rejection triggers a fresh account lookup only when that account is still
selected.

The mode bar derives independent Rabbita values for account state, local
durability, Replica persistence, sync control, remote relation, per-document
network activity, and selection activity. Equality stops changes in one value
before rebuilding the others. These remain separate facts. A
clean working copy can therefore still expose a failed Replica metadata write,
without misreporting it as a network failure. Remote relation is defined only
for a parsed live Replica; deleting candidates and tombstones cannot report
visible text as synchronized. The newest remote knowledge is the monotonic join
of the durable Replica observation and the transient catalog head. A missing or
older catalog entry cannot erase an update already stored on the device, while
a newer catalog observation—including a tombstone newer than a stored update
body—determines the relation and expires the old capability before it can be
consumed. Persistence retry, document-network retry, and selection-fetch retry use
different message and opaque capability types. A network retry identifies the
protocol's failed task and is consumed only after the aggregate resolves its
authoritative durable Replica.

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
a remote-only row fetches its body, persists a received synchronized replica,
and activates it only after that write succeeds. A newer revision of an existing
replica is fetched and reconciled through the same causal writer. It becomes
`Available`, or persists `Diverged` before recovery, without assigning text to
the mounted textarea. `observed_revision` includes both phases, so an available
update continues observing newer catalog revisions rather than freezing at the
first notice. Opening an existing Replica advances that ordinary freshness lane
rather than creating another GET lifecycle. A remote-only response can create a
Replica only while the document remains absent locally; if a Replica becomes
durable while that GET is in flight, the response expires and the canonical
Replica continues through ordinary synchronization. A remote-only record is
admitted from that exact durable Replica only when the current catalog revision
can activate; revision and textarea text therefore cannot come from different
snapshots. If IME composition starts while a remote row is loading, admission
and activation remain pending until composition ends. A canceled selection
still allows its already-started replica write to finish without activating
it. If that row becomes a tombstone before its body arrives, the tombstone
enters the same causal writer but ends the selection, so persistence cannot
activate a deleted document. Account, discovery, typed attempt, revision, and
replica identities fence delayed results. The expensive remote/local join depends only
on a narrow document-membership projection and the remote catalog, and replica
success does not rescan and reproject the account, so ordinary edits do not
rebuild either graph.

`switch_by` remains appropriate for disposable account-only presentation and
subscriptions, but not as the sync reducer's ownership boundary: parent
Autosave input must enter the normal root `update` without a stored child
`Emit`, polling, or a custom event bus. A separate `moonbitlang/async` task group
or queue would duplicate Rabbita's existing async `Cmd` runtime and still need
the same message identities because cancellation is cooperative. Multi-tab
replica writes still need transaction-local compare-and-write; the current
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
conflicts, discovers remote metadata, opens remote-only documents, displays
account/document sync status, and explicitly starts sync for local documents.
It also exposes current-state capabilities for remote updates and tombstones,
and preserves divergent local text through an atomic recovery fork without
replacing a mounted editor. Synchronized deletion is persisted before the
active editor is replaced, retries exact uncertain operations after restart,
and converges through revision-checked tombstones. Periodic list polling and
recovery-relation presentation in Recent documents remain unfinished. A
separate local browser suite now runs the
production UI and HTTP/document handlers against Better Auth test sessions and
persistent local D1. It covers Worker restart, response-loss replay, independent
browser conflict recovery, and account switching/isolation without adding a
route to the production Worker. This still does not establish the full
phone-to-PC acceptance sequence, real Google callback flow, or physical-device
performance. The remaining work is tracked in the
[account sync plan](../../docs/plans/2026-09-16-loomark-account-document-sync.md).
No shared database or deployment is provisioned by these test commands.

## Production validation

```bash
./scripts/test-loomark-standalone-e2e.sh
./scripts/test-loomark-sync-e2e.sh
```

This performs a clean Warren production build, rejects removed Worker and
private-control artifacts, and runs Playwright against the release output. The
sync suite uses a separate test-only Worker configuration and disposable local
D1; production authentication configuration is unchanged.

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
