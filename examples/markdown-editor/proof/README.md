# Editor ownership boundary proof

This is an executable experiment, not the published editor API. It uses
`editor.MarkdownEditor` to exercise the textarea's deferred restoration against
a newer accepted edit, document switch, removal, and replacement by another
owner with the same DOM ID. It also checks that Text/Preview/Split mode retains
the native textarea and drives the real incremental preview without importing
its engine or state. The host still fences an obsolete document edit after a
switch.

The rejection and acceptance are deliberately separate Rabbita messages queued
in one batch so both run before the next paint. They simulate the app's
admission decisions; this fixture is not a test of a real browser edit being
rejected by Loomark's Documents.

The browser test also covers two trusted native edits while the next render is
held. It selects and deletes `a` from `abc` (the fixture rejects that edit),
then types `X`: restoration must happen before the next input task, so the
accepted result is `abcX`, not `abXc`. A re-entrant native input in the same
task is checked separately for rejection-baseline leakage. This isolates the
textarea restoration boundary; it does not exercise Loomark's actual Documents
admission policy.

The browser regression for queued input covers two `execCommand` edits in one
JavaScript task. They enqueue both trusted browser `input` events before Rabbita
processes either edit. Chromium does not emit
`beforeinput` for `execCommand`, so this specifically exercises the adapter's
full-value fallback. The fixture rejects the first deletion of `a` from `abc`,
and the editor invalidates the second edit captured before that rejection. The
test checks event types and ordering and asserts that committed text cannot
contain rejected content. A separate same-task pair without rejection checks
that ordinary consecutive edits are still accepted.

After installing the Loomark E2E dependencies, run from this directory:

```sh
../../../_build/tools/bin/warren build --browser-entry main --public-dir "$PWD/public"
node test.mjs
```

The browser test uses the Playwright dependency already installed for Loomark's
E2E suite. The proof UI intentionally has no app storage or authentication.
