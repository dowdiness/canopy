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

The pinned `deps/rabbita` commit,
`983d1e50455d0ac8e3e73b9aacb19eb1be70a7c4`, is published on the
`dowdiness/rabbita` `feat/warren-standalone-direct` branch. It contains Warren
direct mode and the current MoonBit debug-rendering spelling used by Loomark.
The installer verifies the immutable gitlink SHA directly rather than relying
on the branch remaining at that commit.

Existing checkouts that still configure the upstream Rabbita repository as the
submodule origin must synchronize it before installing Warren:

```bash
git submodule sync --recursive
git -C deps/rabbita remote set-url origin https://github.com/dowdiness/rabbita.git
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

The standalone page does not publish `MarkdownApp`, `MarkdownSession`, unmount,
remount, or reusable-host behavior. Those lifecycle contracts remain deferred
to issue #1072.
