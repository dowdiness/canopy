# Loomark production and browser-test boundary

**Date:** 2026-08-24

**Status:** Accepted

## Decision

Loomark ships one production Rabbita application. Its release contains no
test-only Model or Msg, hidden DOM control protocol, development host, URL gate,
Parser, projection runtime, or Worker.

Playwright operates the Warren production release through visible controls and
browser APIs. Tests may seed or inspect IndexedDB and may make a browser API
fail from `page.evaluate`; they do not add a test Interface to the application.
Branches that cannot be reached through product behavior or a real browser
boundary are removed.

The release test rejects unexpected JavaScript, removed Worker artifacts,
private control names, and test URL gates before running the product scenarios.
