# Use Lefthook as the local validation orchestrator

## Decision

Use `lefthook.yml` as the local validation orchestrator. Express lifecycle,
changed-file routing, ordering, and change detection there, reusing commands
already exposed through the Justfile and existing adapters.

Nushell exposes only `prepare-commit` and `validate-push`, with NUL-safe
Git-to-MoonBit-target resolution behind that interface.

## Background

[ADR 0001](0001-place-validation-at-lifecycle-gates.md) defines the validation
gates; this decision defines how local validation is orchestrated. The original
record does not document a separate tool comparison or motivating incident:
**unconfirmed**.

## Rejected approaches and non-goals

Do not add:

- A generic validation-policy module or profiles.
- A phase graph.
- A validation cache or separate local validation state.

These are explicit exclusions in the original decision. Reasons for rejecting
each alternative individually are **unconfirmed**.

## Impact

Local validation configuration reuses existing commands and adapters rather
than introducing another policy system. The two Nushell operations remain the
interface for MoonBit preparation and validation; target resolution stays behind
it. Product APIs and compatibility policy are outside this decision's scope.

## Implementation references

See [Lefthook](../../lefthook.yml), the [Justfile](../../justfile), and the
[Nushell adapter](../../scripts/local-validation.nu). The adapter resolves
NUL-delimited Git paths and detects preparation output changes; Lefthook invokes
it through the Justfile. This implementation detail does not transfer overall
orchestration ownership away from Lefthook.

## Unresolved questions and follow-up

The original ADR records no outstanding questions or follow-up tasks. Whether
any remain is **unconfirmed**; this rewrite adds no implementation work or new policy.
