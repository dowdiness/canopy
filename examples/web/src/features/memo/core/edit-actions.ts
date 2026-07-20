export interface LlmResult {
  readonly ok: boolean;
  readonly actions?: readonly EditAction[];
  readonly error?: string;
}

export interface EditAction {
  readonly action: string;
  readonly original?: string;
  readonly fixed?: string;
  readonly line?: number;
  readonly old?: string;
  readonly new?: string;
  readonly text?: string;
}

export interface AppliedActions {
  readonly result: string;
  readonly warnings: readonly string[];
}

export function parseLlmResult(json: string): LlmResult {
  try {
    return JSON.parse(json) as LlmResult;
  } catch {
    return { ok: false, error: 'Failed to parse response' };
  }
}

export function applyActions(text: string, actions: readonly EditAction[]): AppliedActions {
  const warnings: string[] = [];
  for (const action of actions) {
    if (action.action === 'fix_typos' && action.fixed) {
      return { result: action.fixed, warnings };
    }
  }
  const lines = text.split('\n');
  const lineEdits = actions
    .filter(action => action.action !== 'fix_typos' && action.line !== undefined)
    .sort((a, b) => (b.line ?? 0) - (a.line ?? 0));
  for (const action of lineEdits) {
    const index = (action.line ?? 0) - 1;
    if (action.action === 'replace') {
      if (index < 0 || index >= lines.length) {
        warnings.push(`Line ${action.line} out of range (1-${lines.length})`);
        continue;
      }
      if (action.old && !lines[index].includes(action.old)) {
        warnings.push(`Line ${action.line}: "${action.old}" not found`);
        continue;
      }
      lines[index] = lines[index].replace(action.old!, action.new ?? '');
    } else if (action.action === 'insert') {
      const insertIndex = action.line ?? 0;
      if (insertIndex < 0 || insertIndex > lines.length) {
        warnings.push(`Insert line ${action.line} out of range`);
        continue;
      }
      lines.splice(insertIndex, 0, action.text ?? '');
    } else if (action.action === 'delete') {
      if (index < 0 || index >= lines.length) {
        warnings.push(`Delete line ${action.line} out of range`);
        continue;
      }
      lines.splice(index, 1);
    }
  }
  return { result: lines.join('\n'), warnings };
}
