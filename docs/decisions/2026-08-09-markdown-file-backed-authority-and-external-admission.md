# Markdown file-backed authority and external admission

**Date:** 2026-08-09

**Status:** Accepted target architecture; implementation not started

**Related:**

- [EGW staged publication responsibility boundary](2026-08-09-egw-staged-publication-responsibility-boundary.md)
- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
- [Local-first document ownership](../design/local-first-document-ownership.md)

**Reader:** Maintainers designing or reviewing Markdown persistence, external editor admission, or File Authority behavior in Loomark.

**Decision:** Split persistence into Archive-backed and File-backed capabilities. With a continuing File association, the Markdown body file is File Authority for portable content; accepted operation history remains Causal Authority for causal order and identity. Archive-backed exports are unassociated portable artifacts, and reading one creates a new Editing Document identity and causal history baseline through Import Markdown unless synchronized Metadata supports Join Existing Editing Document. Associated external changes preserve Editing Document identity through External admission.

**Keep until:** Permanently. ADRs are durable and are superseded rather than deleted.

**Disposition:** Supersede this record if implementation evidence shows that External admission cannot remain deterministic and bounded, or if File Authority and Causal Authority cannot remain separate scopes.

## Context

The local-first document ownership design establishes that text alone does not preserve identity or causal history, and that persisting the operation history is the rule. It distinguishes four authorities (Causal, Current state, Portable artifact, Derived caches) and states that a `.md` changed by an outside tool re-enters as an explicit import, never as a merge between two truths.

This ADR refines that design by distinguishing two persistence modes and introducing External admission as a narrowly scoped exception to the "edits arrive as edits" rule for file-backed editing with external tools.

Implementation evidence:

- [Local-first document ownership](../design/local-first-document-ownership.md)
- [EGW staged publication responsibility boundary](2026-08-09-egw-staged-publication-responsibility-boundary.md)
- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)

These sources establish the need to preserve Editing Document identity and causal history across writing instances and the separate staged-publication path for Resolution candidates. File association continuity and External admission are decisions introduced by this ADR; the cited evidence does not yet prove that External admission can remain deterministic and bounded.

## Partial supersession

This ADR partially supersedes two statements in the local-first document ownership design:

1. Universal Import Markdown treatment for every outside-modified `.md`. In File-backed persistence, an associated external change preserves Editing Document identity through External admission. An unassociated `.md` still follows Import Markdown.

2. Universal prohibition on snapshot inference. External admission is a narrowly scoped external-boundary exception for File-backed persistence only. The rule remains absolute for all Loomark-originated input paths.

This ADR does not supersede any other part of the local-first design. Causal-history durability, source-equal history persistence, the archive envelope, writer identity, restore limits, and parser-losslessness remain unchanged.

## Persistence modes

### Archive-backed persistence

No Markdown body file is associated with the Editing Document. The application-owned archive retains durable content and Metadata preserves the Causal Authority. Exported Markdown is an unassociated portable artifact. Opening it follows Import Markdown: a new Editing Document and a new causal history baseline, unless explicit synchronized Metadata supports Join Existing Editing Document.

### File-backed persistence

A continuing File association links the Editing Document to a Markdown body file. The associated body file is File Authority for portable content at open, save, and external-change admission. Accepted operation history remains Causal Authority for causal order, Editing Document identity, and writer identity; File Authority does not determine either.

Safe file replacement is required for writable File-backed persistence. Without it, Loomark limits the association to read-only access and offers Archive-backed editing, Export Markdown, or Choose New Location.

## External admission

### What it is

External admission is the deterministic bounded multi-span conversion of an admitted external file's final text, relative to the File baseline, into inferred causal edits that preserve unchanged spans and produce the exact external source. It preserves Editing Document identity but never claims to recover the external editor's original operations or intent.

### Requirements

**UTF-16 validation.** External admission validates sentinel-free UTF-16 boundaries before inference. Invalid boundaries reject admission and enter Content conflict.

**Resource budget.** External admission uses a resource budget. Exceeding the budget falls back to one contiguous replacement, which must also satisfy receiver admission limits before any mutation. If no inferred batch — including the contiguous-replacement fallback — fits within receiver admission limits, apply nothing, preserve the Observed external variant, and enter Content conflict. The budget is receiver policy, not a property of the format.

**Exact replay.** External admission requires exact replay verification: applying the inferred edits to the File baseline must produce the exact admitted external source. Mismatch rejects admission and enters Content conflict.

