# Changelog

All notable changes to `@canopy/editor-adapter` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `CM6Adapter` now applies `SetDiagnostics` patches as inline `cm-diagnostic cm-diagnostic-${severity}` marks with native-tooltip `title` and `data-severity` attributes. `static extensions()` returns the new diagnostic field + plugin alongside the decoration pair. (#227)

### Changed
- `UserIntent` cursor intents are now unit-specific: `SetPmCursor(pm_tree_position)` for ProseMirror tree positions and `SetDocCursor(doc_code_unit_offset)` for document code-unit offsets replace the ambiguous `SetCursor(position)` shape.
- `cm6-adapter.ts`: `DecorationSet` and `ViewUpdate` are now imported with `import type`, fixing the build for downstream TypeScript projects with `verbatimModuleSyntax: true` (a Vite/SvelteKit default).
- `cm6-adapter.ts`: `PeerCursorWidget.{eq, toDOM, ignoreEvent}` now carry the `override` modifier, fixing the build for downstream projects with `noImplicitOverride: true`.

## [0.1.0-alpha.0] - 2026-05-13

### Added
- `README.md` documenting the package boundary, public API stability tiers, wire-format invariants, and extension points.
- `CHANGELOG.md` (this file).

## [0.0.0] - Initial

- Internal-only release. `ViewPatch` / `UserIntent` protocol types and CM6, ProseMirror, and HTML adapters in use by Canopy demos.
