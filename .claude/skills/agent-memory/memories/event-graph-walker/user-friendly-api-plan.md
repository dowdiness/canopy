---
summary: "User-friendly API + error architecture plan for event-graph-walker CRDT library - facade layer with TextDoc, SyncMessage, and TextError"
created: 2026-01-23
status: in-progress
tags: [api-design, error-handling, event-graph-walker, crdt]
related: [event-graph-walker/text/, event-graph-walker/document/, event-graph-walker/README.md]
---

# User-Friendly API Architecture for Event Graph Walker

## Goals

1. **Simplicity**: Single entry point (`TextDoc`), hide CRDT internals
2. **Discoverability**: Clear method grouping (editing, syncing, versioning)
3. **Ergonomics**: Opaque types prevent misuse, `SyncMessage` replaces awkward 2-param merge
4. **Progressive disclosure**: `advanced()` escape hatch for power users
5. **User-friendly errors**: Category + recoverability + actionable help

## Architecture Overview

```
Facade Layer (NEW: text package)
├── TextDoc      - Mutable working copy (wraps Document)
├── TextView     - Read-only historical view (wraps Branch)
├── SyncSession  - Sync operation grouping
├── SyncMessage  - Single sync payload (ops + heads)
├── Version      - Opaque version identifier (wraps Frontier)
├── Change       - Local edit result (wraps Op)
├── Pos / Range  - Type-safe positions
└── TextError    - User-facing errors with diagnostics
```

## Facade API Design

### TextDoc (Main Entry Point)

```moonbit
pub struct TextDoc { inner : @document.Document }

pub fn TextDoc::new(agent_id: String) -> Self
pub fn TextDoc::text(Self) -> String
pub fn TextDoc::len(Self) -> Int
pub fn TextDoc::insert(Self, Pos, String) -> Change raise TextError
pub fn TextDoc::delete(Self, Pos) -> Change raise TextError
pub fn TextDoc::version(Self) -> Version
pub fn TextDoc::sync(Self) -> SyncSession
pub fn TextDoc::checkout(Self, Version) -> TextView raise TextError
pub fn TextDoc::advanced(Self) -> @document.Document  // escape hatch
```

### SyncSession (Clean Sync Interface)

Replaces `merge_remote(Array[Op], Array[RawVersion])` with single message type:

```moonbit
pub fn SyncSession::export(Self) -> SyncMessage
pub fn SyncSession::export_since(Self, Version) -> SyncMessage
pub fn SyncSession::apply(Self, SyncMessage) -> Unit raise TextError
```

### TextView (Historical View)

```moonbit
pub fn TextView::text(Self) -> String
pub fn TextView::version(Self) -> Version
```

### Opaque Types

```moonbit
pub struct Pos(Int)           // Type-safe position
pub struct Range { start: Pos, end: Pos }
pub struct Version(...)       // Wraps Frontier internally
pub struct Change(...)        // Wraps Op internally
pub struct SyncMessage(...)   // Contains ops + heads
```

## Error Architecture

### User-Facing Error Type

```moonbit
pub enum TextError {
  InvalidPosition(pos~ : Int, len~ : Int)
  SyncFailed(reason~ : SyncFailure)
  VersionNotFound(version~ : Version)
  Internal(detail~ : String)
}

pub enum SyncFailure {
  MissingDependency(hint~ : String)   // "Sync more ops, retry"
  MalformedMessage                     // "Discard, quarantine peer"
}
```

### Diagnostic Methods

```moonbit
pub fn TextError::message(Self) -> String      // User-facing short message
pub fn TextError::help(Self) -> String         // Actionable guidance
pub fn TextError::debug(Self) -> String        // Full detail for logs
pub fn TextError::is_retryable(Self) -> Bool
```

### Error Categorization

| Error | Category | Recoverability | Help |
|-------|----------|----------------|------|
| `InvalidPosition` | InvalidInput | Recoverable | "Clamp to [0..len]" |
| `MissingDependency` | MissingDependency | Retryable | "Sync missing ops, retry" |
| `MalformedMessage` | ProtocolViolation | Unrecoverable | "Discard batch, isolate peer" |
| `VersionNotFound` | MissingDependency | Retryable | "Version may not be synced yet" |
| `Internal` | InternalBug | Unrecoverable | "Report bug with debug info" |

## Usage Example

```moonbit
import "dowdiness/event-graph-walker/text"

// Create document
let doc = text.TextDoc::new("alice")

// Edit
doc.insert(Pos::at(0), "Hello")
doc.insert(Pos::at(5), " World")

// Sync with peer
let msg = doc.sync().export()           // Send to peer
// ... network transfer ...
doc.sync().apply(msg_from_peer)         // Receive from peer

// Time travel
let old_view = doc.checkout(some_version)
println(old_view.text())

// Power user access
let raw_doc = doc.advanced()
let oplog = raw_doc.oplog
```

## Implementation Notes

### Internal Mappings

- `TextDoc.inner` → `@document.Document`
- `TextView` → wraps `@branch.Branch`
- `Version` → wraps `@causal_graph.Frontier`
- `Change` → wraps `@oplog.Op`
- `SyncMessage` → contains `Array[@oplog.Op]` + `Array[@causal_graph.RawVersion]`
- `TextError` → maps from `DocumentError` via `diagnose()` function

### Package Structure

```
event-graph-walker/
├── text/           # NEW: Facade layer
│   ├── text_doc.mbt
│   ├── sync.mbt
│   ├── view.mbt
│   ├── types.mbt
│   ├── errors.mbt
│   └── moon.pkg.json
├── document/       # Existing (internal)
├── branch/         # Existing (internal)
├── oplog/          # Existing (internal)
├── causal_graph/   # Existing (internal)
└── fugue/          # Existing (internal)
```
