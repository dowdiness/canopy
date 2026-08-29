# Loomark separates current and saved text

**Date:** 2026-08-24

**Status:** Accepted

**Issue:** [#1162](https://github.com/dowdiness/canopy/issues/1162)

**Related:**

- [Loomark production E2E boundary](2026-08-24-loomark-production-e2e-boundary.md)
- [Standard Rabbita Text app](../plans/2026-08-24-loomark-standard-rabbita-text-app.md)
- [Loomark Source repository](2026-08-29-loomark-source-repository.md), which
  supersedes this decision's original single-record recovery details
- [#1347 — bound local saving without entering Text input tasks](https://github.com/dowdiness/canopy/issues/1347)

## Context

Loomark's immediate product is a fast, comfortable, private single-user Markdown editor. Earlier specifications made every visible edit immediately advance complete editing history and prepare an archive of that history. Real-browser measurements showed that this work cannot satisfy the interactive target: complete history work can take orders of magnitude longer than one input task, and even Markdown parsing can exceed the budget on larger documents.

The product therefore distinguishes the current Document text, the Saved text that can be recovered after reopening, and the optional complete editing history required for collaboration. Treating them as one saving guarantee either makes typing slow or makes saving claims dishonest. The current text itself does not need separate draft and accepted copies: Text mode and Block mode update one Document text directly, while saving and Preview generation may follow later.

## Decision

Production Loomark uses these values:

1. **Document text** — the current Markdown text of the Loomark document. Text mode and Block mode update it immediately; Preview mode renders it after parsing.
2. **Saved text** — the latest Document text successfully written to browser storage together with the Loomark document identity. Browser storage does not preserve edit history or undo across page reloads.
3. **Complete editing history** — optional information needed for collaboration, cross-window undo, or exact replay. The current production input and browser-storage paths do not prepare or save it.

The Text input task has a hard p95 and maximum target of 10 ms. Updating the Rabbita Model with the new Document text belongs to that task. Markdown parsing, history mutation, hashing, JSON encoding, archive preparation, browser-storage work, and Preview generation must not execute synchronously in that task. Frame latency is measured separately.

IME composition updates the same Document text shown in Text mode. Saving and Preview generation wait until composition ends. They do not require a second text value in the Model.

Browser saving is trailing: after input becomes quiet, the latest Document text is written to browser storage. #1347 tracks continuous-typing max-wait and page-lifecycle handling, which must remain outside the input task. Until implemented, the UI and documentation must not claim a bounded crash-loss window during uninterrupted typing.

Preview parsing also waits until input becomes quiet. Switching to Preview requests parsing of the latest Document text immediately. The delay is selected from production E2E measurements and user-visible behavior rather than fixed by this decision.

Complete editing history is added only for an explicit collaboration or history-continuity requirement and only after its evidence gate passes. Adding it must preserve the Text input budget and keep history preparation outside ordinary input.

The current release exposes Text mode only. Block mode and Preview mode remain product features, not development features, but return to the product UI only after they meet their performance and consistency requirements.

## Consequences

- There is one current Document text in the Rabbita Model, not separate draft and canonical copies.
- Saving and Preview may lag behind Document text independently.
- A crash before saving completes may lose changes that are present in Document text.
- A save failure leaves Document text editable, shows that changes are not saved, and permits an explicit Retry.
- Once saving completes, reopening restores the exact Saved text and Loomark document identity.
- When the Source repository has no valid document, Loomark creates the
  baseline defined by the later Source repository decision.
- Record-level corruption is preserved and isolated when another valid Source
  can open; repository-wide access, migration, identity, or authoritative-write
  failure enters Recovery.
- Reopening does not restore prior undo history or internal block identities.
- Browser-based Text mode uses LF line terminators. Exact imported-file terminators require a separate file capability.
- A catalog of Loomark documents can be built without waiting for complete editing-history storage.
- Exceeding the measured 10 ms Text input limit is a product correctness failure.
- Until Block mode and Preview mode satisfy their gates, the release contains no unreachable mode UI or mode-specific application branches.
- The Model needs no revision, generation, or sequence value unless a measured implementation demonstrates an ordering problem that Rabbita, cancellation, serialization, or direct input comparison cannot solve.

## Rejected alternatives

**Save complete editing history after every edit.** Rejected because its cost is incompatible with the Text input objective and it couples ordinary local recovery to future collaboration requirements.

**Keep separate draft and accepted text values.** Rejected because Markdown input updates the current Document text directly. Saving, parsing, and Preview can be delayed independently without duplicating the text in the Model.

**Parse Markdown synchronously on every Text input.** Rejected because parsing may exceed the input budget on larger documents. Preview parsing waits until input is quiet or Preview is selected.

**Claim bounded saving from trailing debounce alone.** Rejected because continuous input can postpone a trailing callback indefinitely.

**Ship Block mode and Preview mode as hidden development paths.** Rejected because both are product features. They are omitted from the current release until their product requirements are met, then restored through ordinary user-facing behavior and production E2E coverage.
