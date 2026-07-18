import { spawn } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { finished, pipeline } from 'node:stream/promises';

const DEFAULT_TERMINATION_GRACE_MS = 5_000;
const DEFAULT_OUTPUT_SETTLE_MS = 5_000;
const STDERR_RETAIN_BYTES = 16_384;

function waitWithin(promise, timeoutMs) {
  return new Promise(resolve => {
    let settled = false;
    const finish = value => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(value);
    };
    const timer = setTimeout(() => finish(false), timeoutMs);
    Promise.resolve(promise).then(() => finish(true), () => finish(false));
  });
}

function terminateWindowsProcessTree(pid, force, timeoutMs) {
  return new Promise(resolve => {
    const killer = spawn('taskkill', ['/PID', String(pid), '/T', ...(force ? ['/F'] : [])], { stdio: 'ignore' });
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve();
    };
    const timer = setTimeout(() => {
      killer.kill('SIGKILL');
      killer.unref();
      finish();
    }, timeoutMs);
    killer.once('error', finish);
    killer.once('exit', finish);
  });
}

export function waitForProcess(child, {
  timeoutMs,
  kill,
  platform,
  terminateWindowsTree,
  terminationGraceMs = DEFAULT_TERMINATION_GRACE_MS,
  forceTerminationMs = DEFAULT_TERMINATION_GRACE_MS,
}) {
  return new Promise(resolveResult => {
    let terminationReason = null;
    let childOutcome = null;
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
      if (platform === 'win32') {
        return Promise.resolve()
          .then(() => terminateWindowsTree(child.pid, name === 'SIGKILL'))
          .catch(() => undefined);
      }
      try {
        kill(-child.pid, name);
      } catch {
        try { child.kill(name); } catch {}
      }
      return Promise.resolve();
    };
    const terminate = reason => {
      if (terminationReason !== null) return;
      terminationReason = reason;
      forceTimer = setTimeout(() => {
        void (async () => {
          await waitWithin(signal('SIGKILL'), forceTerminationMs);
          finish({
            exitCode: null,
            signal: 'SIGKILL',
            timedOut: terminationReason === 'timeout',
            interrupted: terminationReason === 'interrupt',
            error: childOutcome?.error ?? null,
          });
        })();
      }, terminationGraceMs);
      void signal('SIGTERM');
    };
    const interrupt = () => terminate('interrupt');
    const timer = setTimeout(() => terminate('timeout'), timeoutMs);
    process.once('SIGINT', interrupt);
    process.once('SIGTERM', interrupt);
    child.once('error', error => {
      childOutcome = { exitCode: null, signal: null, error };
      if (terminationReason === null) {
        finish({ ...childOutcome, timedOut: false, interrupted: false });
      }
    });
    child.once('exit', (exitCode, signalName) => {
      childOutcome = { exitCode, signal: signalName, error: null };
      if (terminationReason === null) {
        finish({ ...childOutcome, timedOut: false, interrupted: false });
      }
    });
  });
}

function completeUtf8PrefixLength(bytes) {
  if (bytes.length === 0) return 0;
  let lead = bytes.length - 1;
  while (lead >= 0 && (bytes[lead] & 0xc0) === 0x80) lead -= 1;
  if (lead < 0) return 0;
  const first = bytes[lead];
  const expected = first <= 0x7f
    ? 1
    : first >= 0xc2 && first <= 0xdf
      ? 2
      : first >= 0xe0 && first <= 0xef
        ? 3
        : first >= 0xf0 && first <= 0xf4
          ? 4
          : 1;
  return bytes.length - lead < expected ? lead : bytes.length;
}

function decodeUtf8WithinByteCap(chunks, retainedBytes, maxBytes) {
  const text = Buffer.concat(chunks, retainedBytes).toString('utf8');
  const encoded = Buffer.from(text);
  if (encoded.length <= maxBytes) return text;
  const capped = encoded.subarray(0, maxBytes);
  return capped.subarray(0, completeUtf8PrefixLength(capped)).toString('utf8');
}

