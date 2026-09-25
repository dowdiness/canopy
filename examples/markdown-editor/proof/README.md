# Editor ownership boundary proof

This is an executable experiment, not the published editor API. It exercises
`TextArea`'s deferred restoration against a newer accepted edit, document
switch, removal, and replacement by another owner with the same DOM ID. It also
checks that the host's Text/Preview/Split mode retains the native textarea and
drives the real incremental `PreviewEngine`.

The rejection and acceptance are deliberately separate Rabbita messages queued
in one batch so both run before the next paint. They simulate the app's
admission decisions; this fixture is not a test of a real browser edit being
rejected by Loomark's Documents.

After installing the Loomark E2E dependencies, run from this directory:

```sh
../../../_build/tools/bin/warren build --browser-entry main --public-dir "$PWD/public"
node test.mjs
```

The browser test uses the Playwright dependency already installed for Loomark's
E2E suite. The proof UI intentionally has no app storage, authentication, or
reusable editor facade.
