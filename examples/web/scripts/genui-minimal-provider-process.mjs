import { spawn } from 'node:child_process';
import { finished } from 'node:stream/promises';

const DEFAULT_TERMINATION_GRACE_MS = 5_000;
const DEFAULT_OUTPUT_SETTLE_MS = 5_000;

export function waitForProcess(child, {
  timeoutMs,
  kill,
  platform,
  terminateWindowsTree,
  terminationGraceMs = DEFAULT_TERMINATION_GRACE_MS,
}) {
  return new Promise(resolveResult => {
    let timedOut = false;
    let interrupted = false;
    let forceTimer;
    let settled = false;
    const finish = result => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearTimeout(forceTimer);
      process.off('SIGINT', interrupt);
      process.off('SIGTERM', interrupt);
      resolveResult(result);
    };
    const signal = name => {
      if (platform === 'win32') terminateWindowsTree(child.pid, name === 'SIGKILL');
      else {
        try { kill(-child.pid, name); } catch { child.kill(name); }
      }
    };
    const terminate = () => {
      signal('SIGTERM');
      forceTimer = setTimeout(() => {
        signal('SIGKILL');
        finish({ exitCode: null, signal: 'SIGKILL', timedOut, interrupted, error: null });
      }, terminationGraceMs);
    };
    const interrupt = () => {
      interrupted = true;
      terminate();
    };
    const timer = setTimeout(() => {
      timedOut = true;
      terminate();
    }, timeoutMs);
    process.once('SIGINT', interrupt);
    process.once('SIGTERM', interrupt);
    child.once('error', error => finish({ exitCode: null, signal: null, timedOut, interrupted, error }));
    child.once('exit', (exitCode, signalName) => {
      finish({ exitCode, signal: signalName, timedOut, interrupted, error: null });
    });
  });
}

async function settlePipedOutput(child, stream, completion, outputSettleMs) {
  let timer;
  const bounded = new Promise(resolveDone => {
    timer = setTimeout(() => {
      child.stdout.destroy();
      stream.destroy();
      resolveDone();
    }, outputSettleMs);
  });
  await Promise.race([completion.catch(() => undefined), bounded]);
  clearTimeout(timer);
}

export async function runProviderProcess(run, options, deps = {}) {
  const spawnProcess = deps.spawnProcess ?? spawn;
  const providerInvocation = deps.providerInvocation ?? { command: 'codex', prefixArgs: [] };
  const platform = deps.platform ?? process.platform;
  const kill = deps.kill ?? process.kill;
  const terminationGraceMs = deps.terminationGraceMs ?? DEFAULT_TERMINATION_GRACE_MS;
  const outputSettleMs = deps.outputSettleMs ?? DEFAULT_OUTPUT_SETTLE_MS;
  const args = [
    ...providerInvocation.prefixArgs,
    'exec',
    '--json',
    '--ephemeral',
    '--ignore-user-config',
    '--ignore-rules',
    '--skip-git-repo-check',
    '--sandbox', 'read-only',
    '--model', options.model,
    '--output-schema', run.paths.schema,
    '--output-last-message', run.paths.candidate,
    '-',
  ];
  const child = spawnProcess(providerInvocation.command, args, {
    cwd: run.paths.work,
    detached: platform !== 'win32',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const terminateWindowsTree = deps.terminateWindowsTree ?? ((pid, force) => {
    const killer = spawn('taskkill', ['/PID', String(pid), '/T', ...(force ? ['/F'] : [])], { stdio: 'ignore' });
    killer.unref();
  });
  const processResult = waitForProcess(child, {
    timeoutMs: options.timeoutMs,
    kill,
    platform,
    terminateWindowsTree,
    terminationGraceMs,
  });
  const eventsDone = finished(child.stdout.pipe(deps.eventsStream));
  let stderr = '';
  child.stderr.on('data', chunk => { stderr += chunk; });
  child.stdin.end(run.request.prompt);
  const observed = await processResult;
  await settlePipedOutput(child, deps.eventsStream, eventsDone, outputSettleMs);
  return { ...observed, stderr, invocationCount: 1 };
}
