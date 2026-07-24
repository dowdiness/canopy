# EGW 0.3 and 0.4 wire compatibility evidence

**Date:** 2026-07-22

**Status:** Complete; protocol v3 hard cutover selected

**Related:**
[Collaboration boundary ADR](../decisions/2026-07-21-egw-collaboration-responsibility-boundary.md) ·
[EGW companion migration plan](../plans/2026-07-22-egw-companion-canopy-migration.md) ·
[Exact fixtures](fixtures/2026-07-22-egw-wire-compatibility/) ·
[Protocol v3 hard cutover](../decisions/2026-07-22-protocol-v3-hard-cutover.md)

**Reader:** Maintainers deciding how Canopy moves its current text-bound
collaboration protocol from EGW 0.3 to the target EGW release.

**Question:** Can an EGW 0.3 peer and an EGW 0.4 peer exchange the current
`CrdtOps`, `SyncRequest`, and `SyncResponse` payloads while retaining Canopy
wire protocol version 2?

**Result:** No. The Canopy v2 outer frame accepts and preserves both payload
families, but every tested EGW version and sync payload is rejected by the
other EGW release. The migration plan's wire compatibility gate is therefore
closed as a failure, not as an unverified risk.

**Keep until:** The protocol v3 cutover and the later EGW dependency migration
pass their published-artifact and collaboration validation.

**Disposition:** After that migration ships, retain the durable conclusion in
the ADR and delete this report plus its temporary fixture directory.

## Scope

The producer revisions were:

- EGW 0.3 tag `v0.3.0`, commit `a7d813c`;
- EGW 0.4 baseline commit `703e740`.

Each revision ran in its own detached worktree and MoonBit process. No module
imported both EGW versions. The investigation changed no EGW public source,
Canopy dependency, submodule pointer, or published package.

The current Canopy collaboration wire is text-bound. EGW 0.3 container exposes
raw public sync records but no matching `Version` and `SyncMessage` JSON codec
pair, so it is not a deployed cross-version wire surface. The container
companion remains a target-EGW-only validation concern.

## Method

Each producer created the same text history:

1. start with an empty `alice` replica;
2. insert `H` and `i`;
3. export a full sync message and base version;
4. apply the JSON-decoded full message to `bob`;
5. insert `!` on `alice`;
6. export and JSON-decode an incremental message;
7. apply it to `bob` and verify `Hi!`; and
8. export and decode an empty incremental message at the final version.

This established a passing same-version decoder and apply baseline before
cross-version consumption. Static fixture files were then exchanged between
processes. Consumers called the release's real `Version::from_json_string`,
`SyncMessage::from_json_string`, and `SyncSession::apply` APIs.

Canopy's real `protocol/wire` encoders wrapped the base version and full sync
fixtures in `CrdtOps`, `RelayedCrdtOps`, `SyncRequest`, and `SyncResponse`.
Every generated frame passed `decode_message`, was generated twice with
identical bytes, and is stored as base64 with its length and SHA-256 digest.

## Results

| Producer | Consumer | Empty/base/final version | Full sync | Incremental sync | Empty incremental | Apply result |
|---|---|---:|---:|---:|---:|---|
| EGW 0.3 | EGW 0.3 | accept | accept | accept | accept | `Hi!` |
| EGW 0.4 | EGW 0.4 | accept | accept | accept | accept | `Hi!` |
| EGW 0.3 | EGW 0.4 | reject all | reject | reject | reject | not reached |
| EGW 0.4 | EGW 0.3 | reject all | reject | reject | reject | not reached |

The exact cross-consumer outputs are:

```text
v030_empty_version        REJECT
v030_base_version         REJECT
v030_final_version        REJECT
v030_full_sync            REJECT
v030_incremental_sync     REJECT
v030_empty_incremental_sync REJECT
```

The reverse direction rejects the corresponding six v0.4 fixtures as well.

## Cause

EGW 0.3 text versions are frontier arrays such as:

```json
["Frontier",[1]]
```

EGW 0.4 versions are strict façade-specific envelopes:

```json
{"schema":1,"format":"event-graph-walker/text-version","entries":[{"replica_id":"alice","sequence":1}]}
```

EGW 0.3 sync messages contain compressed `runs` keyed partly by local logical
versions.

EGW 0.4 messages contain strict `operations` keyed by stable
`(replica_id, sequence)` identities. The migration guide intentionally rejects
legacy arrays and provides no mixed-version decoder or migration heuristic.

The binary Canopy frame is not the incompatibility. For both payload families,
its version byte, message tags, request IDs, target IDs, sender IDs, and opaque
payload bytes round-trip correctly. Failure occurs only when the receiving EGW
façade interprets `version_json` or `sync_json`.

