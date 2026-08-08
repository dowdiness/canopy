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

## Framework — projection editing

Framework vocabulary for the projection engine that backs the application terms above. Distinct from the Loomark document domain: these describe how the editing session's tree keeps identity across reparses, not how documents persist.

**Reconciliation**:
The identity-preserving match between the previous projection tree and the newly reparsed tree: it decides, for each node in the new tree, whether it is the same node as one in the old tree (carrying its NodeId) or a fresh node. It is not text diffing and not CRDT merge.
_Avoid_: Merge, diff, CRDT merge

**Identity evidence**:
What reconciliation may consult when deciding that a new node is the same as an old node: sibling position (positional), a structural-edit hint (hint-directed), or a payload fingerprint (exact-key). The three kinds are a closed public set — the surface offers no hints+exact-key combination — but each mode combines its own evidence with positional LCS internally, and fallback matching preserves sibling order rather than strict position.
_Avoid_: Matching mode, strategy, policy record

**Fresh identity**:
A newly allocated NodeId, given to a node that reconciliation cannot match to any previous node — including fresh nodes at unmatched positions and nodes whose old identity retired or was ambiguous (Replace / Move / unresolved wrap). The counterpart of preserved identity, where a node keeps its previous NodeId across an edit.
_Avoid_: Identity carry (as a noun), id retention
