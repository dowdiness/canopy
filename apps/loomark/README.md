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

## Production validation

```bash
./scripts/test-loomark-standalone-e2e.sh
```

This performs a clean Warren production build, rejects removed Worker and
private-control artifacts, and runs Playwright against the release output.
