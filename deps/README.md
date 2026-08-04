# Dependencies

Separately owned Git repositories are checked out here as submodules. A
dependency may also be a MoonBit workspace member; repository ownership and
workspace membership are independent.

## Working here

- Use [`.gitmodules`](../.gitmodules) for the authoritative submodule paths and
  remotes.
- Follow the dependency repository's own guidance and manifests.
- Commit and push changes in the submodule repository before updating the
  parent pointer in Canopy.

Do not maintain a dependency inventory in this file. Use
`git submodule status --recursive` for the checked-out revisions and
[`../moon.work`](../moon.work) for root-workspace membership.

See the [submodule workflow](../docs/development/workflow.md) and the
[module and package placement rules](../docs/development/module-package-map.md).
