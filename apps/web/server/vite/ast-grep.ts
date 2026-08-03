import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import type { Plugin, ViteDevServer } from 'vite';

type AstGrepJsonMatch = {
  ruleId?: string;
  range?: { byteOffset?: { start?: number; end?: number } };
};

export function astGrepPlugin(): Plugin {
  return {
    name: 'ast-grep',
    apply: 'serve',

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
    },
  };
}

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
