# Loomark

Loomark is a browser Markdown Text editor built with [Rabbita](https://github.com/dowdiness/rabbita).

## Architecture

Loomark is one standard Rabbita application in `apps/loomark/app`. Its private
`Model`, `Msg`, `update`, and `view` expose one public function:

```moonbit
pub fn app() -> @rabbita.Val[@rabbita.Html]
```

`apps/loomark/main/main.mbt` mounts that application. Browser integration is
split between `apps/loomark/internal/source_repository`, which reconciles
versioned Source records and derives an in-memory Catalog through `open` and
`save`, and `apps/loomark/internal/text_area`, which converts native textarea
input sequences into shared `TextChange` operations.

See the [Standard Rabbita Text App plan](../../docs/plans/2026-08-24-loomark-standard-rabbita-text-app.md) and the accepted decisions:

- [Current and saved text](../../docs/decisions/2026-08-24-loomark-source-first-interactive-contract.md)
- [Production E2E boundary](../../docs/decisions/2026-08-24-loomark-production-e2e-boundary.md)
- [Textarea edit ownership](../../docs/decisions/2026-08-25-loomark-textarea-edit-boundary.md)

## Autosave and Recovery

Text input updates the Document text immediately. Autosave makes latest text
eligible after 250 ms quiet, when one non-restarting 2,000 ms maximum-wait timer
becomes processable, or when the page becomes hidden. The maximum is application
policy rather than a wall-clock acknowledgment guarantee. IME composition
defers persistence until its committed result.

At most one Source write and one newer text-free checkpoint exist. Transaction
completion starts a latest follow-up only when that checkpoint is already
eligible. Exact return to the acknowledged Source restores `Saved` without a
redundant write; failure requires explicit Retry.

Each `source/v1/<document-id>` record contains exactly `document_id` and `text`
and is the durable authority for that document. Opening scans the complete
store, isolates malformed or unsupported records, derives first-ATX-H1 names
into an in-memory Catalog, and selects the first valid Document ID lexically.
Unknown metadata remains stored but cannot hide or override a Source.

An empty repository creates a UUID-backed Source with exact text
`# Untitled\n`. The legacy `active` record is moved atomically when safe;
collisions preserve both records. A normal save writes only the accepted Source
and installs the next in-memory Catalog after that transaction completes. A
Source save failure preserves current text and presents Retry. Hidden-page
persistence is best effort because the browser may freeze or terminate before
IndexedDB completion.

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
