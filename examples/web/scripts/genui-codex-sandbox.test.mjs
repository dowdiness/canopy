import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { access, chmod, mkdir, readFile, realpath, stat, writeFile } from 'node:fs/promises';
import { constants as fsConstants } from 'node:fs';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import test from 'node:test';

import {
  MINIMAL_CONFIG_KEY_PATHS,
  PINNED_CONFIG_SCHEMA_SHA256,
  assertCanaryFree,
  buildCodexSandboxSpec,
  buildMinimalCodexConfig,
  inspectNamespaceRoot,
  prepareCodexSandbox,
} from './genui-codex-sandbox.mjs';

const AUTH_BYTES = '{"tokens":{"access_token":"AUTH-BYTE-CANARY"}}\n';
const PINNED_SCHEMA_SHA256 = '841e0ab1c1bd2fea736ba2d46212ab5bedc06dce9fd83bbafbf50b57b9056d17';
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

function findExecutable(name) {
  for (const directory of (process.env.PATH ?? '').split(delimiter)) {
    if (directory) return join(directory, name);
  }
  throw new Error(`PATH is empty while locating ${name}`);
}

async function executable(name) {
  for (const directory of (process.env.PATH ?? '').split(delimiter)) {
    if (!directory) continue;
    const candidate = join(directory, name);
    try {
      await access(candidate, fsConstants.X_OK);
      return realpath(candidate);
    } catch {
      // Try the next PATH entry.
    }
  }
  throw new Error(`Required executable is absent: ${name}`);
}

async function temporaryFixture() {
  const root = await import('node:fs/promises').then(({ mkdtemp }) => mkdtemp(join(tmpdir(), 'canopy-codex-sandbox-')));
  const runRoot = join(root, 'run');
  const rawRoot = join(runRoot, 'raw');
  const authSource = join(root, 'auth.json');
  const hostCanary = join(root, 'HOST-PATH-CANARY');
  const unrelatedCodexState = join(root, 'unrelated-codex-home', 'MEMORY-CANARY');
  await mkdir(rawRoot, { recursive: true, mode: 0o700 });
  await mkdir(join(root, 'unrelated-codex-home'), { mode: 0o700 });
  await writeFile(authSource, AUTH_BYTES, { mode: 0o600 });
  await writeFile(hostCanary, 'host-visible', { mode: 0o600 });
  await writeFile(unrelatedCodexState, 'must-stay-hidden', { mode: 0o600 });
  await writeFile(join(rawRoot, 'keep.json'), '{}\n', { mode: 0o600 });
  return {
    root,
    runRoot,
    rawRoot,
    authSource,
    hostCanary,
    unrelatedCodexState,
    canaries: {
      hostPaths: [hostCanary, unrelatedCodexState],
      secretValues: ['AUTH-BYTE-CANARY', 'SECRET-TRANSCRIPT-CANARY'],
    },
  };
}

function parseToml(config) {
  const values = new Map();
  let table = '';
  for (const rawLine of config.split('\n')) {
    const line = rawLine.trim();
    if (line === '' || line.startsWith('#')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      table = line.slice(1, -1);
      continue;
    }
    const equals = line.indexOf('=');
    assert.notEqual(equals, -1, line);
    const key = line.slice(0, equals).trim();
    const literal = line.slice(equals + 1).trim();
    values.set(table ? `${table}.${key}` : key, literal);
  }
  return values;
}

function fakeIsolationPreflight() {
  return {
    detectorPositive: true,
    hostCanariesHidden: true,
    forbiddenPathsHidden: true,
    requiredPathsPresent: true,
    workDirectoryEmpty: true,
  };
}

function fakeSpawnRecorder() {
  const calls = [];
  const children = [];
  const spawn = (file, args, options) => {
    const stderr = new EventEmitter();
    const stdout = new EventEmitter();
    stdout[Symbol.asyncIterator] = async function* () {};
    const stdin = { write() {}, end() {} };
    const child = {
      pid: 4242 + calls.length,
      stdin,
      stdout,
      stderr,
      killed: false,
      kill(signal) {
        this.killed = signal;
        return true;
      },
      exit: new Promise(() => {}),
    };
    calls.push({ file, args, options });
    children.push(child);
    queueMicrotask(() => child.onSpawn?.());
    return child;
  };
  return { calls, children, spawn };
}
async function waitUntilMissing(path) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      await access(path);
    } catch {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.fail(`path remained after cleanup: ${path}`);
}


