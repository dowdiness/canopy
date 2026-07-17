import { spawn as nodeSpawn, execFile as nodeExecFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  access,
  chmod,
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  realpath,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import { constants as fsConstants } from 'node:fs';
import { join } from 'node:path';
import { promisify } from 'node:util';

export const PINNED_CONFIG_SCHEMA_SHA256 = '841e0ab1c1bd2fea736ba2d46212ab5bedc06dce9fd83bbafbf50b57b9056d17';

const FORBIDDEN_FEATURES = Object.freeze([
  'apply_patch_freeform',
  'apps',
  'browser_use',
  'browser_use_external',
  'browser_use_full_cdp_access',
  'code_mode',
  'code_mode_host',
  'code_mode_only',
  'codex_git_commit',
  'codex_hooks',
  'collab',
  'collaboration_modes',
  'computer_use',
  'connectors',
  'default_mode_request_user_input',
  'enable_fanout',
  'enable_mcp_apps',
  'exec_permission_approvals',
  'experimental_use_unified_exec_tool',
  'hooks',
  'in_app_browser',
  'js_repl',
  'js_repl_tools_only',
  'memories',
  'memory_tool',
  'multi_agent',
  'multi_agent_mode',
  'network_proxy',
  'non_prefixed_mcp_tool_names',
  'plugin_hooks',
  'plugin_sharing',
  'plugins',
  'request_permissions',
  'request_permissions_tool',
  'search_tool',
  'shell_snapshot',
  'shell_tool',
  'shell_zsh_fork',
  'skill_env_var_dependency_prompt',
  'skill_mcp_dependency_install',
  'standalone_web_search',
  'tool_call_mcp_elicitation',
  'tool_search',
  'tool_search_always_defer_mcp_tools',
  'tool_suggest',
  'unavailable_dummy_tools',
  'unified_exec',
  'unified_exec_zsh_fork',
  'web_search',
  'web_search_cached',
  'web_search_request',
]);
const MOUNT_KEYS = Object.freeze([
  'static_codex_binary',
  'tls_certificate',
  'dns_configuration',
  'proc',
  'dev',
  'tmpfs_tmp',
  'empty_work',
  'private_codex_home',
]);
const ENVIRONMENT_KEYS = Object.freeze(['CODEX_HOME', 'HOME', 'LANG', 'SSL_CERT_FILE']);
const FIXED_CONFIG_KEY_PATHS = Object.freeze([
  'check_for_update_on_startup',
  'web_search',
  'include_apps_instructions',
  'include_collaboration_mode_instructions',
  'include_environment_context',
  'include_permissions_instructions',
  'project_doc_max_bytes',
  'project_doc_fallback_filenames',
  'mcp_servers',
  'plugins',
  'hooks',
  'analytics.enabled',
  'feedback.enabled',
  'history.persistence',
  'shell_environment_policy.inherit',
  'shell_environment_policy.include_only',
  'shell_environment_policy.set',
  'skills.include_instructions',
  'skills.config',
  'skills.bundled.enabled',
  'apps._default.enabled',
]);
export const MINIMAL_CONFIG_KEY_PATHS = Object.freeze([
  ...FIXED_CONFIG_KEY_PATHS,
  ...FORBIDDEN_FEATURES.map((feature) => `features.${feature}`),
]);

export function buildMinimalCodexConfig() {
  const lines = [
    'check_for_update_on_startup = false',
    'web_search = "disabled"',
    'include_apps_instructions = false',
    'include_collaboration_mode_instructions = false',
    'include_environment_context = false',
    'include_permissions_instructions = false',
    'project_doc_max_bytes = 0',
    'project_doc_fallback_filenames = []',
    'mcp_servers = {}',
    'plugins = {}',
    'hooks = {}',
    '',
    '[analytics]',
    'enabled = false',
    '',
    '[feedback]',
    'enabled = false',
    '',
    '[history]',
    'persistence = "none"',
    '',
    '[shell_environment_policy]',
    'inherit = "none"',
    'include_only = []',
    'set = {}',
    '',
    '[skills]',
    'include_instructions = false',
    'config = []',
    '',
    '[skills.bundled]',
    'enabled = false',
    '',
    '[apps._default]',
    'enabled = false',
    '',
    '[features]',
    ...FORBIDDEN_FEATURES.map((feature) => `${feature} = false`),
    '',
  ];
  return lines.join('\n');
}

export function buildCodexSandboxSpec({
  bwrapBinary,
  codexBinary,
  privateHome,
  tlsCertificate,
  dnsFiles,
}) {
  const args = [
    '--unshare-all',
    '--share-net',
    '--die-with-parent',
    '--new-session',
    '--clearenv',
    '--setenv', 'HOME', '/codex-home',
    '--setenv', 'CODEX_HOME', '/codex-home',
    '--setenv', 'SSL_CERT_FILE', '/etc/ssl/certs/ca-certificates.crt',
    '--setenv', 'LANG', 'C.UTF-8',
    '--dir', '/bin',
    '--ro-bind', codexBinary, '/bin/codex',
    '--dir', '/etc',
    '--dir', '/etc/ssl',
    '--dir', '/etc/ssl/certs',
    '--ro-bind', tlsCertificate, '/etc/ssl/certs/ca-certificates.crt',
  ];
  for (const source of dnsFiles) args.push('--ro-bind', source, source);
  args.push(
    '--proc', '/proc',
    '--dev', '/dev',
    '--tmpfs', '/tmp',
    '--dir', '/work',
    '--bind', privateHome, '/codex-home',
    '--chdir', '/work',
    '--',
    '/bin/codex',
    'app-server',
  );
  return Object.freeze({
    file: bwrapBinary,
    args: Object.freeze(args),
    options: Object.freeze({
      detached: true,
      env: Object.freeze({}),
      stdio: Object.freeze(['pipe', 'pipe', 'pipe']),
    }),
  });
}

export async function prepareCodexSandbox({
  runRoot,
  codexBinary,
  bwrapBinary = '/usr/bin/bwrap',
  authSource,
  canaries,
}, deps = {}) {
  validateInputs({ runRoot, codexBinary, bwrapBinary, authSource, canaries });
  const spawn = deps.spawn ?? nodeSpawn;
  const resolveExecutable = deps.resolveExecutable ?? realpath;
  const checkExecutable = deps.validateExecutable ?? validateExecutable;
  const readVersion = deps.readVersion ?? defaultReadVersion;
  const sha256File = deps.sha256File ?? defaultSha256File;
  const runIsolationPreflight = deps.runIsolationPreflight ?? defaultRunIsolationPreflight;
  const signalSource = deps.signalSource ?? process;

  await mkdir(runRoot, { recursive: true, mode: 0o700 });
  await chmod(runRoot, 0o700);
  const privateHome = await mkdtemp(join(runRoot, '.codex-home-'));
  await chmod(privateHome, 0o700);
  const authPath = join(privateHome, 'auth.json');
  const configPath = join(privateHome, 'config.toml');
  const activeChildren = new Set();
  const auditErrors = [];
  let cleaned = false;

  const cleanup = async () => {
    if (cleaned) return;
    cleaned = true;
    removeSignalHandlers();
    for (const child of activeChildren) child.kill('SIGKILL');
    activeChildren.clear();
    await rm(privateHome, { recursive: true, force: true });
    if (auditErrors.length > 0) throw auditErrors[0];
  };
  const signalHandler = () => {
    void cleanup().catch(() => undefined);
  };
  const signalNames = ['SIGINT', 'SIGTERM', 'SIGHUP'];
  const removeSignalHandlers = () => {
    for (const signal of signalNames) signalSource.off?.(signal, signalHandler);
  };
  for (const signal of signalNames) signalSource.on?.(signal, signalHandler);

  try {
    const [resolvedCodex, resolvedBwrap] = await Promise.all([
      resolveExecutable(codexBinary),
      resolveExecutable(bwrapBinary),
    ]);
    await checkExecutable(resolvedCodex, 'Codex');
    await checkExecutable(resolvedBwrap, 'bubblewrap');
    await validatePrivateAuthSource(authSource);
    await copyFile(authSource, authPath, fsConstants.COPYFILE_EXCL);
    await chmod(authPath, 0o600);
    const config = buildMinimalCodexConfig();
    await writeFile(configPath, config, { mode: 0o600, flag: 'wx' });
    await chmod(configPath, 0o600);

    const tlsCertificate = '/etc/ssl/certs/ca-certificates.crt';
    await access(tlsCertificate, fsConstants.R_OK);
    const dnsFiles = await existingFiles([
      '/etc/resolv.conf',
      '/etc/hosts',
      '/etc/nsswitch.conf',
      '/etc/gai.conf',
    ]);
    if (!dnsFiles.includes('/etc/resolv.conf')) {
      throw sandboxError('sandbox_preflight_failed', 'DNS resolver configuration is absent.');
    }
    const spec = buildCodexSandboxSpec({
      bwrapBinary: resolvedBwrap,
      codexBinary: resolvedCodex,
      privateHome,
      tlsCertificate,
      dnsFiles,
    });
    const canaryOutcomes = await runIsolationPreflight({
      spec,
      spawn,
      bwrapBinary: resolvedBwrap,
      codexBinary: resolvedCodex,
      canaries,
    });
    requirePassingPreflight(canaryOutcomes);

    const [bwrapVersion, codexVersion, codexBinarySha256, configSha256] = await Promise.all([
      readVersion(resolvedBwrap),
      readVersion(resolvedCodex),
      sha256File(resolvedCodex),
      sha256Bytes(config),
    ]);
    const contract = deepFreeze({
      version: 1,
      bwrapVersion,
      codexVersion,
      codexBinarySha256,
      configSha256,
      configSchemaSha256: PINNED_CONFIG_SCHEMA_SHA256,
      configKeyPaths: [...MINIMAL_CONFIG_KEY_PATHS],
      mountKeys: [...MOUNT_KEYS],
      environmentKeys: [...ENVIRONMENT_KEYS],
      canaryOutcomes: { ...canaryOutcomes },
    });
    assertCanaryFree(contract, canaries, 'sandbox contract');

    const spawnProcess = async () => {
      if (cleaned) {
        throw sandboxError('sandbox_unavailable', 'Codex sandbox has been cleaned up.');
      }
      const child = spawn(spec.file, [...spec.args], {
        ...spec.options,
        env: {},
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      const namespacePid = typeof child.once === 'function' && Number.isInteger(child.pid)
        ? await waitForNamespace(child.pid, async (root) => (
            await defaultPathExists(`${root}/bin/codex`)
          ) && (
            await defaultPathExists(`${root}/codex-home/config.toml`)
          ))
        : child.pid;
      const wrapped = wrapChildProcess(child, canaries, auditErrors, namespacePid);
      activeChildren.add(wrapped);
      void wrapped.exit.finally(() => activeChildren.delete(wrapped));
      return wrapped;
    };

    return Object.freeze({ spawnProcess, contract, cleanup });
  } catch (error) {
    await cleanup().catch(() => undefined);
    throw error;
  }
}

export async function inspectNamespaceRoot(pid, {
  required = [],
  forbidden = [],
  emptyDirectories = [],
}, deps = {}) {
  if (!Number.isInteger(pid) || pid <= 0) {
    throw sandboxError('sandbox_preflight_failed', 'Namespace PID is invalid.');
  }
  const pathExists = deps.pathExists ?? defaultPathExists;
  const readDirectory = deps.readdir ?? readdir;
  const root = `/proc/${pid}/root`;
  const requiredPathsPresent = await everyAsync(
    required,
    (path) => pathExists(namespacePath(root, path)),
  );
  const forbiddenPathsHidden = await everyAsync(
    forbidden.filter((path) => typeof path === 'string' && path.startsWith('/')),
    async (path) => !(await pathExists(namespacePath(root, path))),
  );
  const workDirectoryEmpty = await everyAsync(emptyDirectories, async (path) => {
    try {
      return (await readDirectory(namespacePath(root, path))).length === 0;
    } catch {
      return false;
    }
  });
  return Object.freeze({ requiredPathsPresent, forbiddenPathsHidden, workDirectoryEmpty });
}

export function assertCanaryFree(value, canaries, surface) {
  const text = Buffer.isBuffer(value)
    ? value.toString('utf8')
    : typeof value === 'string'
      ? value
      : JSON.stringify(value);
  for (const canary of [...canaries.hostPaths, ...canaries.secretValues]) {
    if (canary.length > 0 && text.includes(canary)) {
      throw sandboxError(
        'credential_or_canary_leak',
        `${surface} contains a forbidden canary.`,
      );
    }
  }
}

async function defaultRunIsolationPreflight({
  spec,
  spawn,
  bwrapBinary,
  codexBinary,
  canaries,
}) {
  const detectorCanary = canaries.hostPaths[0];
  const permissive = spawn(bwrapBinary, [
    '--unshare-all',
    '--share-net',
    '--die-with-parent',
    '--new-session',
    '--ro-bind', '/', '/',
    '--',
    codexBinary,
    'app-server',
  ], { detached: true, env: {}, stdio: ['pipe', 'ignore', 'ignore'] });
  try {
    await waitForNamespace(permissive.pid, async (root) => (
      defaultPathExists(namespacePath(root, detectorCanary))
    ));
  } finally {
    await stopChild(permissive);
  }

  const production = spawn(spec.file, [...spec.args], {
    ...spec.options,
    env: {},
    stdio: ['pipe', 'ignore', 'ignore'],
  });
  try {
    const namespacePid = await waitForNamespace(production.pid, async (root) => (
      await defaultPathExists(`${root}/bin/codex`)
    ) && !(
      await defaultPathExists(namespacePath(root, detectorCanary))
    ));
    const inspection = await inspectNamespaceRoot(namespacePid, {
      required: [
        '/bin/codex',
        '/etc/ssl/certs/ca-certificates.crt',
        '/etc/resolv.conf',
        '/proc',
        '/dev/null',
        '/tmp',
        '/work',
        '/codex-home/auth.json',
        '/codex-home/config.toml',
      ],
      forbidden: [
        ...canaries.hostPaths,
        '/bin/sh',
        '/usr/bin',
        '/usr/local/bin',
        '/home',
        '/root',
      ],
      emptyDirectories: ['/work'],
    });
    return Object.freeze({
      detectorPositive: true,
      hostCanariesHidden: canaries.hostPaths.every((path) => path.startsWith('/')) && inspection.forbiddenPathsHidden,
      forbiddenPathsHidden: inspection.forbiddenPathsHidden,
      requiredPathsPresent: inspection.requiredPathsPresent,
      workDirectoryEmpty: inspection.workDirectoryEmpty,
    });
  } finally {
    await stopChild(production);
  }
}

function wrapChildProcess(child, canaries, auditErrors, namespacePid = child.pid) {
  let auditError = null;
  const exit = child.exit ?? (typeof child.once === 'function'
    ? new Promise((resolve, reject) => {
        child.once('error', reject);
        child.once('exit', (code, signal) => resolve({ code, signal }));
      })
    : Promise.resolve({ code: null, signal: null }));
  const wrapped = {
    pid: namespacePid,
    stdin: child.stdin,
    stdout: child.stdout,
    stderr: child.stderr,
    exit,
    get killed() {
      return child.killed;
    },
    kill(signal) {
      if (typeof child.once === 'function' && Number.isInteger(child.pid)) {
        try {
          process.kill(-child.pid, signal);
          return true;
        } catch {
          // Fall through to the child handle if the process group already exited.
        }
      }
      return child.kill(signal);
    },
    assertAudit() {
      if (auditError) throw auditError;
    },
  };
  child.stderr?.on?.('data', (chunk) => {
    try {
      assertCanaryFree(chunk, canaries, 'Codex stderr');
    } catch (error) {
      auditError = error;
      auditErrors.push(error);
      wrapped.kill('SIGKILL');
    }
  });
  return Object.freeze(wrapped);
}

async function waitForNamespace(parentPid, ready) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const descendants = await descendantPids(parentPid);
    for (const pid of descendants.toReversed()) {
      if (await ready(`/proc/${pid}/root`)) return pid;
    }
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  throw sandboxError('sandbox_preflight_failed', 'Sandbox namespace did not become inspectable.');
}

async function descendantPids(parentPid) {
  const pending = [parentPid];
  const descendants = [];
  while (pending.length > 0) {
    const pid = pending.shift();
    let children;
    try {
      children = (await readFile(`/proc/${pid}/task/${pid}/children`, 'utf8'))
        .trim()
        .split(/\s+/u)
        .filter(Boolean)
        .map(Number);
    } catch {
      children = [];
    }
    descendants.push(...children);
    pending.push(...children);
  }
  return descendants;
}

async function stopChild(child) {
  if (!child) return;
  const parentRunning = child.exitCode === null && child.signalCode === null;
  const exited = parentRunning && typeof child.once === 'function'
    ? new Promise((resolve) => child.once('exit', resolve))
    : null;
  try {
    process.kill(-child.pid, 'SIGKILL');
  } catch {
    child.kill?.('SIGKILL');
  }
  if (exited) await exited;
}

async function defaultReadVersion(file) {
  const execFile = promisify(nodeExecFile);
  const { stdout } = await execFile(file, ['--version'], { env: {}, encoding: 'utf8' });
  return stdout.trim();
}

async function defaultSha256File(path) {
  return sha256Bytes(await readFile(path));
}

function sha256Bytes(value) {
  return createHash('sha256').update(value).digest('hex');
}

async function validateExecutable(path, label) {
  try {
    await access(path, fsConstants.R_OK | fsConstants.X_OK);
    const metadata = await stat(path);
    if (!metadata.isFile()) throw new Error('not a file');
  } catch {
    throw sandboxError('sandbox_preflight_failed', `${label} executable is unavailable.`);
  }
}

async function validatePrivateAuthSource(path) {
  try {
    const metadata = await stat(path);
    if (!metadata.isFile() || (metadata.mode & 0o077) !== 0) throw new Error('not private');
  } catch {
    throw sandboxError('credential_preflight_failed', 'Codex auth source must be a private regular file.');
  }
}

function validateInputs({ runRoot, codexBinary, bwrapBinary, authSource, canaries }) {
  if (![runRoot, codexBinary, bwrapBinary, authSource].every((value) => typeof value === 'string' && value.startsWith('/'))) {
    throw sandboxError('sandbox_preflight_failed', 'Sandbox paths must be absolute.');
  }
  if (
    !canaries ||
    !Array.isArray(canaries.hostPaths) ||
    canaries.hostPaths.length === 0 ||
    !Array.isArray(canaries.secretValues) ||
    canaries.secretValues.length === 0
  ) {
    throw sandboxError('sandbox_preflight_failed', 'Sandbox canaries are required.');
  }
}

function requirePassingPreflight(outcomes) {
  const required = [
    'detectorPositive',
    'hostCanariesHidden',
    'forbiddenPathsHidden',
    'requiredPathsPresent',
    'workDirectoryEmpty',
  ];
  if (!outcomes || !required.every((key) => outcomes[key] === true)) {
    throw sandboxError('sandbox_preflight_failed', 'Codex sandbox isolation preflight failed closed.');
  }
}

async function existingFiles(paths) {
  const present = [];
  for (const path of paths) {
    if (await defaultPathExists(path)) present.push(path);
  }
  return present;
}

async function everyAsync(values, predicate) {
  for (const value of values) {
    if (!(await predicate(value))) return false;
  }
  return true;
}

async function defaultPathExists(path) {
  try {
    await access(path, fsConstants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function namespacePath(root, absolutePath) {
  return `${root}${absolutePath}`;
}

function sandboxError(classification, message) {
  const error = new Error(message);
  error.name = 'CodexSandboxError';
  error.classification = classification;
  return error;
}

function deepFreeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}
