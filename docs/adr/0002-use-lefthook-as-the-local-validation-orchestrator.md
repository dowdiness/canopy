# Use Lefthook as the local validation orchestrator

Canopy expresses local validation lifecycle, changed-file routing, ordering, and change detection directly in `lefthook.yml` and reuses commands already exposed through the Justfile and existing adapters. Nushell exposes only `prepare-commit` and `validate-push`, using NUL-safe Git-to-MoonBit-target resolution behind that interface. Canopy does not add a generic validation-policy module, profiles, a phase graph, a validation cache, or separate local validation state.
