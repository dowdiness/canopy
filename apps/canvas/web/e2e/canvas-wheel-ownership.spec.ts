import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const sourceDir = resolve(process.cwd(), 'src');

function source(name: string): string {
  return readFileSync(resolve(sourceDir, name), 'utf8');
}

test('workflow wheel ownership has no TypeScript listener or zoom bridge', () => {
  const main = source('main.ts');
  const adapter = source('graph-adapter.ts');

  expect(main).not.toContain("root.addEventListener('wheel'");
  expect(main).not.toContain('root.addEventListener("wheel"');
  expect(main).not.toContain('adapter.zoom(');
  expect(adapter).not.toContain('zoom: (');
  expect(adapter).not.toContain('source_graph_zoom');
  expect(adapter).not.toContain('zoom(');
});
