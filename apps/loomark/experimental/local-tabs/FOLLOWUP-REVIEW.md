# Historical follow-up review — before work resumed

> Preserved from the source-only handoff prepared on 2026-10-03. “Open,”
> “UNTESTED,” and “pending” below describe that snapshot, not the current PR.
> For current dispositions, see [the handoff](CODEX_HANDOFF.md#original-findings-and-current-disposition);
> exact-commit verification is recorded on [PR #1450](https://github.com/dowdiness/canopy/pull/1450).

## Additional open regression: composition commit during Worker recovery

Independent review identified a source-level loss path: Worker loss sets ready=false; old
onChange silently rejected the terminal composition TextChange; then composition
ended and an empty queue allowed open to overwrite the textarea with restored
text. Read-only during restore does not cancel an already active OS composition.

A minimal UNTESTED onChange guard correction has been applied: a session with
an existing accepted basisVersion retains native TextChanges even while not
ready. Initial opening with no accepted basis still rejects input; blocked error
states remain blocked. The original s.text is used as before, terminal DOM text
as after, and the intent stays in the existing ordered queue. Consequently open
must not overwrite the draft while the queue is nonempty, and replay uses the
retained accepted basis before that queued command. No runtime result is claimed.

Required regression remains pending: begin synthetic composition; crash Worker;
delay the open response; commit composition before Ready; assert draft and exact
command are retained, no premature Saved, then original-basis application once,
one durable packet/operation union, peer convergence, save/reopen. Include queued
input before composition and remote changes during recovery. Actual OS IME still
requires supported CUA access. This change is not in the original ZIP; it is included in this handoff from the separately recovered source file.

## Additional open finding: one native command / one Undo capture

Independent ZIP review reports worker.mjs converts a full TextChange
into multiple snapshot diff replacements, while engine/main/main.mbt establishes
an Undo capture boundary for every replacement. If those boundaries are as
reported, a single ReplaceAll fallback such as cat -> dog may capture deletion
and insertion separately: one Undo can remove dog without restoring cat.

The source read attempted after this report failed with the same deny-read ACL
initialization error. No capture-group code change or runtime verification has
been performed. Keep this as an open correctness finding, not a completed fix.

Proposed smallest change, subject to source confirmation: establish one capture
boundary before the replacement loop and one after the entire native command,
and remove per-replacement capture boundaries on that path. Keep remote packet
application outside local Undo recording. Keep separate native commands in
separate capture groups. Ensure exceptional exit closes the capture boundary;
failure must still preserve the unaccepted intent rather than publish success.

Required regression: force the actual native full TextChange/ReplaceAll fallback
for cat -> dog; verify one Undo restores cat and one Redo restores dog, including
peer convergence and save. Add a disjoint multi-span fallback with unchanged
middle text and Unicode, and two successive native commands to prove each takes
one Undo separately. Test the fallback path itself, not ordinary selection input
which may emit a single replacement and miss this defect.

The original ZIP, version 0, 7,598,071 bytes,
is the earlier validated snapshot. It does NOT include the following source edits.
Its SHA256 is 210cc02beb0f20115a6792b342d91fed8f5a815bc693e3f94ea3b52c0b728300.
The earlier measurement artifact was not changed.

After the initial validation, third-party review identified a source-level
ordinary-error path: a history request may execute, then fail before main accepts
its packet. Retrying it on a fresh Worker/empty UndoManager could silently turn
it into a no-op. This has not yet been reproduced by executing the new regression.

Changes in client.mjs now classify ANY failed queued history request as unresolved,
not only WorkerLost. Ordinary Retry retains the exact request and read-only,
Not saved state. A separate Cancel interrupted Undo/Redo action requires an
explicit confirmation before removing it. Dismissing confirmation changes nothing.
The existing accepted text is retained; cancellation does not perform Undo.

| Boundary | Text and history | Dirty state and recovery |
|---|---|---|
| Before Worker execution, no accepted response | Main still shows accepted text; request remains queued. Worker execution cannot generally be distinguished from lost response. | Unresolved, read-only, Not saved. Retry retains request. |
| Applied in Worker, before main acceptance | Only volatile Worker editor/Undo state may have changed. Main has not authorized save. Main accepted text remains. | Same unresolved state. Explicit cancellation starts a fresh Worker at accepted basis, discarding volatile result and old Undo stack. |
| Main accepts immutable packet, before commit | Main applies Undo result, retains exact packet, removes command queue entry. | Saving/Not saved on fault; recovery retransmits same packet IDs, never reruns Undo. |
| Transaction committed, before ACK | Main still retains exact packet; durable receipt records it. | Still Saving until matching commit confirmation. Retry deduplicates receipt and then clears only that packet. |
| Matching ACK accepted | Result is durable. | Saved only if no later input/packets/composition/failure remains. |

The cancellation button is intentionally not an exactly-once Undo recovery claim.
Unaccepted Undo has no durable packet or recoverable UndoManager snapshot. The
request remains in this live tab's memory and unload warns; abrupt process loss
does not retain that intent. Persisting unresolved commands and providing a
supported portable Undo checkpoint would require further protocol/storage work.

New regressions in fault-test.mjs cover: Retry retains command identity; native
input is blocked; dismissing cancellation preserves it; confirming cancellation
restores accepted text; and an ordinary error injected after actual Worker
history execution but before main acceptance. These tests are ADDED, NOT RUN.

## Selection: known actual risk

The current numeric/text-alignment fallback is not a stable CRDT cursor anchor.
In repeated text it can choose another identical character's provenance. In a
large bounded fallback replacement it can move a caret/range within the replaced
span to the replacement end. Thus users can observe selection movement; no
claim of universal caret stability is justified. Keeping numeric scrollTop
also does not keep the same content visually anchored after lines above change.

Existing passed coverage: UTF16/emoji, distant changes, repeated-character test,
backward selection and numeric scroll preservation, plus inactive-document
selection mapping for a prefix insertion (A-B-A). Those tests establish specific
examples, not provenance correctness. Focused ambiguous repetition and fallback
tests should state expected limitations rather than assert impossible anchors.

## Execution/publication blockers

Reconnection command execution failed with:
`exec-server rejected request (-32603): helper_unknown_error: apply deny-read ACLs`.
apply_patch remains available, so the changes above were applied, but commands,
new file searches, syntax checks and browser regressions could not run.

The requested deeper task-local just/lefthook scan is still pending this blocker.
Previous PATH/common installed locations did not contain either tool. Existing
GitHub CLI attempt was `gh auth status`; it failed reading
`GitHub CLI config: Access is denied`.
No alternate config, credentials or permission bypass was attempted.

Historical recommendation: do not promote this tree to implementation-ready
until the new regressions and normal gates run. The user subsequently requested
a draft-only Codex handoff; see CODEX_HANDOFF.md for the publication exception. Existing
388 module tests and browser measurements describe the earlier validated source.