**Coordinator writer.** External admission uses the stable synthetic Coordinator writer of the Editing Document's Aggregate Markdown runtime. The same writer may generate other application operations, whose category and provenance are recorded in application Metadata. It persists across reopen and never represents an external person, editor, or tool.

**Atomic transaction.** External admission is an optimistic atomic transaction against its expected causal version and File baseline. A match applies every inferred edit exactly once under the Coordinator writer and records one application-level undo group. A mismatch applies none, preserves the Observed external variant, and enters Content conflict without re-diffing against the newer Loomark source.

### What it is not

External admission is not Import Markdown. Import creates a new Editing Document; External admission preserves the existing one.

External admission is not operation reconstruction. It infers bounded multi-span edits from a final text, not the external editor's actual operations or intent.

External admission is not a relaxation of "edits arrive as edits" for Loomark input paths. The rule remains absolute for user actions within Loomark. Snapshot inference is a narrowly scoped external-boundary exception only.

## External concurrency uncertainty

After a Loomark source change in an active Editing Document lifetime, a plain external file write cannot prove which prior content its writer observed. External concurrency uncertainty sends such a write to Content conflict rather than silently replacing the Loomark variant. Close and reopen resets the uncertainty against the newly acknowledged file.

Generic plain files cannot reveal writer IDs or causal parents. External concurrency uncertainty and Observed-variant preservation prevent silent overwrite.

## File association and identity

External file relocation updates the File association after a rename or move without changing the Editing Document's identity or causal history.

An unassociated `.md` — whether copied, exported, or never associated — follows Import Markdown. Opening a cloned Markdown body file without synchronized Metadata creates a new Editing Document even when another device edits equivalent content.

## Rejected alternatives

### Universal `.md` authority

Rejected because it would conflate File Authority for portable content with Causal Authority for causal history and identity. A `.md` cannot reconstruct causal history; only Metadata preserves it.

### Automatic rebase on mismatch

Rejected because External admission is an optimistic atomic transaction. A mismatch against the expected causal version or File baseline must apply none and enter Content conflict without re-diffing against the newer Loomark source. Automatic rebase would silently apply partial changes and lose the Observed external variant.

### External admission for Loomark input paths

Rejected because it would relax the "edits arrive as edits" rule for user actions within Loomark. The rule must remain absolute for Loomark-originated paths; snapshot inference is a narrowly scoped external-boundary exception only.

### Operation reconstruction

Rejected because External admission cannot recover the external editor's actual operations or intent. It infers bounded multi-span edits from a final text relative to a File baseline. Claiming operation reconstruction would overstate what is possible and misrepresent the synthetic writer's provenance.

### Claim stable support before External admission is deterministic and bounded

Rejected because External admission must remain deterministic and bounded under resource limits. Incubating with File-backed persistence evidence prevents premature commitment.

## Consequences

- File Authority and Causal Authority are separate scopes. File Authority settles portable content at file-backed open, save, and external-change admission. Causal Authority settles causal order, Editing Document identity, and writer identity.
- External admission preserves Editing Document identity for associated external file changes. It does not create a new Editing Document.
- External admission is deterministic and bounded. It validates UTF-16 boundaries, uses a resource budget, and requires exact replay. Exceeding the budget falls back to one contiguous replacement, which must also satisfy receiver admission limits before any mutation. If no inferred batch fits, apply nothing, preserve the Observed external variant, and enter Content conflict.
- Coordinator writer plus application records preserve synthetic provenance without treating writer identity as an operation category.
- External admission is an optimistic atomic transaction. A mismatch applies none and enters Content conflict without re-diffing against the newer Loomark source.
- External concurrency uncertainty prevents silent overwrite after a Loomark source change. An external write in this condition enters Content conflict.
- A rename or move of an associated file preserves Editing Document identity via File association.
- An unassociated `.md` follows Import Markdown. Synchronized Metadata is required for Join Existing Editing Document.
- The local-first design's causal-history durability, source-equal history persistence, archive envelope, writer identity, restore limits, and parser-losslessness remain unchanged.

## Non-goals

- Implementing or moving code in this documentation change.
- Changing EGW core or the collaboration runtime.
- Defining the archive envelope format or Metadata persistence.
- Specifying Loomark's Autosave policy, conflict resolution UX, or Resolution workspace lifecycle.
- Claiming stable External admission support before it is deterministic and bounded under resource limits.
