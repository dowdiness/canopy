# Design: extract a shared `byte-codec` package

**Status:** design (no code). Follow-up to #387 (ephemeral extraction).
**Date:** 2026-05-29.
**Class:** design doc — answers *what to build and why*, not *how/in what order*. Implementation plan is deferred until scope (Option A vs B) is chosen.

## Problem (why)

Two unrelated needs converge on the same missing abstraction:

1. **#387 facade leak.** Extracting `ephemeral` forced its low-level wire primitives (`Reader`, `read_string`, `write_string`) to become `pub` so `editor/sync_protocol.mbt` could keep reading/writing protocol frames. These are generic byte-codec internals, not presence concepts — yet they now sit in `ephemeral`'s public surface, and `editor` reaches *through* `ephemeral` for them. The dependency direction is right (editor → ephemeral) but the *content* is wrong: editor depends on ephemeral for byte-reading, not for presence.

2. **`relay/wire.mbt` duplication.** `relay` independently reimplements the same wire primitives — LEB128 varint and length-prefixed UTF-16LE strings — in a *different idiom* (`read_relay_uvarint(data, offset) -> (value, offset)?` offset-threading + `Option`, on `Int`), versus `ephemeral`'s `Reader` struct (mutable `pos`) + `raise`. Same underlying format concept, two hand-rolled implementations, zero shared code.

Restating both in one vocabulary (per *finding-common-structures* §1): *both packages serialize values to a byte buffer and deserialize them from a byte cursor, using LEB128 varints and length-prefixed strings.* The restatement is natural, not forced — so the common structure is genuine, not incidental. This is the same shape as the `lib/range` duplication already tracked in memory.

## Current state (the duplication, precisely)

### Generic primitives in `ephemeral/ephemeral_encoding.mbt`
Wire-format-agnostic, candidates to move:
- `Reader` struct (`data : Bytes`, `mut pos : Int`) + `new`, `read_byte`, `read_bytes`.
- `write_uvarint` / `read_uvarint` (LEB128, `UInt64`), `safe_uvarint_to_int`.
- `write_ivarint` / `read_ivarint` (zigzag, `Int64`).
- `write_string` / `read_string` (uvarint-length-prefixed, UTF-16LE via `Buffer.write_string_utf16le` + `Bytes.to_unchecked_string`).
- `write_len_bytes` / `read_len_bytes`.
- `write_f64_le` / `read_f64_le`.

### Ephemeral-specific (stays in `ephemeral`)
- `write_ephemeral_value` / `read_ephemeral_value` (the `EphemeralValue` tag codec + tag constants).
- `parse_peer_id` / `wire_peer_id` / `to_wire_peer_id` / `stable_peer_hash` (peer-id → wire-id mapping; FNV hash).
- `encode_entries` / `decode_entries` (`EphemeralRecord` framing).

### `relay/wire.mbt` (a *second* implementation)
- `write_relay_uvarint(Buffer, Int)`, `read_relay_uvarint(Bytes, Int) -> (Int, Int)?`, `read_relay_string(Bytes, Int) -> (String, Int)?` — generic, duplicated.
- `encode_peer_control`, `wrap_with_sender`, `encode_peer_joined`, `encode_peer_left` — relay-specific framing (stays in `relay`).
- Consumers: `relay/relay_room.mbt` + tests.

### Consumers of the generic layer
- `ephemeral`: its value codec + entry framing.
- `editor/sync_protocol.mbt` + `sync_editor_ws.mbt`: `Reader`, `read_string`, `write_string` (today via `ephemeral` facade `using`).
- `relay`: its own copy.

## Design tensions (the real decisions)

### 1. API style — `Reader` struct vs offset-threading
- **`Reader` (mutable `pos`) + `raise`** (ephemeral): imperative, composes well for nested reads (`read_ephemeral_value` recurses), errors propagate automatically. Mutable cursor is a hidden effect.
- **offset-threading `(value, offset)?`** (relay): pure, explicit cursor, but every call site must thread the offset and match `Option`; verbose for nested structures.

