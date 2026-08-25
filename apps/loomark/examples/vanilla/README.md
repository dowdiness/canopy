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
