import { expect, type Locator, type Page, test } from '@playwright/test';

const SAMPLE_SOURCE = 'osc = sine(freq: 440Hz)\nmeter = scope()';

const INVALID_SOURCE_CASES = [
  { name: 'parser-blocked', source: 'osc = sine(freq: )' },
  { name: 'projection-blocked', source: 'osc = sine(input: missing)' },
] as const;

type Point = {
  x: number;
  y: number;
};

function inputHandle(page: Page, nodeId: number): Locator {
  return page.locator(`.handle.input[data-node-id="${nodeId}"]`);
}

function outputHandle(page: Page, nodeId: number): Locator {
  return page.locator(`.handle.output[data-node-id="${nodeId}"]`);
}

function edgePaths(page: Page): Locator {
  return page.locator('#edges path.edge');
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

async function dragBetween(page: Page, from: Locator, to: Locator): Promise<void> {
  const start = await center(from, 'source handle');
  const end = await center(to, 'target handle');
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(end.x, end.y, { steps: 8 });
}

async function edgeMidpoint(edge: Locator): Promise<Point> {
  return edge.evaluate((path) => {
    const svgPath = path as SVGPathElement;
    const point = svgPath.getPointAtLength(svgPath.getTotalLength() / 2);
    const matrix = svgPath.getScreenCTM();
    if (!matrix) throw new Error('edge path has no screen transform');
    return {
      x: point.x * matrix.a + point.y * matrix.c + matrix.e,
      y: point.x * matrix.b + point.y * matrix.d + matrix.f,
    };
  });
}

async function clickEdge(page: Page, index: number): Promise<void> {
  const point = await edgeMidpoint(edgePaths(page).nth(index));
  await page.mouse.click(point.x, point.y);
}

async function dragBy(page: Page, locator: Locator, dx: number, dy: number): Promise<void> {
  const start = await center(locator, 'draggable node');
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(start.x + dx, start.y + dy, { steps: 8 });
  await page.mouse.up();
}

function collectRuntimeErrors(page: Page): string[] {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') {
      runtimeErrors.push(message.text());
    }
  });
  return runtimeErrors;
}

test('source-backed node drag updates local layout without mutating source', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expect(page.locator('#source-editor')).toHaveValue(SAMPLE_SOURCE);

  const node = page.locator('.canvas-node[data-node-id="1"]');
  const before = await center(node, 'source-backed node');
  await dragBy(page, node.locator('.node-title'), 82, 36);
  const after = await center(node, 'dragged source-backed node');

  expect(after.x - before.x).toBeGreaterThan(60);
  expect(after.y - before.y).toBeGreaterThan(20);
  await expect(page.locator('#source-editor')).toHaveValue(SAMPLE_SOURCE);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed canvas gestures lower into canonical source', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expect(page.locator('#source-editor')).toHaveValue(SAMPLE_SOURCE);

  await dragBetween(page, outputHandle(page, 1), inputHandle(page, 2));
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(1);
  await page.mouse.up();

  await expect(page.locator('#source-editor')).toHaveValue(
    'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)',
  );
  await expect(page.locator('#edges path.edge')).toHaveCount(1);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed selected edge deletion lowers into canonical source', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expect(page.locator('#source-editor')).toHaveValue(SAMPLE_SOURCE);

  await dragBetween(page, outputHandle(page, 1), inputHandle(page, 2));
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(1);
  await page.mouse.up();
  await expect(edgePaths(page)).toHaveCount(1);
  await expect(page.locator('#source-editor')).toHaveValue(
    'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)',
  );

  await clickEdge(page, 0);
  await expect(edgePaths(page).first()).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await page.keyboard.press('Backspace');

  await expect(page.locator('#source-editor')).toHaveValue(SAMPLE_SOURCE);
  await expect(page.locator('.canvas-node')).toHaveCount(2);
  await expect(edgePaths(page)).toHaveCount(0);
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');
  await expect(page.locator('#source-status')).toHaveAttribute('data-tone', 'success');
  await expect(page.locator('#source-status')).toContainText(
    'Disconnected selected edge through graph-dsl source.',
  );
  expect(runtimeErrors).toEqual([]);
});

