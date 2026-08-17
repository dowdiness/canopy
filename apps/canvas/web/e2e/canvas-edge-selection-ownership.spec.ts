import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const sourceDir = resolve(process.cwd(), 'src');

function source(name: string): string {
  return readFileSync(resolve(sourceDir, name), 'utf8');
}

test('workflow edge and context-menu authority is not held by TypeScript', () => {
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
  expect(main).not.toContain('contextPoint');
  expect(main).not.toContain('contextEdge');
  expect(main).not.toContain('root.addEventListener(\'contextmenu\'');
  expect(main).not.toContain('canopy-canvas-context-menu-show');
  expect(main).not.toContain('canopy-canvas-context-menu-hide');
  expect(main).toContain('mount_canvas_context_menu');
  expect(main).toContain('edge.path_d');
  expect(main).not.toContain('function portOffset');
  expect(main).not.toContain('function inputAnchor');
  expect(main).not.toContain('function outputAnchor');
  expect(main).not.toContain('function bezierPath');
  expect(main).not.toContain('function edgeTitle');
  expect(main).toContain('path_d');
  expect(main).toContain('aria_label');
  expect(main).toContain('pendingPath');
  expect(main).not.toContain('outputAnchor(');
  expect(main).not.toContain('inputAnchor(');
  expect(main).not.toContain('nodesById');
  expect(main).not.toContain('edge.source_port');
  expect(main).not.toContain('edge.target_port');
  expect(main).toContain('get_workflow_node_catalog');
  expect(adapter).not.toContain('select_edge');
  expect(adapter).not.toContain('disconnect_ports');
  expect(adapter).toContain('delete_selection');
});
