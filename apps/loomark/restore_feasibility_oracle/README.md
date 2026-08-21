# Gate R0 oracle boundary

This directory is a test-only, imperative consumer shell for Gate R0.  It
does not define an archive format or a Markdown API.

## Invariants

1. The canonical v1 archive bytes are the only source of truth for the
   full-history oracle.  A consumer is started in a distinct process with only
   those bytes and a fresh writer id; it receives no source editor, history
   object, `Ref`, operation log, or materializer alias.
2. The consumer opens bytes only through the existing `MarkdownEditor::open`
   façade and reports product observations (text, frontier, editability,
   recovery, and first-edit results).  It does not expose or recreate a
   Markdown-owned authority path.
3. EGW authority evidence is produced independently by its test-only process.
   Nushell joins the two versioned JSONL streams by `run_id` and `case_id`; no
   process shares live state with another.
4. Canonical-history provider reads are counted by the provider capability
   boundary (calls, operations, bytes, requested boundary).  Traversing an
   already-loaded candidate is recorded separately as an in-memory scan and
   can never satisfy a provider-read assertion.
5. A zero-read fast-path assertion is valid only after the known-positive
   control records exactly one provider call and positive operation and byte
   counts.  Any unresolved closure is a recorded explicit fallback, never an
   inferred fast path.
6. Candidate A (#1291), B (#1290), and C (#1292) are not evaluated by R0's
   oracle runner.  Each is recorded as `not_applicable`; this runner neither
   chooses nor implements a retained-state candidate.

The functional core maps serialized observations to deterministic artifacts
and failure classifications.  The Nushell runner is the imperative shell that
starts processes, writes files, and selects the fixed exit code.

## Existing API reuse check

The consumer reuses `MarkdownEditor::open` (fresh writer plus complete-history
admission) and `LoomarkDocumentArchive::decode_json_string` (v1 validation),
rather than adding an archive or authority restore API.  The EGW probe uses
`TextState::new`/`SyncSession::apply` for local authority behavior and
`SyncMessage::to_canonical_bytes` for byte accounting.  Core `Json` parses and
serializes the process handoff; `String` is retained only for opaque archive
bytes.  No new public helper or mutable authority collection is introduced.
