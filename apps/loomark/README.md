# Loomark

Loomark is the standalone Rabbita Markdown editor. One Rabbita root owns the
browser page for its lifetime. The production standalone surface edits a
source-backed Raw document (internally `LocalText`); it does not decode prior
history or insert the stored source into CRDT state during startup or ordinary
local input. The
shared shell still owns an empty editor session. Block and Preview remain development-host
surfaces until an explicit collaboration promotion path exists.

The production contract is recorded in
[Source-first interactive editing](../../docs/decisions/2026-08-24-loomark-source-first-interactive-contract.md)
and implemented by [PR #1345](https://github.com/dowdiness/canopy/pull/1345).
Raw input tasks have a hard p95 and maximum target of 10 ms. Parsing, CRDT,
hashing, JSON, archive preparation, IndexedDB, and speculative Preview work stay
outside that task; frame latency is measured separately.

## Development

Install Warren from the pinned Rabbita submodule, then start the top-level page
with live reload:

```bash
./scripts/install-local-warren.sh
cd apps/loomark
../../_build/tools/bin/warren dev --direct
```

The recorded `deps/rabbita` gitlink is the authoritative Warren revision, and
`.gitmodules` is the authoritative repository location. The pinned fork tracks
current upstream Rabbita while retaining Canopy's incremental resizable content
support and the syntax compatibility required by Canopy's MoonBit toolchain.
`scripts/install-local-warren.sh` verifies the gitlink before installation.

Existing checkouts that still configure a different Rabbita origin must
synchronize it before installing Warren:

```bash
git submodule sync --recursive
RABBITA_REMOTE="$(git config -f .gitmodules --get submodule.rabbita.url)"
git -C deps/rabbita remote set-url origin "$RABBITA_REMOTE"
git submodule update --init --recursive deps/rabbita
```

## Release build

```bash
./scripts/install-local-warren.sh
cd apps/loomark
../../_build/tools/bin/warren build
```

Warren writes the self-contained static site to `apps/loomark/dist/`. The
output is generated, ignored by Git, and should be served by an ordinary static
HTTP server.

## Local document ownership

The standalone application keeps one active Source record in this browser's
local storage. Raw typing stays browser-owned; after a 250 ms quiet period, the
latest draft becomes Canonical source and atomically replaces a small record containing the stable logical document identity and
portable Markdown. The record contains no causal history. Source-backed browser
editing uses the textarea's LF line representation; exact CRLF or lone-CR file
profiles belong to a future File-backed capability.

If the Source record is absent, Loomark reads `document_id` and
`portable_markdown` from the existing v1 archive without decoding or admitting
its history. The v1 bytes remain untouched. The first subsequent edit writes
the new source-only slot, so reloads prefer the fast path while the old archive
remains as a backup.

A browser draft is not yet canonical or durable during the quiet period. After
acceptance, the edit remains visible if Source record replacement fails.
Loomark warns that those changes are not saved locally; reloading recovers the
last successfully stored Source record, or the untouched v1 fallback when no
Source record has been stored. Invalid and unsupported records remain behind the existing
non-editable recovery screen. Selection, focus, and browser-local undo remain
page-lifetime state and are not restored after reload.

The current guarantee is trailing rather than bounded during uninterrupted
typing: a continuously changing draft can postpone acceptance. [#1347](https://github.com/dowdiness/canopy/issues/1347)
tracks max-wait and lifecycle hardening outside the Raw input task. Complete
causal history, cross-instance undo, and collaboration are also future
capabilities and must not restore archive preparation to ordinary input.

## Browser validation

```bash
./scripts/test-loomark-standalone-e2e.sh
```

This command verifies direct-mode development launch, performs a clean release
build, rejects private development-driver controls in the production bundle,
and runs the production Playwright suite. The private development-host suite
remains separately available through `./scripts/test-loomark-dev-host-e2e.sh`.

The standalone page does not expose embedding, teardown, remount, or host-reuse
behavior. Those lifecycle capabilities remain deferred to issue #1072.