function collectBoundedStderr(stream, maxBytes, ignoreError) {
  const chunks = [];
  let retainedBytes = 0;
  let truncated = false;
  let streamError = null;
  const onData = chunk => {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    const remaining = maxBytes - retainedBytes;
    if (remaining > 0) {
      const retained = bytes.subarray(0, remaining);
      chunks.push(retained);
      retainedBytes += retained.length;
    }
    if (bytes.length > remaining) truncated = true;
  };
  stream.on('data', onData);
  const completion = finished(stream).catch(error => {
    if (!ignoreError()) streamError = error;
  });
  return {
    completion,
    finish(incomplete) {
      stream.off('data', onData);
      const stderr = decodeUtf8WithinByteCap(chunks, retainedBytes, maxBytes);
      return { stderr, stderrTruncated: truncated || incomplete, streamError };
    },
  };
}

async function settlePipedOutput(streams, completions, outputSettleMs, onTimeout) {
  let timer;
  let timedOut = false;
  const bounded = new Promise(resolveDone => {
    timer = setTimeout(() => {
      timedOut = true;
      onTimeout();
      for (const stream of streams) stream.destroy();
      resolveDone();
    }, outputSettleMs);
  });
  await Promise.race([Promise.all(completions), bounded]);
  clearTimeout(timer);
  return timedOut;
}

export async function runProviderProcess(run, options, deps = {}) {
  const spawnProcess = deps.spawnProcess ?? spawn;
  const providerInvocation = deps.providerInvocation ?? { command: 'codex', prefixArgs: [] };
  const platform = deps.platform ?? process.platform;
  const kill = deps.kill ?? process.kill;
  const terminationGraceMs = deps.terminationGraceMs ?? DEFAULT_TERMINATION_GRACE_MS;
  const outputSettleMs = deps.outputSettleMs ?? DEFAULT_OUTPUT_SETTLE_MS;
  const monotonicNow = deps.monotonicNow ?? (() => performance.now());
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
  const startedAt = monotonicNow();
  const child = spawnProcess(providerInvocation.command, args, {
    cwd: run.paths.work,
    detached: platform !== 'win32',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const terminateWindowsTree = deps.terminateWindowsTree ?? ((pid, force) => (
    terminateWindowsProcessTree(pid, force, terminationGraceMs)
  ));
  const processResult = waitForProcess(child, {
    timeoutMs: options.timeoutMs,
    kill,
    platform,
    terminateWindowsTree,
    terminationGraceMs,
    forceTerminationMs: deps.forceTerminationMs ?? DEFAULT_TERMINATION_GRACE_MS,
  });
  let suppressOutputErrors = false;
  let eventsError = null;
  const eventsDone = pipeline(child.stdout, deps.eventsStream).catch(error => {
    if (!suppressOutputErrors) eventsError = error;
  });
  const stderrOutput = collectBoundedStderr(
    child.stderr,
    STDERR_RETAIN_BYTES,
    () => suppressOutputErrors,
  );
  let stdinError = null;
  const stdinDone = finished(child.stdin, { readable: false }).catch(error => { stdinError ??= error; });
  try {
    child.stdin.end(run.request.prompt);
  } catch (error) {
    stdinError = error;
    child.stdin.destroy();
  }
  const observed = await processResult;
  const outputSettlementTimedOut = await settlePipedOutput(
    [child.stdin, child.stdout, child.stderr, deps.eventsStream],
    [stdinDone, eventsDone, stderrOutput.completion],
    outputSettleMs,
    () => { suppressOutputErrors = true; },
  );
  const { streamError: stderrError, ...stderrResult } = stderrOutput.finish(outputSettlementTimedOut);
  if (eventsError) throw eventsError;
  if (stderrError) throw stderrError;
  const elapsed = monotonicNow() - startedAt;
  const providerDurationMs = Number.isFinite(elapsed) ? Math.max(0, Math.round(elapsed)) : 0;
  const error = observed.error ?? (observed.exitCode === 0 ? stdinError : null);
  return {
    ...observed,
    ...stderrResult,
    error,
    outputSettlementTimedOut,
    providerDurationMs,
    invocationCount: 1,
  };
}
