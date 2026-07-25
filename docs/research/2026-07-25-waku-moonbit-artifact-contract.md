# Waku / MoonBit artifact contract (2026-07-25)

**Decision:** A Waku app should keep the five MoonBit JavaScript outputs as
repo-level build artifacts and expose them to Vite through the existing virtual
module contract. Do not copy them into Waku's `dist`, publish them from
`public`, or replace the virtual imports with ad-hoc aliases. Production and CI
should run the repository's authoritative MoonBit build before Waku's build;
local development should use one shared MoonBit build/watch process plus the
Vite plugin's output invalidation. The supported reload guarantee is a **full
browser reload**, not granular React/Waku HMR.

This is a research decision, not an implementation. The existing plugin is the
reference contract, but its current “one `moon build` per configured module”
implementation should not be copied unchanged into Waku: the four Canopy FFI
entries all point at the same workspace root, so a Waku adapter should
coordinate one root build/watch rather than start four concurrent builds of the
same project.

## The five-module contract

The public import IDs and resolved repository artifacts are:

| Virtual import ID | JavaScript artifact | TypeScript declarations |
| --- | --- | --- |
| `@moonbit/crdt-lambda` | `_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js` | `lambda.d.ts` and `moonbit.d.ts` in the same directory |
| `@moonbit/crdt-json` | `_build/js/release/build/dowdiness/canopy/ffi/json/json.js` | `json.d.ts` and `moonbit.d.ts` in the same directory |
| `@moonbit/crdt-markdown` | `_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js` | `markdown.d.ts` and `moonbit.d.ts` in the same directory |
| `@moonbit/crdt-jsx` | `_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.js` | `jsx.d.ts` and `moonbit.d.ts` in the same directory |
| `@moonbit/graphviz` | `_build/js/release/build/dowdiness/graphviz/browser/browser.js` | `browser.d.ts` in the same directory |