## Golden frame summary

| Frame | v0.3 bytes | v0.3 SHA-256 | v0.4 bytes | v0.4 SHA-256 |
|---|---:|---|---:|---|
| `CrdtOps` | 363 | `c53111f2480ee82c2d4ca28cf8f10e686c26772bff2e2dfbece78e69c9fafb02` | 861 | `1a27369679c767381f75da317e5fb267b26b983eb4bb197d7414eab6a0a6dbca` |
| `RelayedCrdtOps` | 374 | `a275b293e803d5be8f60d5264404114fcd2dbeb027864d7e6df5652e46c68562` | 872 | `4ae427e4b25a9f937b2b2d7f6f119cd57f327e4328589c5338e371bf1059c840` |
| `SyncRequest` | 48 | `49e8ff4b0f8e18d34db262d4a873228f534dd4af72c11ec38f0cd93d4ea25915` | 223 | `7aac67cc6b3666ae70943f0212797d52df57e55d2b6b281a15280d7b0c38f9db` |
| `SyncResponse` | 381 | `bcb7a9a5749d0aa74294a874b600395947267b8496c27a41b935bcd6dfa78194` | 879 | `d152fafbe8ee716378a3c53d7554455161b0b266a04b354bef1a9a16ebf1929e` |

The fixture directory contains the complete JSON payloads, cross-consumer
results, exact base64 frame bytes, and the MoonBit package sources used to
produce and consume them.

## Decision

The protocol v3 ADR selects a coordinated hard cut. Endpoint decoders reject v2
frames before EGW payload handling, and the relay drops complete frames whose
version is not v3. No identity bridge, dual decoder, or mixed-version room mode
is introduced.

This resolves the wire decision required before the Canopy dependency
migration. The companion publication, Loom migration, and clean published-
resolution gates remain unchanged.

## Validation commands

The archived sources use `.txt` suffixes so MoonBit does not discover them as
Canopy workspace packages. Recreate detached EGW worktrees, copy each version's
packages to that release's module root, then restore the executable filenames:

```sh
fixture_root="$CANOPY/docs/research/fixtures/2026-07-22-egw-wire-compatibility"
git -C "$CANOPY/event-graph-walker" worktree add --detach "$V030" v0.3.0
git -C "$CANOPY/event-graph-walker" worktree add --detach "$V040" 703e740
cp -R "$fixture_root/sources/v030/wire_fixture" "$V030/"
cp -R "$fixture_root/sources/v030/wire_consumer" "$V030/"
cp -R "$fixture_root/sources/v040/wire_fixture" "$V040/"
cp -R "$fixture_root/sources/v040/wire_consumer" "$V040/"
for package in \
  "$V030/wire_fixture" "$V030/wire_consumer" \
  "$V040/wire_fixture" "$V040/wire_consumer"
do
  mv "$package/moon.pkg.txt" "$package/moon.pkg"
  mv "$package/main.mbt.txt" "$package/main.mbt"
done
```

From the EGW 0.3 detached worktree:

```sh
NEW_MOON_MOD=0 moon check wire_fixture --deny-warn --warn-list=-20-82
NEW_MOON_MOD=0 moon run wire_fixture --warn-list=-20-82
NEW_MOON_MOD=0 moon check wire_consumer --deny-warn --warn-list=-20-82
NEW_MOON_MOD=0 moon run wire_consumer --warn-list=-20-82
```

Warnings 20 and 82 are pre-existing v0.3 source diagnostics under the current
compiler. The fixture and consumer packages introduce no additional warning.

From the EGW 0.4 detached worktree:

```sh
NEW_MOON_MOD=0 moon check wire_fixture --deny-warn
NEW_MOON_MOD=0 moon run wire_fixture
NEW_MOON_MOD=0 moon check wire_consumer --deny-warn
NEW_MOON_MOD=0 moon run wire_consumer
```

From the Canopy root, copy in the archived frame generator, run it, and remove
only that temporary package afterward:

```sh
cp -R \
  "$fixture_root/sources/canopy/wire_compat_fixture" \
  "$CANOPY/wire_compat_fixture"
mv "$CANOPY/wire_compat_fixture/moon.pkg.txt" \
  "$CANOPY/wire_compat_fixture/moon.pkg"
mv "$CANOPY/wire_compat_fixture/main.mbt.txt" \
  "$CANOPY/wire_compat_fixture/main.mbt"
NEW_MOON_MOD=0 moon check wire_compat_fixture --deny-warn
NEW_MOON_MOD=0 moon run wire_compat_fixture
rm -rf "$CANOPY/wire_compat_fixture"
```
