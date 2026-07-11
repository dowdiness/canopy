import * as crdt from '@moonbit/crdt-lambda';

// MoonBit FFI exports — cast once at module load to avoid per-call `as any`
const llm = crdt as unknown as {
  canopy_llm_fix_typos(text: string, apiKey: string): Promise<string>;
  canopy_llm_edit(text: string, instruction: string, apiKey: string): Promise<string>;
};

const memoEl = document.getElementById('memo') as HTMLTextAreaElement;
const apiKeyEl = document.getElementById('api-key') as HTMLInputElement;
const fixTyposBtn = document.getElementById('fix-typos-btn') as HTMLButtonElement;
const editBtn = document.getElementById('edit-btn') as HTMLButtonElement;
const instructionEl = document.getElementById('instruction') as HTMLInputElement;
const statusEl = document.getElementById('status') as HTMLDivElement;
const diffSection = document.getElementById('diff-section') as HTMLDivElement;
const diffOriginal = document.getElementById('diff-original') as HTMLPreElement;
const diffFixed = document.getElementById('diff-fixed') as HTMLPreElement;
const acceptBtn = document.getElementById('accept-btn') as HTMLButtonElement;
const rejectBtn = document.getElementById('reject-btn') as HTMLButtonElement;

let pendingText: string | null = null;
let lastRequestTime = 0;
const RATE_LIMIT_MS = 5000;
const MAX_INPUT_LENGTH = 5000;

function setStatus(msg: string, type: '' | 'error' | 'success' = '') {
  statusEl.textContent = msg;
  statusEl.className = `status-bar ${type}`;
}

function setLoading(loading: boolean) {
  fixTyposBtn.disabled = loading;
  editBtn.disabled = loading;
  if (loading) setStatus('Calling Gemini API...');
}

function getApiKey(): string | null {
  const key = apiKeyEl.value.trim();
  if (!key) {
    setStatus('Please enter your Gemini API key.', 'error');
    apiKeyEl.focus();
    return null;
  }
  return key;
}

function checkRateLimit(): boolean {
  const now = Date.now();
  if (now - lastRequestTime < RATE_LIMIT_MS) {
    const wait = Math.ceil((RATE_LIMIT_MS - (now - lastRequestTime)) / 1000);
    setStatus(`Rate limited. Wait ${wait}s.`, 'error');
    return false;
  }
  lastRequestTime = now;
  return true;
}

function getText(): string | null {
  const text = memoEl.value;
  if (!text.trim()) {
    setStatus('Nothing to process — textarea is empty.', 'error');
    return null;
  }
  if (text.length > MAX_INPUT_LENGTH) {
    setStatus(`Text too long (${text.length}/${MAX_INPUT_LENGTH} chars).`, 'error');
    return null;
  }
  return text;
}

function showDiff(original: string, fixed: string) {
  diffOriginal.textContent = original;
  diffFixed.textContent = fixed;
  pendingText = fixed;
  diffSection.classList.add('visible');
}

function hideDiff() {
  diffSection.classList.remove('visible');
  pendingText = null;
}

interface LlmResult {
  ok: boolean;
  actions?: EditAction[];
  error?: string;
}

interface EditAction {
  action: string;
  original?: string;
  fixed?: string;
  line?: number;
  old?: string;
  new?: string;
  text?: string;
}

function parseLlmResult(jsonStr: string): LlmResult {
  try {
    return JSON.parse(jsonStr) as LlmResult;
  } catch {
    return { ok: false, error: 'Failed to parse response' };
  }
}

function applyActions(text: string, actions: EditAction[]): { result: string; warnings: string[] } {
  const warnings: string[] = [];
  for (const action of actions) {
    if (action.action === 'fix_typos' && action.fixed) {
      return { result: action.fixed, warnings };
    }
  }
  const lines = text.split('\n');
  const lineEdits = actions
    .filter(a => a.action !== 'fix_typos' && a.line !== undefined)
    .sort((a, b) => (b.line ?? 0) - (a.line ?? 0));
  for (const action of lineEdits) {
    const idx = (action.line ?? 0) - 1;
    if (action.action === 'replace') {
      if (idx < 0 || idx >= lines.length) {
        warnings.push(`Line ${action.line} out of range (1-${lines.length})`);
        continue;
      }
      if (action.old && !lines[idx].includes(action.old)) {
        warnings.push(`Line ${action.line}: "${action.old}" not found`);
        continue;
      }
      lines[idx] = lines[idx].replace(action.old!, action.new ?? '');
    } else if (action.action === 'insert') {
      // Insert uses line number directly (not -1): "line 3" inserts AFTER line 3
      const insertIdx = action.line ?? 0;
      if (insertIdx < 0 || insertIdx > lines.length) {
        warnings.push(`Insert line ${action.line} out of range`);
        continue;
      }
      lines.splice(insertIdx, 0, action.text ?? '');
    } else if (action.action === 'delete') {
      if (idx < 0 || idx >= lines.length) {
        warnings.push(`Delete line ${action.line} out of range`);
        continue;
      }
      lines.splice(idx, 1);
    }
  }
  return { result: lines.join('\n'), warnings };
}

async function callLlm(fetchFn: () => Promise<string>, originalText: string) {
  setLoading(true);
  try {
    const resultJson: string = await fetchFn();
    const result = parseLlmResult(resultJson);
    if (!result.ok) {
      setStatus(`Error: ${result.error}`, 'error');
      return;
    }
    if (!result.actions || result.actions.length === 0) {
      setStatus('No changes suggested.', 'success');
      return;
    }
    const { result: fixed, warnings } = applyActions(originalText, result.actions);
    if (fixed === originalText) {
      setStatus('No changes detected.', 'success');
    } else {
      showDiff(originalText, fixed);
      const msg = warnings.length > 0
        ? `Review changes. Warnings: ${warnings.join('; ')}`
        : 'Review the suggested changes below.';
      setStatus(msg, warnings.length > 0 ? 'error' : 'success');
    }
  } catch (err) {
    setStatus(`Unexpected error: ${err instanceof Error ? err.message : err}`, 'error');
  } finally {
    setLoading(false);
  }
}

fixTyposBtn.addEventListener('click', async () => {
  const apiKey = getApiKey();
  if (!apiKey) return;
  const text = getText();
  if (!text) return;
  if (!checkRateLimit()) return;
  await callLlm(() => llm.canopy_llm_fix_typos(text, apiKey), text);
});

editBtn.addEventListener('click', async () => {
  const apiKey = getApiKey();
  if (!apiKey) return;
  const text = getText();
  if (!text) return;
  const instruction = instructionEl.value.trim();
  if (!instruction) {
    setStatus('Please enter an edit instruction.', 'error');
    instructionEl.focus();
    return;
  }
  if (!checkRateLimit()) return;
  await callLlm(() => llm.canopy_llm_edit(text, instruction, apiKey), text);
});

acceptBtn.addEventListener('click', () => {
  if (pendingText !== null) {
    memoEl.value = pendingText;
    setStatus('Changes applied.', 'success');
  }
  hideDiff();
});

rejectBtn.addEventListener('click', () => {
  setStatus('Changes rejected.');
  hideDiff();
});

setStatus('Ready. Enter your API key and start typing.');
