# Loomark production E2E

This directory contains the Playwright boundary for the Warren production
release. Production tests interact only with the visible Text editor and browser
storage; they do not expose a test-only control path in the application.

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

The same script also builds the test-only `examples/sidebar_fixture` entry into
`apps/loomark/.sidebar-e2e-dist` and runs `sidebar.spec.ts`. This fixture imports
Loomark's copied Sidebar with `mobile=true` to cover child-origin keyboard events,
focus wrapping, disabled controls, Escape, and repeated close/reopen. It uses the
existing Warren/Playwright server boundary; no fixture route or code is included
in production `dist`.