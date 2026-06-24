import { exec, spawn, type ChildProcess } from 'node:child_process';
import { promisify } from 'node:util';
import { access, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
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

  // Auto-detect CI environment
  const isCI = process.env.CI === 'true' || process.env.GITHUB_ACTIONS === 'true';
  const shouldSkipBuild = skipIfExists || isCI;

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
        const allExist = await checkAllModulesExist(resolvedModules);
        if (allExist) {
          console.log('[MoonBit] All pre-built modules found, skipping build');
          return;
        } else {
          console.log('[MoonBit] Some modules missing, building...');
        }
      } else {
        console.log('[MoonBit] Building modules...');
      }
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
      server.middlewares.use('/api/ast-grep', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: 'method not allowed' }));
          return;
        }

        try {
          const body = JSON.parse(await readRequestBody(req, 1_000_000)) as { text?: unknown };
          const text = typeof body.text === 'string' ? body.text : '';
          const matches = await runAstGrep(text);
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ matches }));
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          res.statusCode = message.includes('request body too large') ? 413 : 500;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ error: message }));
        }
      });

      if (watch) {
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
function inferOutputPath(moduleName: string, target: string, release: boolean): string {
  // Extract last part of module name (e.g., '@moonbit/crdt' -> 'crdt')
  const baseName = moduleName.split('/').pop() || 'module';
  const mode = release ? 'release' : 'debug';
  return `_build/${target}/${mode}/build/${baseName}.js`;
}

/**
 * Check if all module output files exist
 */
async function checkAllModulesExist(
  modules: Array<MoonBitModule & { absoluteOutputPath: string }>
): Promise<boolean> {
  for (const mod of modules) {
    try {
      await access(mod.absoluteOutputPath);
    } catch {
      console.log(`[MoonBit] Missing: ${mod.name} at ${mod.absoluteOutputPath}`);
      return false;
    }
  }
  return true;
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
type AstGrepJsonMatch = {
  ruleId?: string;
  range?: { byteOffset?: { start?: number; end?: number } };
};

async function readRequestBody(
  req: import('node:http').IncomingMessage,
  maxBytes: number,
): Promise<string> {
  const chunks: Buffer[] = [];
  let totalBytes = 0;
  for await (const chunk of req) {
    const buffer = typeof chunk === 'string' ? Buffer.from(chunk) : chunk;
    totalBytes += buffer.byteLength;
    if (totalBytes > maxBytes) {
      throw new Error('request body too large for ast-grep analysis');
    }
    chunks.push(buffer);
  }
  return Buffer.concat(chunks).toString('utf8');
}

async function runAstGrep(text: string): Promise<Array<{ byte_start: number; byte_end: number; pattern_id: string }>> {
  if (text.trim() === '') return [];

  const repoRoot = path.resolve(process.cwd(), '../..');
  const astGrepBin = process.env.AST_GREP_BIN ?? path.resolve(process.cwd(), 'node_modules/.bin/sg');
  const tempDir = await mkdtemp(path.join(tmpdir(), 'canopy-ast-grep-'));
  const tempFile = path.join(tempDir, 'input.mbt');

  try {
    await writeFile(tempFile, text, 'utf8');
    const { stdout, stderr, code } = await runProcess(
      astGrepBin,
      [
        'scan',
        '-c', 'sgconfig.yml',
        '--filter', '^moonbit-fn-def$',
        tempFile,
        '--json=stream',
      ],
      '',
      repoRoot,
      5_000,
    );

    if (code !== 0) {
      throw new Error(stderr || `ast-grep exited with code ${code}`);
    }

    return stdout
      .split('\n')
      .map(line => line.trim())
      .filter(Boolean)
      .map(line => JSON.parse(line) as AstGrepJsonMatch)
      .map(match => {
        const start = match.range?.byteOffset?.start;
        const end = match.range?.byteOffset?.end;
        if (typeof start !== 'number' || typeof end !== 'number') {
          throw new Error('ast-grep result missing byte offsets');
        }
        return {
          byte_start: start,
          byte_end: end,
          pattern_id: match.ruleId ?? 'moonbit-fn-def',
        };
      });
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

function runProcess(
  command: string,
  args: string[],
  input: string,
  cwd: string,
  timeoutMs: number,
): Promise<{ stdout: string; stderr: string; code: number | null }> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    let settled = false;
    let timedOut = false;

    const timeout = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
    }, timeoutMs);

    child.stdout?.on('data', data => { stdout += data.toString(); });
    child.stderr?.on('data', data => { stderr += data.toString(); });
    child.on('error', error => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });
    child.on('close', code => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      resolve({
        stdout,
        stderr: timedOut ? `ast-grep timed out after ${timeoutMs}ms` : stderr,
        code,
      });
    });
    child.stdin?.end(input);
  });
}

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
