import { execFile, spawn, type ChildProcess } from 'node:child_process';
import { promisify } from 'node:util';
import { access, readFile } from 'node:fs/promises';
import path from 'node:path';
import type { Plugin, ViteDevServer } from 'vite';

const execFileAsync = promisify(execFile);

/**
 * Configuration for a MoonBit module
 */
export interface MoonBitModule {
  /** Virtual module name for imports (e.g., '@moonbit/mymodule') */
  name: string;
  /** Path to the MoonBit module directory (relative to Vite root) */
  path: string;
  /** Path to the built JS file relative to the module path. */
  output: string;
  /** Glob patterns to watch for changes (relative to module path, defaults to ['**\/*.mbt']) */
  watch?: string[];
  /** Additional build flags to pass to moon build */
  buildFlags?: string[];
}

/**
 * Vite plugin configuration for MoonBit
 */
export interface MoonBitBuildCoordinator {
  /** Workspace root used for the single build/watch process. */
  path: string;
  /** Additional flags shared by the coordinated root build. */
  buildFlags?: string[];
}

export function installMoonbitOutputReload(
  server: Pick<ViteDevServer, 'watcher' | 'moduleGraph' | 'ws'>,
  modules: ReadonlyArray<{ readonly name: string; readonly absoluteOutputPath: string }>,
): void {
  for (const module of modules) {
    server.watcher.add(module.absoluteOutputPath);
  }

  server.watcher.on('change', (file: string) => {
    const changedModule = modules.find(
      (module) => module.absoluteOutputPath === file,
    );
    if (!changedModule) return;

    console.log(`[MoonBit] ${changedModule.name} rebuilt, invalidating modules...`);
    const generatedModule = server.moduleGraph.getModuleById(changedModule.name);
    if (generatedModule) {
      server.moduleGraph.invalidateModule(generatedModule);
      for (const importer of generatedModule.importers) {
        server.moduleGraph.invalidateModule(importer);
      }
    }
    server.ws.send({ type: 'full-reload', path: '*' });
    console.log(`[MoonBit] ${changedModule.name} full reload complete`);
  });
}

export interface MoonBitPluginOptions {
  /** Array of MoonBit modules to import from the coordinated build output. */
  modules: MoonBitModule[];
  /** One workspace-root build/watch coordinator for every module. */
  coordinator: MoonBitBuildCoordinator;
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
  if (!options.coordinator) {
    throw new Error('[MoonBit] A build coordinator is required');
  }

  const {
    modules,
    coordinator,
    target = 'js',
    release = true,
    watch = true,
    skipIfExists = false,
  } = options;
  let initialBuild: Promise<void> | undefined;
  let watchProcess: ChildProcess | undefined;
  const reloadServers = new WeakSet<ViteDevServer>();

  // Auto-detect CI environment. CANOPY_SKIP_MOON_BUILD=1 is the project-wide
  // signal (see scripts/test-*-e2e.sh) that pre-built JS artifacts already
  // exist and the MoonBit toolchain may be unavailable (e.g. Playwright's
  // container image).
  const isCI = process.env.CI === 'true' || process.env.GITHUB_ACTIONS === 'true';
  const skipMoonBuild = process.env.CANOPY_SKIP_MOON_BUILD === '1';
  const externalWatch = process.env.CANOPY_EXTERNAL_MOON_WATCH === '1';
  const shouldSkipBuild = skipIfExists || isCI || skipMoonBuild || externalWatch;

  // Resolve absolute paths for modules
  const resolvedModules = modules.map(mod => {
    const modulePath = path.resolve(process.cwd(), mod.path);
    const outputPath = mod.output;
    const watchPatterns = mod.watch || ['**/*.mbt'];

    return {
      ...mod,
      absolutePath: modulePath,
      absoluteOutputPath: path.join(modulePath, outputPath),
      watchPatterns
    };
  });

  const resolvedCoordinator = {
    ...coordinator,
    absolutePath: path.resolve(process.cwd(), coordinator.path),
  };

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
      if (!initialBuild) {
        console.log('[MoonBit] Running one coordinated workspace build...');
        initialBuild = buildWorkspace(resolvedCoordinator, target, release);
      }
      await initialBuild;
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
      if (watch && shouldSkipBuild && !externalWatch) {
        console.log('[MoonBit] Skipping watch mode (CI / CANOPY_SKIP_MOON_BUILD=1), using pre-built modules');
      } else if (watch) {
        if (!externalWatch && !watchProcess) {
          // One workspace watcher produces every virtual module output for both
          // Vite and Waku development modes.
          console.log('[MoonBit] Starting one coordinated workspace watcher...');
          const flags = [
            'build',
            '--target', target,
            '--watch',
            ...(release ? ['--release'] : []),
            ...(resolvedCoordinator.buildFlags || []),
          ];
          watchProcess = spawn('moon', flags, {
            cwd: resolvedCoordinator.absolutePath,
            stdio: ['ignore', 'pipe', 'pipe'],
          });
          watchProcess.stdout?.on('data', (data) => {
            const output = data.toString().trim();
            if (output) console.log(`[MoonBit] ${output}`);
          });
          watchProcess.stderr?.on('data', (data) => {
            const output = data.toString().trim();
            if (output) console.error(`[MoonBit] ${output}`);
          });
          server.httpServer?.on('close', () => {
            console.log('[MoonBit] Stopping workspace watcher...');
            watchProcess?.kill();
            watchProcess = undefined;
          });
        }

        if (externalWatch) {
          console.log('[MoonBit] Reusing the dual-run root watcher.');
        }
        // A completed output write, rather than source-file churn, owns reload.
        if (!reloadServers.has(server)) {
          installMoonbitOutputReload(server, resolvedModules);
          reloadServers.add(server);
        }
      }
    }
  };
}

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

/** Build every configured output through one workspace-root invocation. */
async function buildWorkspace(
  coordinator: MoonBitBuildCoordinator & { absolutePath: string },
  target: string,
  release: boolean,
): Promise<void> {
  const args = [
    'build',
    '--target', target,
    ...(release ? ['--release'] : []),
    ...(coordinator.buildFlags || []),
  ];

  try {
    await execFileAsync('moon', args, { cwd: coordinator.absolutePath });
    console.log('[MoonBit] Coordinated workspace build succeeded');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Coordinated MoonBit build failed: ${message}`);
  }
}
