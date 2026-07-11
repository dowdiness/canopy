# Ideal Inspector Panel

## Why

The backlog still lists the Ideal editor inspector panel as unfinished, but the
current UI already has partial inspector rendering. What is missing is a clear,
supported definition of which node details should appear and how outline/editor
selection should drive that panel.

## Scope

In:
- `examples/ideal/main/view_inspector.mbt`
- `examples/ideal/main/view_outline.mbt`
- `examples/ideal/main/model.mbt`
- `examples/ideal/main/main.mbt`
- any small supporting files in `examples/ideal/main/` required for selection plumbing

Out:
- new structural editing features
- redesign of the overall Ideal layout

## Current State

- The Ideal editor already has inspector rendering and selected-node plumbing.
- The active backlog still tracks "wire up node details (type, source range,
  children) on outline click" as incomplete.

## Desired State

- Clicking a node in the outline consistently populates the inspector with the
  intended node details.
- The inspector shows the agreed detail set, including source range.
- Empty, stale, and elided-node cases have clear behavior.

## Steps

1. Audit the current selection and inspector data flow.
2. Add the missing source-range and node-detail plumbing.
3. Verify selection behavior from outline clicks and fallback resolution paths.
4. Update or add targeted tests if practical for this surface.

## Acceptance Criteria

- [ ] Outline selection populates the inspector reliably.
- [ ] Inspector details include type/kind, source range, and child information.
- [ ] Missing or elided-node cases degrade cleanly instead of showing stale data.

## Validation

```bash
moon check
moon test
```

Add any browser/manual validation steps needed for the Ideal UI.

## Risks

- Part of this task is clarifying whether the backlog item is truly unfinished
  or just under-specified; the end state should update the TODO accordingly.

## Notes

- Relevant current files: `examples/ideal/main/view_inspector.mbt`,
  `examples/ideal/main/view_outline.mbt`
