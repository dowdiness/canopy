# Loomark production E2E

This directory contains the Playwright boundary for the Warren production
release. Tests interact only with the visible Text editor and browser storage.
They do not import application internals or expose a test-only control path.

Run the complete boundary from the repository root:

```bash
./scripts/test-loomark-standalone-e2e.sh
```

The script builds the production release, rejects unexpected JavaScript or
removed Worker artifacts, type-checks the test, and runs the Playwright suite.

After that build, run the slower explicit-GC retention boundary when changing
Preview parsing, semantic ownership, or lazy subtree reuse:

```bash
npm --prefix apps/loomark/examples/vanilla run test:retention
```

The retention suite checks unchanged DOM-node identity and performs 5,000 edits
across a mounted 2,500-block document. Chromium must expose explicit garbage
collection and precise heap information; the dedicated Playwright configuration
supplies both flags.
