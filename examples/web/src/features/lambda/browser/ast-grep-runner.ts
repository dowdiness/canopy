export type AstGrepMatch = {
  byte_start: number;
  byte_end: number;
  pattern_id: string;
};

type AstGrepApiResponse = {
  matches?: AstGrepMatch[];
  error?: string;
};

export async function runAnalysis(
  text: string,
  options: { signal?: AbortSignal } = {},
): Promise<AstGrepMatch[]> {
  if (text.trim() === '') return [];

  const importMeta = import.meta as ImportMeta & { env?: { DEV?: boolean } };
  if (!importMeta.env?.DEV) return [];

  const response = await fetch('/api/ast-grep', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ text }),
    signal: options.signal,
  });

  if (!response.ok) {
    throw new Error(`ast-grep request failed: ${response.status} ${response.statusText}`);
  }

  const payload = (await response.json()) as AstGrepApiResponse;
  if (payload.error) {
    throw new Error(payload.error);
  }
  return payload.matches ?? [];
}
