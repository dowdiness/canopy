import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const sourceDir = resolve(process.cwd(), 'src');

function source(name: string): string {
  return readFileSync(resolve(sourceDir, name), 'utf8');
}

test('workflow edge selection authority is not held by TypeScript', () => {
  const main = source('main.ts');
  const adapter = source('graph-adapter.ts');

  expect(main).not.toContain('selectedEdge');
  expect(main).not.toContain('EdgeSelection');
  expect(main).not.toContain('edgeSelectionFromEdge');
  expect(main).not.toContain('edgeMatchesSelection');
  expect(main).not.toContain('deleteSelectedEdge');
  expect(main).not.toContain('deleteSelectedNodes');
  expect(main).not.toContain("root.addEventListener('click'");
  expect(main).toContain('adapter.deleteSelection()');
  expect(main).toContain('adapter.selectEdge(');
  expect(adapter).toContain('select_edge');
  expect(adapter).toContain('delete_selection');
});
