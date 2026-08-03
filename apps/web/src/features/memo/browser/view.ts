type StatusTone = '' | 'error' | 'success';

interface MemoViewHandlers {
  readonly fixTypos: () => Promise<void>;
  readonly edit: () => Promise<void>;
  readonly accept: () => void;
  readonly reject: () => void;
}

export interface MemoView {
  memoText(): string;
  setMemoText(value: string): void;
  apiKey(): string;
  clearApiKey(): void;
  instruction(): string;
  setInstruction(value: string): void;
  focusMemo(): void;
  focusApiKey(): void;
  focusInstruction(): void;
  setStatus(message: string, tone?: StatusTone): void;
  setLoading(loading: boolean): void;
  showDiff(original: string, fixed: string): void;
  hideDiff(): void;
  bind(handlers: MemoViewHandlers, signal: AbortSignal): void;
}

export function createMemoView(root: Document | HTMLElement): MemoView {
  function must<T extends HTMLElement>(selector: string): T {
    const element = root.querySelector<HTMLElement>(selector);
    if (element === null) throw new Error(`Missing Memo editor element ${selector}`);
    return element as T;
  }

  const memoEl = must<HTMLTextAreaElement>('#memo');
  const apiKeyEl = must<HTMLInputElement>('#api-key');
  const fixTyposBtn = must<HTMLButtonElement>('#fix-typos-btn');
  const editBtn = must<HTMLButtonElement>('#edit-btn');
  const instructionEl = must<HTMLInputElement>('#instruction');
  const statusEl = must<HTMLDivElement>('#status');
  const diffSection = must<HTMLDivElement>('#diff-section');
  const diffOriginal = must<HTMLPreElement>('#diff-original');
  const diffFixed = must<HTMLPreElement>('#diff-fixed');
  const acceptBtn = must<HTMLButtonElement>('#accept-btn');
  const rejectBtn = must<HTMLButtonElement>('#reject-btn');

  return {
    memoText: () => memoEl.value,
    setMemoText: (value) => { memoEl.value = value; },
    apiKey: () => apiKeyEl.value,
    clearApiKey: () => { apiKeyEl.value = ''; },
    instruction: () => instructionEl.value,
    setInstruction: (value) => { instructionEl.value = value; },
    focusMemo: () => memoEl.focus({ preventScroll: true }),
    focusApiKey: () => apiKeyEl.focus({ preventScroll: true }),
    focusInstruction: () => instructionEl.focus({ preventScroll: true }),
    setStatus(message: string, tone: StatusTone = ''): void {
      statusEl.textContent = message;
      statusEl.className = `status-bar ${tone}`;
    },
    setLoading(loading: boolean): void {
      fixTyposBtn.disabled = loading;
      editBtn.disabled = loading;
      if (loading) {
        statusEl.textContent = 'Calling Gemini API...';
        statusEl.className = 'status-bar ';
      }
    },
    showDiff(original: string, fixed: string): void {
      diffOriginal.textContent = original;
      diffFixed.textContent = fixed;
      diffSection.classList.add('visible');
    },
    hideDiff(): void {
      diffSection.classList.remove('visible');
      diffOriginal.textContent = '';
      diffFixed.textContent = '';
    },
    bind({ fixTypos, edit, accept, reject }, signal): void {
      fixTyposBtn.addEventListener('click', () => { void fixTypos(); }, { signal });
      editBtn.addEventListener('click', () => { void edit(); }, { signal });
      acceptBtn.addEventListener('click', accept, { signal });
      rejectBtn.addEventListener('click', reject, { signal });
    },
  };
}