test('minimal config disables persistence, telemetry, context injection, tools, and extensions', () => {
  const config = buildMinimalCodexConfig();
  const values = parseToml(config);

  assert.equal(PINNED_CONFIG_SCHEMA_SHA256, PINNED_SCHEMA_SHA256);
  assert.deepEqual([...values.keys()].sort(), [...MINIMAL_CONFIG_KEY_PATHS].sort());
  assert.equal(values.get('history.persistence'), '"none"');
  assert.equal(values.get('analytics.enabled'), 'false');
  assert.equal(values.get('feedback.enabled'), 'false');
  assert.equal(values.get('check_for_update_on_startup'), 'false');
  assert.equal(values.get('web_search'), '"disabled"');
  assert.equal(values.get('include_apps_instructions'), 'false');
  assert.equal(values.get('include_collaboration_mode_instructions'), 'false');
  assert.equal(values.get('include_environment_context'), 'false');
  assert.equal(values.get('include_permissions_instructions'), 'false');
  assert.equal(values.get('project_doc_max_bytes'), '0');
  assert.equal(values.get('project_doc_fallback_filenames'), '[]');
  assert.equal(values.get('shell_environment_policy.inherit'), '"none"');
  assert.equal(values.get('shell_environment_policy.include_only'), '[]');
  assert.equal(values.get('shell_environment_policy.set'), '{}');
  assert.equal(values.get('skills.include_instructions'), 'false');
  assert.equal(values.get('skills.config'), '[]');
  assert.equal(values.get('skills.bundled.enabled'), 'false');
  assert.equal(values.get('apps._default.enabled'), 'false');
  assert.equal(values.get('mcp_servers'), '{}');
  assert.equal(values.get('plugins'), '{}');
  for (const feature of FORBIDDEN_FEATURES) {
    assert.equal(values.get(`features.${feature}`), 'false', feature);
  }
});

test('bubblewrap spec exposes only the approved static runtime and a clear environment', () => {
  const spec = buildCodexSandboxSpec({
    bwrapBinary: '/usr/bin/bwrap',
    codexBinary: '/private/static/codex',
    privateHome: '/private/run/codex-home',
    tlsCertificate: '/etc/ssl/certs/ca-certificates.crt',
    dnsFiles: ['/etc/resolv.conf', '/etc/hosts', '/etc/nsswitch.conf'],
  });

  assert.equal(spec.file, '/usr/bin/bwrap');
  assert.deepEqual(spec.options.env, {});
  assert.equal(spec.options.detached, true);
  assert.deepEqual(spec.options.stdio, ['pipe', 'pipe', 'pipe']);
  for (const flag of ['--unshare-all', '--share-net', '--die-with-parent', '--new-session', '--clearenv']) {
    assert.ok(spec.args.includes(flag), flag);
  }
  assert.ok(spec.args.includes('/bin/codex'));
  assert.ok(spec.args.includes('/codex-home'));
  assert.ok(spec.args.includes('/work'));
  assert.ok(spec.args.includes('/tmp'));
  assert.ok(spec.args.includes('/proc'));
  assert.ok(spec.args.includes('/dev'));
  for (const forbidden of ['/bin/sh', '/usr/bin', '/usr/local/bin', 'node', 'git', 'npm', 'HOME=', 'AUTH-BYTE-CANARY']) {
    assert.equal(spec.args.join('\0').includes(forbidden), false, forbidden);
  }
  const environmentKeys = spec.args
    .flatMap((value, index, args) => args[index - 1] === '--setenv' ? [value] : [])
  assert.deepEqual(environmentKeys.sort(), ['CODEX_HOME', 'HOME', 'LANG', 'SSL_CERT_FILE']);
});

test('detector positive control sees a host canary but production namespace hides host state', {
  skip: process.platform !== 'linux',
}, async (context) => {
  let bwrapBinary;
  let codexBinary;
  try {
    bwrapBinary = await executable('bwrap');
    codexBinary = await executable('codex');
  } catch (error) {
    context.skip(error.message);
    return;
  }
  const fixture = await temporaryFixture();
  const prepared = await prepareCodexSandbox({
    runRoot: fixture.runRoot,
    codexBinary,
    bwrapBinary,
    authSource: fixture.authSource,
    canaries: fixture.canaries,
  });

  assert.deepEqual(prepared.contract.canaryOutcomes, fakeIsolationPreflight());
  assert.deepEqual(prepared.contract.mountKeys, [
    'static_codex_binary',
    'tls_certificate',
    'dns_configuration',
    'proc',
    'dev',
    'tmpfs_tmp',
    'empty_work',
    'private_codex_home',
  ]);
  assert.equal(JSON.stringify(prepared.contract).includes(fixture.root), false);
  assert.equal(JSON.stringify(prepared.contract).includes(AUTH_BYTES.trim()), false);

  const child = await prepared.spawnProcess();
  const inspection = await inspectNamespaceRoot(child.pid, {
    required: ['/bin/codex', '/etc/ssl/certs/ca-certificates.crt', '/etc/resolv.conf', '/proc', '/dev/null', '/tmp', '/work', '/codex-home/auth.json', '/codex-home/config.toml'],
    forbidden: [fixture.hostCanary, fixture.unrelatedCodexState, process.cwd(), process.env.HOME, '/bin/sh', '/usr/bin', '/usr/local/bin'],
    emptyDirectories: ['/work'],
  });
  assert.equal(inspection.requiredPathsPresent, true);
  assert.equal(inspection.forbiddenPathsHidden, true);
  assert.equal(inspection.workDirectoryEmpty, true);
  await prepared.cleanup();
});

