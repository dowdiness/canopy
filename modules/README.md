# Modules

Reusable, publishable MoonBit modules owned by this repository live here. The
primary `dowdiness/canopy` module is `canopy/`; each sibling directory is an
independently owned module.

Placement decisions are defined by the
[module and package placement rules](../docs/development/module-package-map.md).

Do not maintain a module or package inventory in this file. Read
[`../moon.work`](../moon.work) for root-workspace membership, the nearest
`moon.mod` for module identity and dependencies, and the nearest `moon.pkg` for
package dependencies. Use `moon ide outline <path>` to inspect a package's
public interface.
