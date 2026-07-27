const INTERNAL_BUILD_PATH = '/__waku_internal_build_static_files';
const LOOPBACK_HOSTNAMES = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);

export function isWakuBuildPreviewRequest(input) {
  try {
    const value = input instanceof Request ? input.url : String(input);
    const url = new URL(value);
    return LOOPBACK_HOSTNAMES.has(url.hostname) && url.pathname === INTERNAL_BUILD_PATH;
  } catch {
    return false;
  }
}

function isConnectionRefused(error) {
  return typeof error === 'object' &&
    error !== null &&
    typeof error.cause === 'object' &&
    error.cause !== null &&
    error.cause.code === 'ECONNREFUSED';
}

export async function fetchWakuBuildPreviewWithRetry(
  input,
  init,
  {
    attempts = 20,
    delayMs = 25,
    fetchFn = globalThis.fetch,
    wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
  } = {},
) {
  if (!Number.isSafeInteger(attempts) || attempts < 1) {
    throw new RangeError('attempts must be a positive safe integer');
  }
  if (!Number.isFinite(delayMs) || delayMs < 0) {
    throw new RangeError('delayMs must be a non-negative finite number');
  }

  const retryConnectionRefused = isWakuBuildPreviewRequest(input);
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await fetchFn(input, init);
    } catch (error) {
      if (!retryConnectionRefused || !isConnectionRefused(error) || attempt === attempts) {
        throw error;
      }
      await wait(delayMs);
    }
  }
  throw new Error('Waku preview fetch retry exhausted unexpectedly');
}

if (
  process.env.CANOPY_WAKU_BUILD_FETCH_RETRY === '1' &&
  typeof globalThis.fetch === 'function'
) {
  const nativeFetch = globalThis.fetch.bind(globalThis);
  globalThis.fetch = (input, init) => fetchWakuBuildPreviewWithRetry(
    input,
    init,
    { fetchFn: nativeFetch },
  );
}
