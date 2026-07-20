import { exec, spawn, type ChildProcess } from 'node:child_process';
import { promisify } from 'node:util';
import { access, readFile } from 'node:fs/promises';
import path from 'node:path';
import type { Plugin, ViteDevServer } from 'vite';

const execAsync = promisify(exec);

/**
 * Configuration for a MoonBit module
 */
export interface MoonBitModule {
  /** Virtual module name for imports (e.g., '@moonbit/mymodule') */
  name: string;
  /** Path to the MoonBit module directory (relative to Vite root) */
  path: string;
  /** Path to the built JS file (relative to module path, defaults to '_build/js/release/build/{last-part-of-name}.js') */
  output?: string;
  /** Glob patterns to watch for changes (relative to module path, defaults to ['**\/*.mbt']) */
  watch?: string[];
  /** Additional build flags to pass to moon build */
  buildFlags?: string[];
}

/**
 * Vite plugin configuration for MoonBit
 */
export interface MoonBitPluginOptions {
  /** Array of MoonBit modules to build and import */
  modules: MoonBitModule[];
  /** Target for moon build (defaults to 'js') */
  target?: string;
  /** Whether to build in release mode (defaults to true) */
  release?: boolean;
  /** Enable MoonBit watch mode in development (defaults to true) */
  watch?: boolean;
  /** Skip building if output files exist (useful in CI, defaults to false) */
  skipIfExists?: boolean;
}

/**
 * Vite plugin for building and importing MoonBit modules
 *
 * @example
 * ```typescript
 * moonbitPlugin({
 *   modules: [
 *     {
 *       name: '@moonbit/crdt-lambda',
 *       path: '..',
 *       output: '_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js'
 *     },
 *     {
 *       name: '@moonbit/graphviz',
 *       path: '../graphviz',
 *       output: '_build/js/release/build/browser/browser.js'
 *     }
 *   ]
 * })
 * ```
 */
