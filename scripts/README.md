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
operational sources. `check-moon-registry-bootstrap.nu` and
`check-moon-interfaces.nu` enforce the cache-aware MoonBit registry and generated
interface boundaries; `moon-update.sh` remains the bounded-retry implementation
used by the CI action, self-contained Cloudflare build scripts, local
`registry-refresh`, and its regression test.
`check-submodule-reachability.nu` is the shared blocking contract used by
PR-ready validation and the narrow Lefthook pre-push route;
`run-submodule-reachability.sh` maps Git's pre-push ref-update stream to that
command, enumerating commits relative to the streamed remote SHA or
authoritative `origin` refs for new refs rather than stale local tracking refs.
The checker checks initialized/matching gitlinks, conflicts, configured-origin
fetches, normal origin reachability, exact-SHA fetchability, and isolated
recursive graphs for pushed commits. Development guidance belongs under
[`../docs/development/`](../docs/development/).
