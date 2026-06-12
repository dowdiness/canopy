# FFI Export Manifest (Parallel-Run)

Status: parallel-run since S4 PR2 (see
`docs/plans/2026-06-12-s4-ffi-host-extraction.md` Step 6).

## What it is

`examples/ideal/export-manifest.json` declares the expected FFI export
surface of the lambda app seam:

- `ffi_exports` — the symbols `ffi/lambda/moon.pkg` must export to JS
- `app_reexports` — the subset the ideal app re-exports through
  `examples/ideal/main/crdt_reexport.mbt` wrappers and the
  `examples/ideal/main/moon.pkg` export array

`scripts/check-export-manifest.mjs` (run in CI's Dependency Rules job and
locally via `node scripts/check-export-manifest.mjs`) parses the two
`moon.pkg` brace export lists and the wrapper file's `pub fn` definitions,
then reports symbol-level discrepancies in each direction — manifest-only,
moon.pkg-only, and wrapper-only — plus duplicates and the seam invariant
that every app re-export exists in the FFI export surface.

## Parallel-run contract

During parallel-run the **hand-maintained files remain authoritative**:
`ffi/lambda/moon.pkg`, `examples/ideal/main/crdt_reexport.mbt`, and
`examples/ideal/main/moon.pkg`. The manifest is a declared mirror that makes
drift between the layers visible; it is not code-generated and nothing is
generated from it. Codegen or wrapper deletion is reserved for the S4 PR3
decision, gated on at least one release of this parallel-run.

## When the check fails

The failure names the exact symbol and the layer it is missing from. Fix the
live file if the symbol is a real discrepancy (a forgotten export or
wrapper), or update `examples/ideal/export-manifest.json` if the seam
intentionally changed. Do not weaken the check.
