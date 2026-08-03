'use client';

import type { MountedImperativeSession } from '../../../shared/route-lifecycle/browser/imperative-session';
import { applyActions, parseLlmResult } from '../core/edit-actions';
import { createMemoView } from './view';

export interface MemoRuntime {
  canopy_llm_fix_typos(text: string, apiKey: string): Promise<string>;
  canopy_llm_edit(text: string, instruction: string, apiKey: string): Promise<string>;
}

export interface MemoProposal {
  readonly original: string;
  readonly fixed: string;
}

export interface MemoSnapshot {
  readonly draft: string;
  readonly instruction: string;
  readonly proposal: MemoProposal | null;
}

const RATE_LIMIT_MS = 5000;
const MAX_INPUT_LENGTH = 5000;

export function mountMemoApp(
  root: Document | HTMLElement = globalThis.document,
  restoredSnapshot: unknown,
  llm: MemoRuntime,
): MountedImperativeSession {
  const document = root instanceof Document ? root : root.ownerDocument;
  const window = document.defaultView ?? globalThis.window;
  const surfaceCandidate = root.querySelector<HTMLElement>('[data-memo-ready]');
  if (surfaceCandidate === null) throw new Error('Missing Memo editor surface');
  const surfaceEl: HTMLElement = surfaceCandidate;
  const view = createMemoView(root);
  const listenerAbort = new window.AbortController();
  const restored = normalizeMemoSnapshot(restoredSnapshot);

  let disposed = false;
  let proposal = restored.proposal;
  let lastRequestTime = 0;
  let requestGeneration = 0;

  function dispose(): void {
    if (disposed) return;
    disposed = true;
    requestGeneration += 1;
    listenerAbort.abort();
    view.clearApiKey();
    surfaceEl.inert = true;
    surfaceEl.dataset.memoReady = 'false';
  }

  function getApiKey(): string | null {
    const key = view.apiKey().trim();
    if (!key) {
      view.setStatus('Please enter your Gemini API key.', 'error');
      view.focusApiKey();
      return null;
    }
    return key;
  }

  function getText(): string | null {
    const text = view.memoText();
    if (!text.trim()) {
      view.setStatus('Nothing to process — textarea is empty.', 'error');
      return null;
    }
    if (text.length > MAX_INPUT_LENGTH) {
      view.setStatus(`Text too long (${text.length}/${MAX_INPUT_LENGTH} chars).`, 'error');
      return null;
    }
    return text;
  }

  function checkRateLimit(): boolean {
    const now = Date.now();
    if (now - lastRequestTime < RATE_LIMIT_MS) {
      const wait = Math.ceil((RATE_LIMIT_MS - (now - lastRequestTime)) / 1000);
      view.setStatus(`Rate limited. Wait ${wait}s.`, 'error');
      return false;
    }
    lastRequestTime = now;
    return true;
  }

  function hideDiff(): void {
    view.hideDiff();
    proposal = null;
  }

  async function callLlm(
    fetchResult: () => Promise<string>,
    originalText: string,
  ): Promise<void> {
    const generation = ++requestGeneration;
    view.setLoading(true);
    try {
      const parsed = parseLlmResult(await fetchResult());
      if (disposed || generation !== requestGeneration) return;
      if (!parsed.ok) {
        view.setStatus(`Error: ${parsed.error}`, 'error');
        return;
      }
      if (!parsed.actions || parsed.actions.length === 0) {
        view.setStatus('No changes suggested.', 'success');
        return;
      }
      const { result: fixed, warnings } = applyActions(originalText, parsed.actions);
      if (fixed === originalText) {
        view.setStatus('No changes detected.', 'success');
        return;
      }
      proposal = { original: originalText, fixed };
      view.showDiff(originalText, fixed);
      view.setStatus(
        warnings.length > 0
          ? `Review changes. Warnings: ${warnings.join('; ')}`
          : 'Review the suggested changes below.',
        warnings.length > 0 ? 'error' : 'success',
      );
    } catch (error) {
      if (disposed || generation !== requestGeneration) return;
      view.setStatus(
        `Unexpected error: ${error instanceof Error ? error.message : error}`,
        'error',
      );
    } finally {
      if (!disposed && generation === requestGeneration) view.setLoading(false);
    }
  }

  async function fixTypos(): Promise<void> {
    const apiKey = getApiKey();
    if (!apiKey) return;
    const text = getText();
    if (!text || !checkRateLimit()) return;
    await callLlm(() => llm.canopy_llm_fix_typos(text, apiKey), text);
  }

  async function edit(): Promise<void> {
    const apiKey = getApiKey();
    if (!apiKey) return;
    const text = getText();
    if (!text) return;
    const instruction = view.instruction().trim();
    if (!instruction) {
      view.setStatus('Please enter an edit instruction.', 'error');
      view.focusInstruction();
      return;
    }
    if (!checkRateLimit()) return;
    await callLlm(() => llm.canopy_llm_edit(text, instruction, apiKey), text);
  }

  try {
    view.setMemoText(restored.draft);
    view.setInstruction(restored.instruction);
    if (proposal !== null) view.showDiff(proposal.original, proposal.fixed);
    view.bind({
      fixTypos,
      edit,
      accept(): void {
        if (proposal !== null) {
          view.setMemoText(proposal.fixed);
          view.setStatus('Changes applied.', 'success');
        }
        hideDiff();
      },
      reject(): void {
        view.setStatus('Changes rejected.');
        hideDiff();
      },
    }, listenerAbort.signal);
    view.setStatus('Ready. Enter your API key and start typing.');
    surfaceEl.inert = false;
    surfaceEl.dataset.memoReady = 'true';

    return {
      snapshot: (): MemoSnapshot => ({
        draft: view.memoText(),
        instruction: view.instruction(),
        proposal: proposal === null ? null : { ...proposal },
      }),
      restoreFocus(token: string): boolean {
        if (disposed) return false;
        if (token === 'memo') view.focusMemo();
        else if (token === 'instruction') view.focusInstruction();
        else return false;
        return document.activeElement?.getAttribute('data-route-focus') === token;
      },
      dispose,
    };
  } catch (error) {
    dispose();
    throw error;
  }
}

export function normalizeMemoSnapshot(value: unknown): MemoSnapshot {
  if (typeof value !== 'object' || value === null) {
    return { draft: '', instruction: '', proposal: null };
  }
  const snapshot = value as Record<string, unknown>;
  const candidate = snapshot.proposal;
  const proposal = typeof candidate === 'object' && candidate !== null &&
    typeof (candidate as Record<string, unknown>).original === 'string' &&
    typeof (candidate as Record<string, unknown>).fixed === 'string'
    ? {
        original: (candidate as Record<string, string>).original,
        fixed: (candidate as Record<string, string>).fixed,
      }
    : null;
  return {
    draft: typeof snapshot.draft === 'string' ? snapshot.draft : '',
    instruction: typeof snapshot.instruction === 'string' ? snapshot.instruction : '',
    proposal,
  };
}
