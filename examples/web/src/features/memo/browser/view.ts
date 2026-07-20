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
  instruction(): string;
  focusApiKey(): void;
  focusInstruction(): void;
  setStatus(message: string, tone?: StatusTone): void;
  setLoading(loading: boolean): void;
  showDiff(original: string, fixed: string): void;
  hideDiff(): void;
  bind(handlers: MemoViewHandlers): void;
}

export function createMemoView(document: Document): MemoView {
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

  return {
    memoText: () => memoEl.value,
    setMemoText: value => { memoEl.value = value; },
    apiKey: () => apiKeyEl.value,
    instruction: () => instructionEl.value,
    focusApiKey: () => apiKeyEl.focus(),
    focusInstruction: () => instructionEl.focus(),
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
    },
    bind({ fixTypos, edit, accept, reject }): void {
      fixTyposBtn.addEventListener('click', () => { void fixTypos(); });
      editBtn.addEventListener('click', () => { void edit(); });
      acceptBtn.addEventListener('click', accept);
      rejectBtn.addEventListener('click', reject);
    },
  };
}
