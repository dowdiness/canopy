import { expect, type Locator, type Page, test } from '@playwright/test';

type Point = {
  x: number;
  y: number;
};

function edgePaths(page: Page): Locator {
  return page.locator('#edges path.edge');
}

function pendingEdgePaths(page: Page): Locator {
  return page.locator('#edges path.edge-pending');
}

function inputHandle(page: Page, nodeId: number): Locator {
  return page.locator(`.handle.input[data-node-id="${nodeId}"]`);
}

function outputHandle(page: Page, nodeId: number): Locator {
  return page.locator(`.handle.output[data-node-id="${nodeId}"]`);
}

async function center(locator: Locator, label: string): Promise<Point> {
  const box = await locator.boundingBox();
  if (!box) {
    throw new Error(`${label} is not visible`);
  }
  return {
    x: box.x + box.width / 2,
    y: box.y + box.height / 2,
  };
}

async function canvasBackgroundPoint(page: Page): Promise<Point> {
  const box = await page.locator('#canvas-root').boundingBox();
  if (!box) {
    throw new Error('canvas root is not visible');
  }
  return {
    x: box.x + 20,
    y: box.y + 20,
  };
}

async function dragBetween(page: Page, from: Locator, to: Locator): Promise<void> {
  const start = await center(from, 'source handle');
  const end = await center(to, 'target handle');
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(end.x, end.y, { steps: 8 });
}

async function commitDrag(page: Page, from: Locator, to: Locator): Promise<void> {
  await dragBetween(page, from, to);
  await expect(pendingEdgePaths(page)).toHaveCount(1);
  await page.mouse.up();
  await expect(pendingEdgePaths(page)).toHaveCount(0);
}

async function worldTransform(page: Page): Promise<string> {
  return page.locator('#world').evaluate((el) => (el as HTMLElement).style.transform);
}

test('canvas handles create edges and reject invalid gestures', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') {
      runtimeErrors.push(message.text());
    }
  });

  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'platform', {
      value: 'MacIntel',
      configurable: true,
    });
  });
  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(edgePaths(page)).toHaveCount(3);
  await expect(pendingEdgePaths(page)).toHaveCount(0);
  expect(runtimeErrors).toEqual([]);

  const source = outputHandle(page, 1);

  const ctrlClickStart = await center(source, 'node 1 output handle');
  await page.keyboard.down('Control');
  await page.mouse.move(ctrlClickStart.x, ctrlClickStart.y);
  await page.mouse.down();
  await page.mouse.up();
  await page.keyboard.up('Control');
  await expect(pendingEdgePaths(page)).toHaveCount(0);
  await expect(edgePaths(page)).toHaveCount(3);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');

  const cancelStart = await center(source, 'node 1 output handle');
  const cancelTarget = await canvasBackgroundPoint(page);
  await page.mouse.move(cancelStart.x, cancelStart.y);
  await page.mouse.down();
  await page.mouse.move(cancelTarget.x, cancelTarget.y, { steps: 4 });
  await expect(pendingEdgePaths(page)).toHaveCount(1);
  await page.mouse.up();
  await expect(pendingEdgePaths(page)).toHaveCount(0);
  await expect(edgePaths(page)).toHaveCount(3);

  await commitDrag(page, outputHandle(page, 2), inputHandle(page, 5));
  await expect(edgePaths(page)).toHaveCount(4);

  await commitDrag(page, outputHandle(page, 2), inputHandle(page, 5));
  await expect(edgePaths(page)).toHaveCount(4);

  await commitDrag(page, outputHandle(page, 2), inputHandle(page, 2));
  await expect(edgePaths(page)).toHaveCount(4);

  const transformBeforeInputDrag = await worldTransform(page);
  const inputStart = await center(inputHandle(page, 3), 'node 3 input handle');
  await page.mouse.move(inputStart.x, inputStart.y);
  await page.mouse.down();
  await page.mouse.move(inputStart.x - 20, inputStart.y + 50, { steps: 4 });
  await expect(pendingEdgePaths(page)).toHaveCount(0);
  await expect(page.locator('#canvas-root')).not.toHaveClass(/panning/);
  expect(await worldTransform(page)).toBe(transformBeforeInputDrag);
  await page.mouse.up();

  await expect(edgePaths(page)).toHaveCount(4);
  await expect(pendingEdgePaths(page)).toHaveCount(0);
  expect(runtimeErrors).toEqual([]);
});

test('selected canvas nodes delete with incident edges from the keyboard', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') {
      runtimeErrors.push(message.text());
    }
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(edgePaths(page)).toHaveCount(3);

  const node = page.locator('.canvas-node[data-node-id="2"]');
  await node.click();
  await expect(node).toHaveClass(/(?:^|\s)selected(?:\s|$)/);

  await page.keyboard.press('Delete');
  await expect(page.locator('.canvas-node')).toHaveCount(5);
  await expect(page.locator('.canvas-node[data-node-id="2"]')).toHaveCount(0);
  await expect(edgePaths(page)).toHaveCount(1);
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('keyboard deletion ignores text-input focus', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') {
      runtimeErrors.push(message.text());
    }
  });

  await page.goto('/');
  await page.locator('.canvas-node[data-node-id="2"]').click();
  await page.locator('#node-search').focus();
  await page.keyboard.press('Backspace');

  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(edgePaths(page)).toHaveCount(3);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('input handles preview compatibility during a connection drag', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') {
      runtimeErrors.push(message.text());
    }
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);

  // Node 2 (HTTP request) emits a single JSON output. Start a drag from it and
  // hold it open so input handles render their compatibility preview.
  const source = outputHandle(page, 2);
  const start = await center(source, 'node 2 output handle');
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(start.x + 40, start.y + 40, { steps: 6 });
  await expect(pendingEdgePaths(page)).toHaveCount(1);

  // JSON output → JSON input (Loop "items") is compatible.
  await expect(inputHandle(page, 5)).toHaveClass(/(?:^|\s)compatible-target(?:\s|$)/);
  // JSON output → Flow input (Parallel "in") is incompatible.
  await expect(inputHandle(page, 6)).toHaveClass(/(?:^|\s)incompatible-target(?:\s|$)/);
  // The source node's own input is a self-loop and must read incompatible.
  await expect(inputHandle(page, 2)).toHaveClass(/(?:^|\s)incompatible-target(?:\s|$)/);

  await page.mouse.up();

  // Once the drag ends, the preview classes are cleared.
  await expect(inputHandle(page, 5)).not.toHaveClass(/compatible-target/);
  await expect(inputHandle(page, 6)).not.toHaveClass(/incompatible-target/);
  expect(runtimeErrors).toEqual([]);
});