test('auth copy is private, launcher metadata is secret-free, and cleanup preserves raw audit files', async () => {
  const fixture = await temporaryFixture();
  const recorder = fakeSpawnRecorder();
  const signals = new EventEmitter();
  const prepared = await prepareCodexSandbox({
    runRoot: fixture.runRoot,
    codexBinary: '/private/static/codex',
    bwrapBinary: '/usr/bin/bwrap',
    authSource: fixture.authSource,
    canaries: fixture.canaries,
  }, {
    spawn: recorder.spawn,
    runIsolationPreflight: async () => fakeIsolationPreflight(),
    resolveExecutable: async (file) => file,
    validateExecutable: async () => {},
    readVersion: async (file) => file.includes('bwrap') ? 'bubblewrap 0.9.0' : 'codex-cli 0.144.4',
    sha256File: async () => 'a'.repeat(64),
    signalSource: signals,
  });

  const child = await prepared.spawnProcess();
  assert.equal(recorder.calls.length, 1);
  const launch = recorder.calls[0];
  assert.equal(launch.args.join('\0').includes(AUTH_BYTES.trim()), false);
  assert.equal(JSON.stringify(launch.options).includes(AUTH_BYTES.trim()), false);
  assert.equal(JSON.stringify(prepared.contract).includes(AUTH_BYTES.trim()), false);
  assert.equal(launch.options.env.CODEX_HOME, undefined);
  assert.equal(launch.args.includes(process.env.HOME), false);

  const authPath = launch.args[launch.args.indexOf('--bind') + 1];
  const copiedAuth = join(authPath, 'auth.json');
  assert.equal((await stat(copiedAuth)).mode & 0o777, 0o600);
  assert.equal(await readFile(copiedAuth, 'utf8'), AUTH_BYTES);
  assert.equal(launch.args.includes(await realpath(process.env.HOME)), false);

  await prepared.cleanup();
  await prepared.cleanup();
  assert.ok(child.killed);
  await assert.rejects(() => access(copiedAuth));
  assert.equal(await readFile(join(fixture.rawRoot, 'keep.json'), 'utf8'), '{}\n');
});

test('cleanup runs on signal and after every terminal scenario', async () => {
  for (const scenario of ['success', 'protocol_failure', 'timeout', 'signal_interruption']) {
    const fixture = await temporaryFixture();
    const recorder = fakeSpawnRecorder();
    const signals = new EventEmitter();
    const prepared = await prepareCodexSandbox({
      runRoot: fixture.runRoot,
      codexBinary: '/private/static/codex',
      bwrapBinary: '/usr/bin/bwrap',
      authSource: fixture.authSource,
      canaries: fixture.canaries,
    }, {
      spawn: recorder.spawn,
      runIsolationPreflight: async () => fakeIsolationPreflight(),
      resolveExecutable: async (file) => file,
      validateExecutable: async () => {},
      readVersion: async () => 'pinned',
      sha256File: async () => 'b'.repeat(64),
      signalSource: signals,
    });
    const child = await prepared.spawnProcess();
    const privateHome = recorder.calls[0].args[recorder.calls[0].args.indexOf('--bind') + 1];
    if (scenario === 'signal_interruption') signals.emit('SIGTERM');
    else await prepared.cleanup();
    await waitUntilMissing(privateHome);
    assert.ok(child.killed, scenario);
    await assert.rejects(() => access(privateHome), undefined, scenario);
  }
});

test('stderr, transcript, and diagnostics reject secret and path canaries', () => {
  const canaries = {
    hostPaths: ['/private/HOST-PATH-CANARY'],
    secretValues: ['SECRET-TRANSCRIPT-CANARY', 'AUTH-BYTE-CANARY'],
  };
  assert.doesNotThrow(() => assertCanaryFree('safe normalized event', canaries, 'transcript'));
  for (const [surface, value] of [
    ['stderr', 'error SECRET-TRANSCRIPT-CANARY'],
    ['transcript', { message: '/private/HOST-PATH-CANARY' }],
    ['diagnostics', Buffer.from('AUTH-BYTE-CANARY')],
  ]) {
    assert.throws(
      () => assertCanaryFree(value, canaries, surface),
      (error) => error.classification === 'credential_or_canary_leak',
      surface,
    );
  }
});
