# Canopy and Loomark

Canopy provides incremental, causally ordered document editing; Loomark is the Markdown writing application built on it. This glossary distinguishes durable document ownership from one running editing session.

## Language

**Loomark document**:
A logical Markdown document whose identity and causal history continue across writing instances.
_Avoid_: File, buffer, session

**Document archive**:
An application-owned recovery value containing a Loomark document's logical identity, portable Markdown, and opaque causal history.
_Avoid_: Snapshot, session snapshot, save file

**Active document**:
The sole Loomark document selected for the current standalone application while document catalogs and document switching remain unavailable.
_Avoid_: Current file, active session, recent document

**Baseline archive**:
The first complete archive that establishes a new active document's logical identity before its first history-changing commit.
_Avoid_: Empty snapshot, default file

**Local archive repository**:
The single-device authority that retains the latest complete document archive for the standalone application's active document.
_Avoid_: Session store, backup, replica

**Local restore policy**:
The resource-admission policy used when reopening a device-owned document archive. It is distinct from policy for history received from another replica.
_Avoid_: Network limit, archive format limit

**Repository acknowledgment**:
Confirmation that one complete archive replacement finished successfully in the local archive repository. It describes one repository operation, not the current product durability state.
_Avoid_: Saved status, durable-local state

**History-changing commit**:
An accepted document commit that advances causal history, whether or not its resulting Markdown source differs from the prior source.
_Avoid_: Text change, source change

**History no-op**:
An accepted document commit that leaves causal history unchanged.
_Avoid_: Unchanged text

**Applied document**:
The current accepted in-memory document state, which may be newer than the last locally durable archive.
_Avoid_: Saved document, durable document

**Local durability**:
The condition in which the current accepted document version is represented by an acknowledged archive in the local archive repository.
_Avoid_: Applied, replicated, backed up

**Recovery-blocked**:
The condition in which an existing archive cannot be safely reopened and remains preserved while editing and replacement are withheld.
_Avoid_: Empty document, recovered, reset

**Writing instance**:
One active lifetime that writes operations under its own replica identity. Reopening a document starts a new writing instance while retaining the logical document identity.
_Avoid_: Document identity, user identity, browser identity
