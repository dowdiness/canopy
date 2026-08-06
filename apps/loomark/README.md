# Loomark

Loomark is the standalone Rabbita Markdown editor. One Rabbita root owns the
browser page for its lifetime, and every Raw editor, Block editor, and Preview
change passes through the same canonical document transaction.

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
