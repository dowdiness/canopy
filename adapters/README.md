# Adapters

Non-MoonBit runtime and interface integrations live here. Adapters translate
between stable Canopy interfaces and host-specific concerns without owning the
editor's domain behavior.

Placement decisions are defined by the
[module and package placement rules](../docs/development/module-package-map.md).

Do not maintain an adapter inventory in this file. Read each adapter's local
package and build configuration for its current entry points. Inspect the
owning MoonBit package with `moon ide outline <path>` before changing the
interface it consumes.
