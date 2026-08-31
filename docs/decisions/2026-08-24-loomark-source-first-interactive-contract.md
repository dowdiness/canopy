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

The product therefore distinguishes the current Document text, the Saved text
that can be recovered after reopening, and the optional complete editing history
required for collaboration. Treating them as one saving guarantee either makes
typing slow or makes saving claims dishonest. The current text itself does not
need separate draft and accepted copies: Text input updates one Document text,
while saving and Preview generation may follow later.

## Decision

Production Loomark uses these values:

1. **Document text** — the current Markdown text of the Loomark document. Text
   input updates it immediately; Preview and Split render the same text after
   parsing.
2. **Saved text** — the latest Document text successfully written to browser storage together with the Loomark document identity. Browser storage does not preserve edit history or undo across page reloads.
3. **Complete editing history** — optional information needed for collaboration, cross-window undo, or exact replay. The current production input and browser-storage paths do not prepare or save it.

The Text input task has a hard p95 and maximum target of 10 ms. Updating the Rabbita Model with the new Document text belongs to that task. Markdown parsing, history mutation, hashing, JSON encoding, archive preparation, browser-storage work, and Preview generation must not execute synchronously in that task. Frame latency is measured separately.

IME composition updates the same Document text shown in Text mode. Saving and Preview generation wait until composition ends. They do not require a second text value in the Model.

Browser saving uses two eligibility paths: 250 ms trailing quiet and one
non-restarting 2,000 ms maximum-wait timer per dirty checkpoint epoch. The
maximum message runs at the first event-loop opportunity at or after its delay;
it does not guarantee IndexedDB acknowledgment, physical-media flush, or page
termination completion. Hidden visibility makes current pending text eligible
as a best effort. At most one Source write and one newer text-free checkpoint
exist, and completion promotes latest text only when that checkpoint is already
eligible. Each dirty interval has a private checkpoint epoch. Each deferred
committed edit advances a private quiet revision, allowing delayed quiet work
to reject equal-text ABA without retaining candidate text.

Preview parsing also waits until input becomes quiet. Switching to Preview requests parsing of the latest Document text immediately. The delay is selected from production E2E measurements and user-visible behavior rather than fixed by this decision.

Complete editing history is added only for an explicit collaboration or history-continuity requirement and only after its evidence gate passes. Adding it must preserve the Text input budget and keep history preparation outside ordinary input.

The current release exposes Text, Preview, and Split modes. Preview and Split
preserve the same textarea and current Document text while showing a read-only
derived Preview. Block mode remains outside the product until it meets its
performance and consistency requirements.

## Consequences

- There is one current Document text in the Rabbita Model, not separate draft and canonical copies.
- Saving and Preview may lag behind Document text independently.
- A crash before saving completes may lose changes that are present in Document text.
- Exact return to acknowledged or in-flight text removes redundant pending
  persistence while retaining one current Document text authority.
- A save failure leaves Document text editable. It shows that changes are not
  saved and permits explicit Retry while current text differs from the
  acknowledged Source; exact return to that Source is truthfully `Saved`
  without another write.
- Once saving completes, reopening restores the exact Saved text and Loomark document identity.
- Uncancelled quiet and maximum messages are fenced by Activation and
  checkpoint epoch. Quiet additionally requires the latest monotone quiet
  revision, so an equal-text ABA path cannot validate an older timer.
- Hidden-page persistence is best effort because the browser may freeze or
  terminate before transaction completion.
- When the Source repository has no valid document, Loomark creates the
  baseline defined by the later Source repository decision.
- Record-level corruption is preserved and isolated when another valid Source
  can open; repository-wide access, migration, identity, or authoritative-write
  failure enters Recovery.
- Reopening does not restore prior undo history or internal block identities.
- Browser-based Text mode uses LF line terminators. Exact imported-file terminators require a separate file capability.
- A catalog of Loomark documents can be built without waiting for complete editing-history storage.
- Exceeding the measured 10 ms Text input limit is a product correctness failure.
- Text, Preview, and Split are reachable product modes over one current
  Document text. The release contains no hidden Block-mode branch.
- Activation generation distinguishes document ownership. A private checkpoint
  epoch distinguishes dirty intervals, while a private quiet revision
  distinguishes edits within one interval because Rabbita's delayed commands
  are not cancelled.

## Rejected alternatives

**Save complete editing history after every edit.** Rejected because its cost is incompatible with the Text input objective and it couples ordinary local recovery to future collaboration requirements.

**Keep separate draft and accepted text values.** Rejected because Markdown input updates the current Document text directly. Saving, parsing, and Preview can be delayed independently without duplicating the text in the Model.

**Parse Markdown synchronously on every Text input.** Rejected because parsing may exceed the input budget on larger documents. Preview parsing waits until input is quiet or Preview is selected.

**Claim bounded saving from trailing debounce alone.** Rejected because continuous input can postpone a trailing callback indefinitely.

**Ship product modes as hidden development paths.** Rejected. Preview and Split
are ordinary user-facing modes with production E2E coverage. Block mode is
absent rather than maintained as an unreachable branch.