A shared package picks **one**. The `Reader`+`raise` style is the better general primitive (composes for nested decode, which relay's flat frames don't need but ephemeral's recursive `EphemeralValue` does). Relay migrating to it is a readability *change* but not a behavior change.

### 2. Error type — the load-bearing coupling
Today `Reader::read_byte` etc. `raise EphemeralError`. A generic `byte-codec` **must not** depend on `EphemeralError` (that would invert the layering). So the shared package needs its **own** error — e.g. `suberror CodecError { UnexpectedEndOfInput; VarintTooLong; VarintValueTooLarge; InvalidUtf16 }`. Then:
- `ephemeral` maps/wraps `CodecError` into `EphemeralError` at its boundary (or replaces the overlapping `EphemeralError` variants entirely and keeps only the truly-ephemeral ones — `InvalidValueTag`, `InvalidBoolValue`, `InvalidPeerKey`).
- This is the single biggest design choice. Cleanest: `byte-codec` owns the *transport-level* read errors (EOF, varint overflow); `ephemeral` owns the *semantic* errors (bad tag, bad bool, bad peer key) and converts at the seam.

### 3. Wire-format compatibility — non-negotiable
Both `ephemeral`'s and `relay`'s byte formats are **transmitted/persisted** (CRDT sync + relay). Unification must be **byte-exact** for each existing format. Risk: `relay` encodes `Int` uvarints, `ephemeral` encodes `UInt64`; the LEB128 algorithms must be confirmed identical for the overlapping value range before relay is migrated onto the shared primitive. **Pin both formats with round-trip property tests *before* any migration** (per *refactoring-safety* §1) — a frozen-bytes fixture, not a re-derivation.

### 4. Package location
- `lib/byte-codec` (sibling of future `lib/*` shared utils) — matches the "shared low-level utility" role and the `lib/range` precedent. **Recommended.**
- top-level `dowdiness/canopy/byte-codec` — fine but `lib/` better signals "general-purpose, no domain knowledge" (per *design-principles* §6: a framework's generality is what it excludes — `byte-codec` must exclude all presence/relay concepts).

## Options

### Option A — narrow (solve the #387 leak only)
Extract the generic primitives into `lib/byte-codec` with its own `CodecError`. `ephemeral` and `editor` consume it directly (editor no longer reaches through `ephemeral`; `ephemeral`'s `Reader`/`read_string`/`write_string` `pub`s disappear). **`relay` untouched.**
- *Pro:* small, removes the facade leak, no wire-format risk for relay.
- *Con:* leaves relay's duplicate in place — the deeper duplication persists.

### Option B — unify (A + migrate relay)
Option A, then migrate `relay/wire.mbt` onto `byte-codec`, deleting `read_relay_*`/`write_relay_uvarint`.
- *Pro:* eliminates the duplication entirely; one varint/string codec repo-wide.
- *Con:* larger; must prove relay's wire format is byte-identical under the shared primitive (format-compat risk #3); touches a second package's persisted format.

## Recommendation

**Stage it: ship Option A first, then Option B as a separate follow-up.** A directly resolves the #387 leak (the concrete debt) with no transmitted-format risk, and *creates* the package B needs. B is then a self-contained "migrate relay onto the existing shared codec" change whose only risk (format compat) is isolated and guarded by the round-trip fixtures written in A. This keeps each PR reviewable and each persisted-format change independently verifiable — rather than bundling a presence-layer cleanup with a relay-protocol migration.

## Non-goals
- No change to any on-the-wire byte format. This is a pure code-location/duplication refactor; every existing encode must produce identical bytes.
- Not generalizing beyond what exists (no new codec features, no generic serialization framework) — `byte-codec` contains exactly today's primitives.

## Verification strategy (for whichever option proceeds)
1. **Before moving anything:** add round-trip property tests (`@quickcheck.samples`) over `EphemeralValue` and a frozen-bytes fixture for both ephemeral and relay frames — these pin the wire formats and must use frozen literals, never re-call the code under refactor (per the drift-detector lesson in memory).
2. New `lib/byte-codec/pkg.generated.mbti` is self-contained (no `@ephemeral`/`@relay`/`@editor` refs).
3. `ephemeral` and `editor` `.mbti` diffs: `ephemeral` loses the `Reader`/`read_string`/`write_string` pubs; editor unchanged.
4. Full workspace `moon test` count unchanged.
5. (Option B) relay's frozen-bytes fixtures pass unchanged after migration — the proof the format is byte-identical.

## Decisions (confirmed 2026-05-29)
- **Scope: A then B.** Ship Option A first (extract `lib/byte-codec`, fix the #387 leak, no relay wire-format risk), then migrate `relay` as a separate guarded PR. Each persisted-format change is verified independently.
- **Location: `lib/byte-codec`** (general-purpose, no domain knowledge — must exclude all presence/relay concepts per *design-principles* §6).
- Implementation deferred to a follow-up session; this doc is the design of record. The Option-A implementation plan (file moves, `CodecError` boundary, consumer rewiring, verification gates) is written when that work starts.
