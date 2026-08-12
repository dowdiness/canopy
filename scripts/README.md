# Scripts

Repository operations and tooling live here. Scripts automate durable build,
check, test, dependency, release, and maintenance workflows.

Placement decisions are defined by the
[module and package placement rules](../docs/development/module-package-map.md).
Prefer standard `moon` workspace commands over wrappers that copy membership
from [`../moon.work`](../moon.work).

Do not maintain a script inventory or copied command reference in this file.
Use the scripts themselves, the root [`justfile`](../justfile), and
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) as the authoritative
operational sources. Development guidance belongs under
[`../docs/development/`](../docs/development/).
