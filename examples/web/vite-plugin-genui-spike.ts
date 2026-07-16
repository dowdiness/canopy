import type { Plugin } from 'vite';

import orders from './src/fixtures/orders.json';
import { GENUI_SPIKE_CASE } from './src/genui-spike-case.js';
import { GENUI_RECIPE_SCHEMA, parseGenUiRecipe } from './src/genui-spike-recipe.js';

const OLLAMA_URL = 'http://127.0.0.1:11434/api/generate';
const DEFAULT_MODEL = 'gemma4:e2b';
const REQUEST_LIMIT_BYTES = 1024;
const REQUEST_TIMEOUT_MS = 120_000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

async function readRequestBody(request: AsyncIterable<Uint8Array>): Promise<unknown> {
  const chunks: Uint8Array[] = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.byteLength;
    if (size > REQUEST_LIMIT_BYTES) {
      throw new Error('Request body exceeds the 1 KiB prototype limit.');
    }
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function sendJson(response: { statusCode: number; setHeader(name: string, value: string): void; end(body: string): void }, status: number, body: unknown) {
  response.statusCode = status;
  response.setHeader('content-type', 'application/json; charset=utf-8');
  response.setHeader('cache-control', 'no-store');
  response.end(JSON.stringify(body));
}

function buildPrompt() {
  return [
    'You design one focused read-only view for a data task.',
    `Question: ${GENUI_SPIKE_CASE.question}`,
    `Rows: ${JSON.stringify(orders)}`,
    'Return only a recipe matching the supplied JSON schema.',
    'Choose the status filter and columns that help answer the question.',
    'Do not answer the question in the title or summary label.',
    'Do not emit HTML, JavaScript, Markdown, explanations, or extra properties.',
  ].join('\n');
}

function readMetric(value: unknown) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

export function genUiSpikePlugin(): Plugin {
  return {
    name: 'genui-spike-ollama',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use('/api/genui-spike', async (request, response) => {
        if (request.method !== 'POST') {
          sendJson(response, 405, { error: 'Only POST is supported.' });
          return;
        }

        try {
          const body = await readRequestBody(request);
          if (!isRecord(body) || Object.keys(body).length !== 1 || body.caseId !== GENUI_SPIKE_CASE.id) {
            sendJson(response, 400, { error: 'Unknown or malformed development case request.' });
            return;
          }

          const model = process.env.GENUI_OLLAMA_MODEL ?? DEFAULT_MODEL;
          const startedAt = performance.now();
          const providerResponse = await fetch(OLLAMA_URL, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
              model,
              prompt: buildPrompt(),
              stream: false,
              format: GENUI_RECIPE_SCHEMA,
              options: { temperature: 0, num_predict: 256 },
              keep_alive: '5m',
            }),
            signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
          });

          if (!providerResponse.ok) {
            sendJson(response, 502, { error: `Ollama returned HTTP ${providerResponse.status}.` });
            return;
          }

          const providerBody: unknown = await providerResponse.json();
          if (!isRecord(providerBody) || typeof providerBody.response !== 'string') {
            sendJson(response, 502, { error: 'Ollama returned an invalid response envelope.' });
            return;
          }

          let untrustedRecipe: unknown;
          try {
            untrustedRecipe = JSON.parse(providerBody.response);
          } catch {
            sendJson(response, 502, { error: 'Ollama returned non-JSON recipe content.' });
            return;
          }

          const parsedRecipe = parseGenUiRecipe(untrustedRecipe);
          if (!parsedRecipe.ok) {
            sendJson(response, 502, { error: `Recipe rejected: ${parsedRecipe.error}` });
            return;
          }

          sendJson(response, 200, {
            recipe: parsedRecipe.value,
            telemetry: {
              model: typeof providerBody.model === 'string' ? providerBody.model : model,
              elapsedMs: Math.round(performance.now() - startedAt),
              providerDurationMs: readMetric(providerBody.total_duration) === null
                ? null
                : Math.round(readMetric(providerBody.total_duration)! / 1_000_000),
              promptTokens: readMetric(providerBody.prompt_eval_count),
              outputTokens: readMetric(providerBody.eval_count),
            },
          });
        } catch (error) {
          const message = error instanceof Error ? error.message : String(error);
          const timedOut = error instanceof Error && (error.name === 'TimeoutError' || error.name === 'AbortError');
          sendJson(response, timedOut ? 504 : 500, {
            error: timedOut ? 'Local model request timed out.' : `Prototype request failed: ${message}`,
          });
        }
      });
    },
  };
}