export function moonbitPlugin(options: MoonBitPluginOptions): Plugin {
  const { modules, target = 'js', release = true, watch = true, skipIfExists = false } = options;
  const watchProcesses: ChildProcess[] = [];

  // Auto-detect CI environment. CANOPY_SKIP_MOON_BUILD=1 is the project-wide
  // signal (see scripts/test-*-e2e.sh) that pre-built JS artifacts already
  // exist and the MoonBit toolchain may be unavailable (e.g. Playwright's
  // container image).
  const isCI = process.env.CI === 'true' || process.env.GITHUB_ACTIONS === 'true';
  const skipMoonBuild = process.env.CANOPY_SKIP_MOON_BUILD === '1';
  const shouldSkipBuild = skipIfExists || isCI || skipMoonBuild;

  // Resolve absolute paths for modules
  const resolvedModules = modules.map(mod => {
    const modulePath = path.resolve(process.cwd(), mod.path);
    const outputPath = mod.output || inferOutputPath(mod.name, target, release);
    const watchPatterns = mod.watch || ['**/*.mbt'];

    return {
      ...mod,
      absolutePath: modulePath,
      absoluteOutputPath: path.join(modulePath, outputPath),
      watchPatterns
    };
  });

  // Create module name -> output path map
  const moduleMap = new Map(
    resolvedModules.map(mod => [mod.name, mod.absoluteOutputPath])
  );

  return {
    name: 'vite-plugin-moonbit',

    async buildStart() {
      if (shouldSkipBuild) {
        console.log('[MoonBit] CI mode detected, checking for pre-built modules...');
        const missingModules = await findMissingModules(resolvedModules);
        if (missingModules.length === 0) {
          console.log('[MoonBit] All pre-built modules found, skipping build');
          return;
        }
        const missingList = missingModules.map(m => '  ' + m.name + ' at ' + m.absoluteOutputPath).join('\n');
        throw new Error(
          '[MoonBit] Pre-built modules missing (CANOPY_SKIP_MOON_BUILD=1 but moon toolchain unavailable):\n' +
          missingList,
        );
      }
      console.log('[MoonBit] Building modules...');
      await buildAllModules(resolvedModules, target, release);
    },

    resolveId(id: string) {
      // Resolve virtual module IDs
      if (moduleMap.has(id)) {
        return id;
      }
      return null;
    },

    async load(id: string) {
      // Load MoonBit modules from build output
      const outputPath = moduleMap.get(id);
      if (outputPath) {
        try {
          const code = await readFile(outputPath, 'utf-8');
          return { code, map: null };
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          throw new Error(`Failed to load MoonBit module '${id}': ${message}`);
        }
      }
      return null;
    },

    configureServer(server: ViteDevServer) {
      if (watch && shouldSkipBuild) {
        console.log('[MoonBit] Skipping watch mode (CI / CANOPY_SKIP_MOON_BUILD=1), using pre-built modules');
      } else if (watch) {
        // Start MoonBit watch mode for each module
        console.log('[MoonBit] Starting watch mode...');

        for (const mod of resolvedModules) {
          const flags = [
            'build',
            '--target', target,
            '--watch',
            ...(release ? ['--release'] : []),
            ...(mod.buildFlags || [])
          ];

          console.log(`[MoonBit] Watching ${mod.name}...`);

          const watchProcess = spawn('moon', flags, {
            cwd: mod.absolutePath,
            stdio: ['ignore', 'pipe', 'pipe']
          });

          // Log output
          watchProcess.stdout?.on('data', (data) => {
            const output = data.toString().trim();
            if (output) {
              console.log(`[MoonBit:${mod.name}] ${output}`);
            }
          });

          watchProcess.stderr?.on('data', (data) => {
            const output = data.toString().trim();
            if (output) {
              console.error(`[MoonBit:${mod.name}] ${output}`);
            }
          });

          watchProcesses.push(watchProcess);
        }

        // Watch output files for changes and trigger HMR
        for (const mod of resolvedModules) {
          server.watcher.add(mod.absoluteOutputPath);
        }

        server.watcher.on('change', async (file: string) => {
          // Check if a MoonBit output file changed
          const changedModule = resolvedModules.find(
            mod => mod.absoluteOutputPath === file
          );

          if (changedModule) {
            console.log(`[MoonBit] ${changedModule.name} rebuilt, invalidating modules...`);

            // Invalidate the virtual module in Vite's module graph
            const mod = server.moduleGraph.getModuleById(changedModule.name);
            if (mod) {
              server.moduleGraph.invalidateModule(mod);

              // Invalidate all modules that import this MoonBit module
              const importers = [...mod.importers];
              for (const importer of importers) {
                server.moduleGraph.invalidateModule(importer);
              }
            }

            // Trigger HMR update
            server.ws.send({
              type: 'full-reload',
              path: '*'
            });

            console.log(`[MoonBit] ${changedModule.name} HMR complete`);
          }
        });

        // Clean up watch processes when server closes
        server.httpServer?.on('close', () => {
          console.log('[MoonBit] Stopping watch processes...');
          for (const proc of watchProcesses) {
            proc.kill();
          }
        });
      }
    }
  };
}

/**
 * Infer output path from module name and build settings
 */
///|
/// Return list of modules whose output files are missing.
async function findMissingModules(
  modules: Array<MoonBitModule & { absoluteOutputPath: string }>
): Promise<Array<MoonBitModule & { absoluteOutputPath: string }>> {
  const missing: Array<MoonBitModule & { absoluteOutputPath: string }> = []
  for (const mod of modules) {
    try {
      await access(mod.absoluteOutputPath);
    } catch {
      console.log(`[MoonBit] Missing: ${mod.name} at ${mod.absoluteOutputPath}`);
      missing.push(mod)
    }
  }
  return missing
}

/**
 * Build all MoonBit modules
 */
async function buildAllModules(
  modules: Array<MoonBitModule & { absolutePath: string }>,
  target: string,
  release: boolean
): Promise<void> {
  await Promise.all(modules.map(mod => buildModule(mod, target, release)));
  console.log('[MoonBit] All modules built successfully');
}

/**
 * Build a single MoonBit module
 */
async function buildModule(
  mod: MoonBitModule & { absolutePath: string },
  target: string,
  release: boolean
): Promise<void> {
  const flags = [
    '--target', target,
    ...(release ? ['--release'] : []),
    ...(mod.buildFlags || [])
  ];

  const command = `moon build ${flags.join(' ')}`;

  try {
    await execAsync(command, { cwd: mod.absolutePath });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Failed to build ${mod.name}: ${message}`);
  }
}
