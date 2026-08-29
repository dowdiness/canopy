# Loomark standard Rabbita Text app

**Status:** Active for Text-mode scope. Preview/Split scope moved to
[2026-08-26-loomark-preview-split-production.md](2026-08-26-loomark-preview-split-production.md)
(#1372). This plan remains authoritative for Loading, Autosave, Recovery,
and the production E2E suite. Its "no Parser" statement now means that a
session remaining in Text mode creates no Parser; the new plan owns lazy
Preview preparation after Preview or Split is selected. The original
single-`active` storage contract is superseded by
[the Source repository decision](../decisions/2026-08-29-loomark-source-repository.md)
and #1303.

## Goal

Loomark is a Text editor that restores and Autosaves one Loomark document in
browser storage. It uses Rabbita's standard `Model`, `Msg`, `update`, and `view`
shape. The implementation contains no private Driver, development host, hidden
DOM protocol, projection runtime, Parser, or Worker.

## Product state

```text
Model
  Loading
  Editing(EditingState)
  Recovery(OpenFailure)

EditingState
  document_id : String
  text : String
  composing : Bool
  save : SaveState

SaveState
  Saved
  Waiting
  Saving(String)
  Failed(SaveFailure)
```

`Saving(String)` is the only in-flight save candidate. On completion, the app
compares that candidate directly with the current text. If they differ, it
saves the latest text next. There is no revision counter, generation token, or
pending queue.

Composition updates the visible text immediately. Autosave waits until
composition ends.

## Modules

```text
apps/loomark/
  app/
    app.mbt
    model.mbt
    update.mbt
    view.mbt
  internal/source_repository/
    storage.mbt
    reconciliation.mbt
    source_codec.mbt
  main/
    main.mbt
  cmd/
    browser -> ../main
```

`main` only mounts `@app.app`. `cmd/browser` is Warren's standard browser-entry
path and is a symlink to that single entry package; it contains no application
logic.

The Source repository exposes command boundaries for opening a reconciled
`RepositorySnapshot` and saving one accepted Source against the in-memory
Catalog. The package owns IndexedDB configuration, complete-store scanning,
strict codecs, document ID allocation, legacy migration, catalog derivation,
and storage error classification. No caller knows its database, store, or key
names.

## Storage contract

The database remains `loomark`, version `1`, with object store `documents`.
Each `source/v1/<document-id>` value retains the strict two-field
`document_id`/`text` shape and is independently authoritative. Opening derives
the complete in-memory Catalog from a full Source scan; no Catalog record is
persisted.

An empty repository creates a UUID-backed Source containing exact text
`# Untitled\n`. The former `active` value is migrated with one atomic Source put
and legacy delete when no conflicting target exists. Corrupt, unsupported, and
unknown records are preserved and reported rather than overwritten. A normal
save writes only its accepted Source and advances the in-memory Catalog after
transaction completion.

## Autosave

- Text input updates `EditingState.text` synchronously.
- A 250 ms quiet period requests a save.
- At most one browser-storage write is in flight.
- Stale delayed requests do nothing.
- A successful stale write is followed by one write of the latest text.
- Composition suppresses save requests until composition ends.
- A failed write preserves the current text and exposes Retry.
- Retry writes the latest text; it does not replay an old candidate.

## Production E2E boundary

Playwright operates only the Warren production release and verifies:

1. A fresh browser opens an empty focused Text editor without tabs or Workers.
2. Autosave restores exact text and document identity after reload.
3. Rapid input writes only the latest text.
4. IME composition saves only after composition ends.
5. Save failure preserves editing; Retry saves the latest text.
6. Invalid stored data opens Recovery without overwriting it.
7. Text input processing has p95 and maximum duration at or below 10 ms.

The release script builds only the production bundle. Unexpected JavaScript,
capability Worker, projection Worker, private Driver names, development-host
names, and test URL gates fail the release test.

## Removed implementation

The Text app does not retain the former Loomark packages for archive history,
Driver orchestration, private Rabbita integration, development hosting,
projection execution, restore feasibility, repository migration, or Worker
entry points. CI contains only the production E2E lane.

## Failure discipline

If a build, test, or runtime failure cannot be reproduced and its cause cannot
be identified, implementation stops. Do not add a retry, fallback, alternate
path, compatibility layer, or suppression to make an unexplained failure pass.
Temporary diagnostic instrumentation is allowed only to identify the cause and
must be removed afterward.

## Validation

```bash
cd apps/loomark
NEW_MOON_MOD=0 moon test internal/source_repository app --target js --release
NEW_MOON_MOD=0 moon check internal/source_repository app main --target js
NEW_MOON_MOD=0 moon fmt internal/source_repository app main
NEW_MOON_MOD=0 moon info internal/source_repository app main

cd ../..
./scripts/test-loomark-standalone-e2e.sh
moon check
moon test
```

After `moon info`, inspect generated `.mbti` files. The only public Loomark app
interface is `app() -> @rabbita.Val[@rabbita.Html]`; Source repository API
drift must match its generated interface and the accepted Source repository
ADR.
