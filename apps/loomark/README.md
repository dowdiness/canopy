# Loomark

Loomark is a browser Markdown Text editor built with [Rabbita](https://github.com/dowdiness/rabbita).

## Architecture

Loomark is one standard Rabbita application in `apps/loomark/app`. Its private
`Model`, `Msg`, `update`, and `view` expose one public function:

```moonbit
pub fn app() -> @rabbita.Val[@rabbita.Html]
```

`apps/loomark/main/main.mbt` mounts that application. Browser I/O is contained
in `apps/loomark/internal/browser_storage`, whose Interface is `open` and
`save`.

See the [Standard Rabbita Text App plan](../../docs/plans/2026-08-24-loomark-standard-rabbita-text-app.md) and the accepted decisions:

- [Current and saved text](../../docs/decisions/2026-08-24-loomark-source-first-interactive-contract.md)
- [Production E2E boundary](../../docs/decisions/2026-08-24-loomark-production-e2e-boundary.md)

## Autosave and Recovery

Text input updates the Document text immediately. Autosave writes the document
ID and text to browser storage after a 250 ms quiet period and after IME
composition ends. At most one write is active.

A missing record creates an empty document with `crypto.randomUUID()`. A stored
record must contain exactly `document_id` and `text`. Invalid data is not
overwritten; Loomark enters Recovery. A save failure preserves the current text
and presents Retry.

Loomark does not read an older record shape, search another key, switch storage
backends, or generate identity through a fallback.

## Development

```bash
./scripts/install-local-warren.sh
cd apps/loomark
../../_build/tools/bin/warren dev --direct
```

## Production validation

```bash
./scripts/test-loomark-standalone-e2e.sh
```

This performs a clean Warren production build, rejects removed Worker and
private-control artifacts, and runs Playwright against the release output.
