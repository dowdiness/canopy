# Loomark

Loomark is the standalone Rabbita Markdown editor. One Rabbita root owns the
browser page for its lifetime. The production standalone surface edits Raw
Markdown directly as LocalText; it does not decode prior history or insert the
stored source into CRDT state during startup or ordinary local input. The
shared shell still owns an empty editor session. Block and Preview remain development-host
surfaces until an explicit collaboration promotion path exists.

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

The standalone application keeps one active LocalText document in this
browser's local storage. Each accepted Raw edit replaces a small record
containing the stable logical document identity and portable Markdown. The
record contains no causal history.

If LocalText is absent, Loomark reads `document_id` and `portable_markdown` from
the existing v1 archive without decoding or admitting its history. The v1 bytes
remain untouched. The first subsequent edit writes the new LocalText slot, so
reloads prefer the fast source-only path while the old archive remains as a
backup.

An applied edit remains visible if LocalText replacement fails. Loomark warns
that those changes are not saved locally; reloading recovers the last
successfully stored LocalText, or the untouched v1 fallback when no LocalText
has been stored. Invalid and unsupported records remain behind the existing
non-editable recovery screen. Selection, focus, and browser-local undo remain
page-lifetime state and are not restored after reload.

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
