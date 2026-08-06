# Loomark

Loomark is the standalone Rabbita Markdown editor. One Rabbita root owns the
browser page for its lifetime, and every Raw editor, Block editor, and Preview
change passes through the same canonical document transaction.

## Development

Install the repository-owned Warren overlay, then start the top-level page with
live reload:

```bash
./scripts/install-local-warren.sh
cd apps/loomark
../../_build/tools/bin/warren dev --direct
```

The overlay is built from the pinned `deps/rabbita` commit plus
`patches/rabbita/warren-standalone.patch`. It adds Warren direct mode and the
current MoonBit debug-rendering spelling without changing the Rabbita runtime
used by Loomark.

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