test('source-backed selected node deletion lowers into canonical source', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expect(page.locator('#source-editor')).toHaveValue(SAMPLE_SOURCE);

  const meter = page.locator('.canvas-node[data-node-id="2"]');
  await meter.click();
  await expect(meter).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await page.keyboard.press('Delete');

  await expect(page.locator('#source-editor')).toHaveValue('osc = sine(freq: 440Hz)');
  await expect(page.locator('.canvas-node')).toHaveCount(1);
  await expect(page.locator('.canvas-node[data-node-id="2"]')).toHaveCount(0);
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed deletion rejects unsafe survivor references', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await page.locator('#source-connect').click();
  await expect(page.locator('#source-editor')).toHaveValue(
    'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)',
  );

  const osc = page.locator('.canvas-node[data-node-id="1"]');
  await osc.click();
  await expect(osc).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await page.keyboard.press('Delete');

  await expect(page.locator('#source-editor')).toHaveValue(
    'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)',
  );
  await expect(page.locator('.canvas-node')).toHaveCount(2);
  await expect(page.locator('#source-status')).toHaveAttribute('data-tone', 'error');
  await expect(page.locator('#source-status')).toContainText('Source delete rejected:');
  await expect(page.locator('#source-status')).toContainText('still references deleted binding');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed deletion ignores source editor focus', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await page.locator('.canvas-node[data-node-id="2"]').click();
  await page.locator('#source-editor').focus();
  await page.keyboard.press('Backspace');

  await expect(page.locator('.canvas-node')).toHaveCount(2);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

for (const invalidSource of INVALID_SOURCE_CASES) {
  test(`source-backed apply reports ${invalidSource.name} source as invalid`, async ({ page }) => {
    const runtimeErrors = collectRuntimeErrors(page);

    await page.goto('/?source=1');
    await expect(page.locator('#source-editor')).toHaveValue(SAMPLE_SOURCE);
    await expect(page.locator('.canvas-node')).toHaveCount(2);

    await page.locator('#source-editor').fill(invalidSource.source);
    await page.locator('#source-apply').click();

    await expect(page.locator('#source-editor')).toHaveValue(invalidSource.source);
    await expect(page.locator('.canvas-node')).toHaveCount(2);
    await expect(page.locator('#edges path.edge')).toHaveCount(0);
    await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
    await expect(page.locator('#source-status')).toHaveAttribute('data-tone', 'error');
    await expect(page.locator('#source-status')).toContainText(
      'Current source is invalid; canvas is rendering last-good graph: current source is not graph-valid:',
    );
    await expect(page.locator('#validation-list .validation-item.error').first()).toBeVisible();

    expect(runtimeErrors).toEqual([]);
  });
}

test('source-backed mode mutates canonical source and render state together', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');

  await expect(page.locator('#source-panel')).toBeVisible();
  await expect(page.locator('#source-mode-toggle')).toHaveText('Return to canvas runtime');
  await expect(page.locator('#source-editor')).toHaveValue(SAMPLE_SOURCE);
  await expect(page.locator('.canvas-node')).toHaveCount(2);
  await expect(page.locator('#edges path.edge')).toHaveCount(0);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');

  await page.locator('#source-connect').click();
  await expect(page.locator('#source-editor')).toHaveValue(
    'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)',
  );
  await expect(page.locator('#edges path.edge')).toHaveCount(1);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');

  await page.locator('#source-insert').click();
  await expect(page.locator('#source-editor')).toHaveValue(
    'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)\nreverb = plate()',
  );
  await expect(page.locator('.canvas-node')).toHaveCount(3);
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');

  await page.locator('#source-editor').fill(
    'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)\nreverb = plate()\ntap = scope(input: reverb)',
  );
  await page.locator('#source-apply').click();
  await expect(page.locator('.canvas-node')).toHaveCount(4);
  await expect(page.locator('#edges path.edge')).toHaveCount(2);
  await expect(page.locator('#source-status')).toHaveText(
    'Source applied; render state is reparsed from Loom GraphDoc.',
  );

  expect(runtimeErrors).toEqual([]);
});
