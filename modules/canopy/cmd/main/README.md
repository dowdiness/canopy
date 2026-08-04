# cmd/main

Native CLI demo of the editor. Runs two scenarios on launch: a convergence demo (`run_convergence_demo`) that exercises CRDT merge between simulated peers, and an interactive lambda REPL (`run_repl("alice")`).

This is the only executable in the canopy module (`options.is-main: true`). It is built by the workspace's `moon build --release` and is the simplest way to drive the editor without a frontend.

## Public API

The package compiles to a binary and has no library surface to import. The implementation files (`main.mbt`, `demo.mbt`, `repl.mbt`) are not callable from outside.

## Consumers

None — this is the top of the dependency tree. Run with `moon run cmd/main` from the workspace root.

## Dependencies

- `dowdiness/canopy/editor`
- `dowdiness/event-graph-walker/text`
- `dowdiness/lambda` (parser, from the loom submodule)
- `dowdiness/pretty` (loom submodule)

## Stability

Internal demo. Not part of the release artifacts (`scripts/package-release.sh` packages the FFI / web outputs, not this CLI). Expect breaking changes whenever the editor's MoonBit API moves.

## Notes

The REPL is line-oriented (read → parse → evaluate → print). It is primarily useful for debugging parser / evaluator changes without booting the web demo; for that purpose, prefer the per-package tests over the REPL when iterating.