The five IDs and output paths are explicit in
[`examples/web/vite.config.ts`](../../examples/web/vite.config.ts#L12-L81).
The release build script independently asserts the same five JavaScript files
and their declarations (plus other example artifacts) in
[`scripts/build-js.sh`](../../scripts/build-js.sh#L10-L44). The root
[`moon.mod`](../../moon.mod#L1-L46) selects JavaScript as the preferred target;
`moon build --target js --release` is therefore the artifact-producing command,
not a TypeScript or Waku compilation step.

## Lifecycle contract

### 1. Build

- **Production/CI:** run [`scripts/build-js.sh`](../../scripts/build-js.sh#L8-L44)
  once at repository root, then run the Waku production build. The repository's
  web wrapper follows this ordering in
  [`scripts/build-web.sh`](../../scripts/build-web.sh#L10-L22), and CI does the
  same through `Build web` before `Type check web`
  ([`.github/workflows/ci.yml`](../../.github/workflows/ci.yml#L307-L344)). Waku's
  own production guide says its build bundles client/server code and writes the
  application result to `dist`; that is a separate output namespace and must
  not become the source location for the MoonBit files
  ([Waku: Building for Production](https://waku.gg/guides/building-for-production)).
- **Local development:** `waku dev` should run the Vite plugin's initial build
  hook and then keep a single `moon build --target js --release --watch`
  process alive for the workspace. Moon's local CLI exposes both `--watch` and
  `--target-dir`; the repository's workspace includes `./graphviz`
  ([`moon.work`](../../moon.work#L1-L43)), while the build script documents that
  graphviz output belongs in the workspace `_build`, not `graphviz/_build`
  ([`scripts/build-js.sh`](../../scripts/build-js.sh#L10-L15)). The five output
  files, rather than `.mbt` files, are the Vite watch inputs.
- **CI reuse:** build artifacts can be produced once and passed to browser jobs.
  CI uploads the namespaced files in `build-js`, downloads them into
  `_build/js/release/build/dowdiness`, and sets `CANOPY_SKIP_MOON_BUILD=1`
  ([`.github/workflows/ci.yml`](../../.github/workflows/ci.yml#L280-L305),
  [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml#L354-L394)). The
  plugin's skip path is fail-closed: it checks every configured output and
  errors if any is missing ([`vite-plugin-moonbit.ts`](../../examples/web/vite-plugin-moonbit.ts#L66-L112)).
  Waku CI should preserve this property rather than silently falling back to a
  source build in a browser-only job.

### 2. Resolve and load

The names above are **virtual import IDs**. The plugin maps each ID to an
absolute output path, returns the ID from `resolveId`, and reads the generated
JavaScript in `load` ([`vite-plugin-moonbit.ts`](../../examples/web/vite-plugin-moonbit.ts#L74-L135)).
The Waku configuration should put this plugin in `defineConfig({ vite: {
plugins: [...] } })`, not in a second standalone Vite config. Waku's public config
accepts a Vite `UserConfig` under `vite`
([Waku `config.ts`](https://github.com/wakujs/waku/blob/main/packages/waku/src/config.ts)),
and Waku's current implementation carries user Vite plugins into its combined
plugin set ([`extra-plugins.ts`](https://github.com/wakujs/waku/blob/main/packages/waku/src/lib/vite-plugins/extra-plugins.ts)).

The app root must retain filesystem access to the repository artifact tree. The
current Vite app does this with `server.fs.allow: ['../..']`
([`vite.config.ts`](../../examples/web/vite.config.ts#L59-L63)); a Waku app at a
different directory must calculate the equivalent repository-root allowance.
The plugin resolves module paths from `process.cwd()`
([`vite-plugin-moonbit.ts`](../../examples/web/vite-plugin-moonbit.ts#L74-L85)),
so its configured relative paths and the TypeScript paths below must be
rechecked against the Waku app's actual working directory.

Vite's official virtual-module example uses a `\0`-prefixed internal ID
([Vite Plugin API: virtual modules](https://vite.dev/guide/api-plugin#virtual-modules-convention)).
That is an internal implementation convention, not a reason to change the five
public import IDs: the repository's existing `resolveId`/`load` behavior is the
contract that current callers use. If the plugin is modernized to use an
internal null-prefixed ID, the externally visible IDs and declaration mappings
must remain unchanged.

### 3. Typecheck

TypeScript resolves the public IDs to generated declarations, not to the
runtime JavaScript. The current `tsconfig.json` maps the four FFI IDs to their
module declarations and their `/moonbit` subpaths to `moonbit.d.ts`; graphviz
has only its browser module declaration
([`examples/web/tsconfig.json`](../../examples/web/tsconfig.json#L14-L25)).
A Waku app should carry these mappings into its app `tsconfig.json` and run
`tsc --noEmit` after the MoonBit build. The repository names that command
`npm run typecheck` ([`examples/web/package.json`](../../examples/web/package.json#L5-L14));
CI proves the intended ordering by building first and typechecking second
([`.github/workflows/ci.yml`](../../.github/workflows/ci.yml#L331-L336)). Waku's
route type generation is additional framework output; it does not replace this
explicit declaration check ([Waku Quick Start](https://waku.gg/guides/quick-start)).

Because these MoonBit packages contain JavaScript/browser FFI (for example,
`ffi/jsx` is restricted to the JS target in its package configuration), imports
belong behind Waku's client boundary. Waku documents that a `'use client'`
module and its transitive imports are bundled for the browser, while code
outside that subtree is server code
([Waku: Server and Client Components](https://waku.gg/guides/server-and-client-components)).
The contract does not claim that these browser artifacts are safe to import from
server components or RSC-only code.

### 4. Cache

Keep all five virtual IDs in `optimizeDeps.exclude`, as the current Vite config
does ([`vite.config.ts`](../../examples/web/vite.config.ts#L79-L81)). Vite's
optimizer is a development-only dependency pre-bundler, and `exclude` means
“exclude from pre-bundling” ([Vite dependency pre-bundling](https://vite.dev/guide/dep-pre-bundling),
[Vite `optimizeDeps.exclude`](https://vite.dev/config/dep-optimization-options#optimizedeps-exclude)).
That is the correct choice here: these IDs are plugin-loaded files whose contents
change under MoonBit's watcher, not stable npm dependencies.

The Vite cache (`node_modules/.vite` by default) is distinct from MoonBit's
`_build` artifacts. Vite keys its pre-bundle cache from the lockfile, relevant
config, and `NODE_ENV`, and supports deleting the cache or forcing a rebuild
([Vite dependency-prebundling cache](https://vite.dev/guide/dep-pre-bundling#file-system-cache)).
Waku creates client, SSR, and RSC environments and merges the user's Vite config
into them before setting per-environment output directories
([Waku `environments.ts`](https://github.com/wakujs/waku/blob/main/packages/waku/src/lib/vite-plugins/environments.ts)).
Therefore the exclusions must be verified in the environment(s) that actually
load the client modules; do not assume a single client-only Vite cache is the
whole Waku dev graph. No Waku framework cache should be introduced for the
MoonBit files.

### 5. Reload

The existing development loop is output-driven: it starts Moon's native watch,
adds each generated output to Vite's watcher, invalidates the virtual module and
its importers, then sends `{ type: 'full-reload' }`
([`vite-plugin-moonbit.ts`](../../examples/web/vite-plugin-moonbit.ts#L137-L221)).
This is a valid Vite plugin pattern—Vite documents that custom hot-update logic
may invalidate modules and send a full reload
([Vite `handleHotUpdate`](https://vite.dev/guide/api-plugin#handlehotupdate)).

The supported Waku contract should consequently be: **a successful MoonBit
output write causes a full browser reload**. Do not describe this as granular
React state-preserving HMR. Waku's guide promises instant updates for ordinary
app edits and its current Vite integration has separate client/SSR/RSC
execution environments, while Vite's environment API scopes module graphs and
hot channels per environment ([Vite Environment API](https://vite.dev/guide/api-environment-plugins)).
The current plugin uses the legacy/shared `server.moduleGraph` and
`server.ws` surfaces, so whether that full-reload message refreshes every Waku
environment exactly as desired is **unverified**. A future implementation must
validate `waku dev` with each client entry; until then, granular HMR and RSC
refresh semantics are explicitly out of contract.

## Sources and scope

Local sources were inspected at the current checkout, including the Moon
workspace/module configuration, the two build scripts, the Waku-facing Vite
plugin/config/typecheck package scripts, and the CI build/upload/download jobs
linked above. External sources are first-party Waku documentation/source and
first-party Vite documentation, retrieved for this note on 2026-07-25. No
secondary Waku/Vite write-up is used.
