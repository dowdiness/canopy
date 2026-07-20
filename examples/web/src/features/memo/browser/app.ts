import * as crdt from '@moonbit/crdt-lambda';
import { applyActions, parseLlmResult } from '../core/edit-actions';
import type { MemoView } from './view';

const llm = crdt as unknown as {
  canopy_llm_fix_typos(text: string, apiKey: string): Promise<string>;
  canopy_llm_edit(text: string, instruction: string, apiKey: string): Promise<string>;
};

const RATE_LIMIT_MS = 5000;
const MAX_INPUT_LENGTH = 5000;

export function createMemoApp(view: MemoView) {
  let pendingText: string | null = null;
  let lastRequestTime = 0;

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
    pendingText = null;
  }

  async function callLlm(fetchResult: () => Promise<string>, originalText: string): Promise<void> {
    view.setLoading(true);
    try {
      const result = parseLlmResult(await fetchResult());
      if (!result.ok) {
        view.setStatus(`Error: ${result.error}`, 'error');
        return;
      }
      if (!result.actions || result.actions.length === 0) {
        view.setStatus('No changes suggested.', 'success');
        return;
      }
      const { result: fixed, warnings } = applyActions(originalText, result.actions);
      if (fixed === originalText) {
        view.setStatus('No changes detected.', 'success');
      } else {
        pendingText = fixed;
        view.showDiff(originalText, fixed);
        view.setStatus(
          warnings.length > 0
            ? `Review changes. Warnings: ${warnings.join('; ')}`
            : 'Review the suggested changes below.',
          warnings.length > 0 ? 'error' : 'success',
        );
      }
    } catch (error) {
      view.setStatus(`Unexpected error: ${error instanceof Error ? error.message : error}`, 'error');
    } finally {
      view.setLoading(false);
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

  return {
    mount(): void {
      view.bind({
        fixTypos,
        edit,
        accept(): void {
          if (pendingText !== null) {
            view.setMemoText(pendingText);
            view.setStatus('Changes applied.', 'success');
          }
          hideDiff();
        },
        reject(): void {
          view.setStatus('Changes rejected.');
          hideDiff();
        },
      });
      view.setStatus('Ready. Enter your API key and start typing.');
    },
  };
}
