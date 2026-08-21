import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const sourceDir = resolve(process.cwd(), 'src');

function source(name: string): string {
  return readFileSync(resolve(sourceDir, name), 'utf8');
}

function indexHtml(): string {
  return readFileSync(resolve(process.cwd(), 'index.html'), 'utf8');
}

test('workflow render and context-menu authority is not held by TypeScript', () => {
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
  expect(main).toContain('adapter.publishRenderState()');
  expect(main).toContain('mount_canvas_render_layer');
  expect(main).not.toContain('nodeDivs');
  expect(main).not.toContain('renderPortHandles');
  expect(main).not.toContain('inputCompatibilityByTarget');
  expect(main).not.toContain('world.style.transform');
  expect(main).not.toContain('className = `canvas-node workflow-node`');
  expect(main).not.toContain('SVG_NS');
  expect(main).not.toContain('edgesSvg');
  expect(main).not.toContain('edgePaths');
  expect(main).not.toContain('pendingPath');
  expect(main).not.toContain('createElementNS');
  expect(main).not.toContain('edge.path_d');
  expect(main).not.toContain('outputAnchor(');
  expect(main).not.toContain('inputAnchor(');
  expect(main).not.toContain('nodesById');
  expect(main).not.toContain('edge.source_port');
  expect(main).not.toContain('edge.target_port');
  expect(indexHtml()).toContain('id="canvas-render-layer"');
  expect(indexHtml()).not.toContain('id="canvas-edge-layer"');
  expect(indexHtml()).not.toContain('<svg id="edges"');
  expect(main).toContain('get_workflow_node_catalog');
  expect(adapter).not.toContain('select_edge');
  expect(adapter).not.toContain('disconnect_ports');
  expect(adapter).not.toContain('EdgeData');
  expect(adapter).not.toContain('path_d');
  expect(adapter).toContain('publish_render_state');
  expect(adapter).toContain('delete_selection');
});
