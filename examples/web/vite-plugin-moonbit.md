# vite-plugin-moonbit

A general-purpose Vite plugin for building and importing MoonBit modules.

## Table of Contents

- [Features](#features)
- [Why Use This Plugin?](#why-use-this-plugin)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [API](#api)
- [TypeScript Configuration](#typescript-configuration)
- [How It Works](#how-it-works)
- [Example Project Structure](#example-project-structure)
- [Import in Code](#import-in-code)
- [Benefits](#benefits)
- [Development Workflow](#development-workflow)
- [Console Output](#console-output)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)
- [Integration with Other Tools](#integration-with-other-tools)
- [FAQ](#faq)
- [License](#license)

## Features

- ⚡ **Automatic Building**: Builds MoonBit modules before Vite starts
- 🔄 **Native Watch Mode**: Uses MoonBit's `--watch` flag for fast incremental rebuilds
- 🔥 **Hot Module Replacement**: Automatically reloads browser when MoonBit files change
- 📦 **Virtual Imports**: Import MoonBit modules using clean virtual module names
- 🎯 **TypeScript Support**: Full TypeScript type definitions with proper module resolution
- ⚙️ **Highly Configurable**: Support for multiple modules, custom build flags, and targets
- 🚀 **Zero Copy**: Files loaded directly from MoonBit build output via Rollup's `load` hook
- 🧹 **Smart Invalidation**: Vite module graph invalidation ensures TypeScript imports stay fresh

## Why Use This Plugin?

### Without Plugin

```bash
# Manual workflow
cd ../moonbit-module && moon build --target js
# copy the generated JS bundle into your app's chosen static location,
# or wire it into your bundler manually
cd ../examples/web && npm run dev

# For every change:
# 1. Stop Vite
# 2. Rebuild MoonBit manually
# 3. Copy files
# 4. Restart Vite
```

### With Plugin

```bash
# Automatic workflow
npm run dev

# For every change:
# Just edit .mbt files - everything else is automatic!
```

| Feature | Without Plugin | With Plugin |
|---------|---------------|-------------|
| **Initial build** | Manual `moon build` | ✅ Automatic |
| **File copying** | Manual `cp` commands | ✅ Not needed (Rollup's `load` hook) |
| **Watch mode** | Manual restart | ✅ Native `--watch` |
| **HMR** | Not available | ✅ Full browser reload |
| **TypeScript types** | Manual path setup | ✅ Configured via `tsconfig.json` |
| **Multiple modules** | Multiple build commands | ✅ Single config |

## Requirements

- **Vite 5.x** or higher
- **MoonBit CLI** (`moon`) installed and in PATH
- **Node.js 18+** (for native `node:` imports)
- **TypeScript 5.x** (optional, for type checking)

## Installation

Copy `vite-plugin-moonbit.ts` to your Vite project.

```bash
# Verify MoonBit is installed
moon version

# Should output something like: moon 0.x.x (...)
```

## Usage

### Basic Example

```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import { moonbitPlugin } from './vite-plugin-moonbit';

export default defineConfig({
  plugins: [
    moonbitPlugin({
      modules: [
        {
          name: '@moonbit/mymodule',
          path: '../moonbit-module'
        }
      ]
    })
  ]
});
```

### Multiple Modules

```typescript
moonbitPlugin({
  modules: [
    {
      name: '@moonbit/core',
      path: '../core',
      output: '_build/js/release/build/core.js'
    },
    {
      name: '@moonbit/utils',
      path: '../utils',
      output: '_build/js/release/build/browser/browser.js'
    }
  ]
})
```

### Custom Build Configuration

```typescript
moonbitPlugin({
  target: 'js',        // Build target (default: 'js')
  release: true,       // Release mode (default: true)
  watch: true,         // Enable watch mode (default: true)
  modules: [
    {
      name: '@moonbit/mymodule',
      path: '../mymodule',
      buildFlags: ['--no-mi']  // Additional moon build flags
    }
  ]
})
```

### Disable Watch Mode

If you want to disable automatic rebuilds (e.g., for production builds):

```typescript
moonbitPlugin({
  watch: false,  // Disable MoonBit watch mode
  modules: [/* ... */]
})
```

**Note:** Watch mode is only active when `vite dev` is running. Production builds (`vite build`) automatically build once without watching.

## API

### `moonbitPlugin(options: MoonBitPluginOptions)`

Creates a Vite plugin for MoonBit modules.

#### Options

**`MoonBitPluginOptions`**

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `modules` | `MoonBitModule[]` | *required* | Array of MoonBit modules to build |
| `target` | `string` | `'js'` | Build target for `moon build` |
| `release` | `boolean` | `true` | Build in release mode |
| `watch` | `boolean` | `true` | Enable MoonBit watch mode (`--watch`) in development |

**`MoonBitModule`**

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `name` | `string` | *required* | Virtual module name (e.g., `'@moonbit/mymodule'`) |
| `path` | `string` | *required* | Path to MoonBit module directory (relative to Vite root) |
| `output` | `string` | *auto* | Path to built JS file (relative to module path) |
| `watch` | `string[]` | *deprecated* | Not used - MoonBit's native watch handles all `.mbt` files |
| `buildFlags` | `string[]` | `[]` | Additional flags for `moon build` |

#### Output Path Inference

If `output` is not specified, it's inferred from the module name:

```
_build/{target}/{release|debug}/build/{module-basename}.js
```

For example:
- Module name: `@moonbit/mymodule`
- Target: `js`
- Release: `true`
- Inferred output: `_build/js/release/build/mymodule.js`

## TypeScript Configuration

Add path mappings to `tsconfig.json`:

```json
{
  "compilerOptions": {
    "paths": {
      "@moonbit/mymodule": ["../mymodule/_build/js/release/build/mymodule.d.ts"]
    }
  }
}
```

For type definitions, place them in `src/vite-env.d.ts` or reference the `.d.ts` files via `paths`.

## How It Works

### Build Process

1. **Build Hook** (`buildStart`): Runs `moon build --target {target}` for each module on Vite startup
2. **Resolve Hook** (`resolveId`): Resolves virtual module names (e.g., `@moonbit/mymodule`)
3. **Load Hook** (`load`): Reads built JS files directly from MoonBit output using Node.js `fs`

### Watch Mode (Development)

When `watch: true` (default in development):

1. **Spawn Watch Processes**: Starts `moon build --watch` for each module
2. **Monitor Output Files**: Vite watches the generated `.js` files
3. **Detect Changes**: When a `.mbt` file changes:
   - MoonBit's watch process rebuilds incrementally
   - Output `.js` file is updated
   - Vite detects the file change
4. **Invalidate Module Graph**:
   - Virtual module (`@moonbit/crdt`) is invalidated
   - All importers (TypeScript files using the module) are invalidated
5. **Trigger HMR**: Browser reloads with fresh code

### Why Module Graph Invalidation?

Without invalidation, Vite's module graph would cache the old module:

```
❌ Without invalidation:
.mbt changes → MoonBit rebuilds → .js changes → Vite caches old module → No reload

✅ With invalidation:
.mbt changes → MoonBit rebuilds → .js changes → Invalidate graph → TypeScript reloads → Browser updates
```

The plugin invalidates:
- The virtual MoonBit module itself (`@moonbit/crdt`)
- All modules that import it (`src/editor.ts`, etc.)

This ensures TypeScript code that imports MoonBit modules gets the latest changes.

### Performance Benefits

This approach is faster than manual file watching because:
- **MoonBit's incremental compilation**: Optimized for speed, only recompiles changed files
- **Single source of truth**: MoonBit's watch handles file detection
- **No duplicate watching**: Vite only watches output files, not source `.mbt` files
- **Native tooling**: Leverages `moon build --watch` built-in capabilities

## Example Project Structure

```
project/
├── moonbit-module/         # MoonBit module
│   ├── src/
│   │   └── lib.mbt
│   ├── moon.mod.json
│   └── _build/
│       └── js/
│           └── release/
│               └── build/
│                   ├── mymodule.js
│                   └── mymodule.d.ts
└── examples/web/           # Vite project
    ├── src/
    │   └── main.ts
    ├── vite.config.ts
    └── vite-plugin-moonbit.ts
```

## Import in Code

```typescript
// src/main.ts
import * as mymodule from '@moonbit/mymodule';

mymodule.someFunction();
```

## Benefits

- **No manual copying**: Files loaded directly from build output via Rollup's `load` hook
- **Fast rebuilds**: MoonBit's incremental compilation with `--watch`
- **Smart invalidation**: Vite module graph invalidation for TypeScript HMR
- **Type safety**: Full TypeScript support with `.d.ts` files
- **Clean separation**: MoonBit code stays in separate directories
- **Standard Vite workflow**: Just run `npm run dev`
- **Zero configuration**: Smart defaults with override options

## Development Workflow

1. **Start Vite dev server**:
   ```bash
   npm run dev
   ```

2. **Plugin automatically**:
   - Builds all MoonBit modules
   - Spawns `moon build --watch` processes
   - Watches output files for changes

3. **Edit MoonBit code** (`.mbt` files):
   - MoonBit watch rebuilds incrementally
   - Vite invalidates module graph
   - Browser reloads automatically

4. **Edit TypeScript code** (`.ts` files):
   - Vite's standard HMR applies
   - Browser hot-reloads changes

## Console Output

When running `npm run dev`, you'll see:

```
[MoonBit] Building modules...
[MoonBit] Starting watch mode...
[MoonBit] Watching @moonbit/crdt...
[MoonBit] Watching @moonbit/graphviz...
[MoonBit:@moonbit/crdt] Finished. moon: no work to do
[MoonBit:@moonbit/graphviz] Finished. moon: no work to do

  VITE v5.x.x  ready in 500 ms

  ➜  Local:   http://localhost:5173/
```

When you edit a `.mbt` file:

```
[MoonBit:@moonbit/crdt] Finished. moon: ran 3 actions, now up to date
[MoonBit] @moonbit/crdt rebuilt, invalidating modules...
[MoonBit] @moonbit/crdt HMR complete
```

## Troubleshooting

### Changes not reflecting in browser

**Issue**: MoonBit rebuilds but browser doesn't update

**Solution**: Check that:
1. Output path is correct (check `output` in config)
2. TypeScript imports use the virtual module name (e.g., `import * as crdt from '@moonbit/crdt'`)
3. Vite dev server is running (watch mode only works with `npm run dev`)

### TypeScript errors after MoonBit changes

**Issue**: TypeScript shows errors for MoonBit imports

**Solution**: Ensure `tsconfig.json` has correct paths:
```json
{
  "compilerOptions": {
    "paths": {
      "@moonbit/mymodule": ["../mymodule/_build/js/release/build/mymodule.d.ts"]
    }
  }
}
```

### Watch process not starting

**Issue**: No `[MoonBit] Watching...` messages

**Solution**: Check that:
1. `moon` CLI is installed and in PATH
2. Module paths are correct
3. Watch mode is enabled (`watch: true`)

### Build fails on startup

**Issue**: `[MoonBit] Build failed:` error

**Solution**:
1. Run `moon build --target js` manually in module directory to see detailed errors
2. Check `moon.mod.json` configuration
3. Verify all dependencies are installed

## Advanced Usage

### Custom Watch Patterns

The `watch` field in module config is **deprecated** (not used with native watch mode):

```typescript
// ❌ This field is ignored when using moon build --watch
{
  name: '@moonbit/mymodule',
  path: '../mymodule',
  watch: ['src/**/*.mbt']  // Not used
}
```

MoonBit's native watch already handles all `.mbt` files intelligently.

### Multiple Targets

Build for different targets:

```typescript
// Browser target
moonbitPlugin({
  target: 'js',
  modules: [/* ... */]
})

// Node.js target
moonbitPlugin({
  target: 'js-node',
  modules: [/* ... */]
})
```

### Debug Mode

Enable debug builds for development:

```typescript
moonbitPlugin({
  release: false,  // Use debug mode
  modules: [/* ... */]
})
```

Debug builds are faster but larger and include debug symbols.

## Integration with Other Tools

### ESLint

Add to `.eslintignore`:
```
../_build/
../graphviz/_build/
```

### Prettier

Add to `.prettierignore`:
```
../_build/
../graphviz/_build/
```

### Git

Add to `.gitignore`:
```
_build/
```

## FAQ

### Does this work with Vite production builds?

Yes! The plugin runs `moon build` once during production builds (`vite build`) without watch mode.

### Can I use this with other build tools?

The plugin is Vite-specific, but the core concepts (Rollup hooks) work with any Rollup-based tool. You'd need to adapt the watch mode logic.

### Does this repo support WASM output?

Not in this repo's supported browser path. The plugin is used here for JS output, and the documented integration flow assumes generated JavaScript modules under `_build/...`.

### How do I debug MoonBit code in the browser?

Use `release: false` for debug builds. Debug builds include source maps and are easier to debug, but are larger.

### Can I use this in a monorepo?

Yes! The plugin supports any directory structure. Just set the correct `path` for each module relative to the Vite project root.

### What happens if MoonBit build fails?

The plugin logs the error and Vite continues running. Fix the MoonBit error and the watch process will automatically rebuild.

### Does this work with hot module replacement (HMR)?

The plugin triggers full page reloads, not granular HMR. MoonBit modules typically export stateful APIs, so full reloads are safest.

### Can I publish this as an npm package?

Yes! The plugin is designed to be general-purpose. Feel free to publish it as `vite-plugin-moonbit` or similar.

## License

Apache-2.0
