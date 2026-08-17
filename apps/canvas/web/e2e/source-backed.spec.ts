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

// Source-backed nodes are identified by the Loom projection token
// (`node#<n>:<binding>`), exposed in the DOM as `data-node-id`. Tests locate a
// node by its user-facing binding (the `.node-title`) and resolve the token on
// demand, so they neither hardcode the internal token format nor break when a
// rename re-mints the token.
function sourceNode(page: Page, binding: string): Locator {
  return page
    .locator('.canvas-node')
    .filter({ has: page.locator('.node-title', { hasText: new RegExp(`^${binding}$`) }) });
}

function inputHandle(page: Page, binding: string): Locator {
  return sourceNode(page, binding).locator('.handle.input');
}

function outputHandle(page: Page, binding: string): Locator {
  return sourceNode(page, binding).locator('.handle.output');
}

function edgePaths(page: Page): Locator {
  return page.locator('#edges path.edge');
}

// The source panel renders a CodeMirror editor (contenteditable), not a
// textarea. Read its document by joining the rendered `.cm-line` divs with
// newlines, normalizing the NBSPs CodeMirror uses for runs of spaces.
async function cmText(page: Page): Promise<string> {
  const lines = await page.locator('#source-editor-cm .cm-line').allTextContents();
  return lines.map((line) => line.replace(/ /g, ' ')).join('\n');
}

// CodeMirror updates asynchronously (mount, set_doc echo, the 250ms graph
// poll), so poll the document rather than reading it once.
async function expectSource(page: Page, expected: string): Promise<void> {
  await expect.poll(() => cmText(page)).toBe(expected);
}

// Replace the whole CodeMirror document, the way a user select-all + paste
// would: the resulting transaction flows through `listen(on_change=...)` and
// lowers into graph-dsl source.
async function setSource(page: Page, text: string): Promise<void> {
  await page.locator('#source-editor-cm .cm-content').click();
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.insertText(text);
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

async function clickEdge(page: Page, index: number, button: 'left' | 'right' = 'left'): Promise<void> {
  const point = await edgeMidpoint(edgePaths(page).nth(index));
  await page.mouse.click(point.x, point.y, { button });
}

async function openBackgroundContextMenu(page: Page): Promise<void> {
  const box = await page.locator('#canvas-root').boundingBox();
  if (!box) throw new Error('canvas root is not visible');
  await page.mouse.click(box.x + box.width - 48, box.y + 48, { button: 'right' });
}

async function dispatchContextMenu(
  page: Page,
  selector: string,
  clientX: number,
  clientY: number,
): Promise<void> {
  await page.evaluate(({ selector, clientX, clientY }) => {
    const target = document.querySelector(selector);
    if (!target) throw new Error(`context-menu target not found: ${selector}`);
    const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true });
    Object.defineProperties(event, {
      clientX: { value: clientX },
      clientY: { value: clientY },
    });
    target.dispatchEvent(event);
  }, { selector, clientX, clientY });
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
  await expectSource(page, SAMPLE_SOURCE);

  const node = sourceNode(page, 'osc');
  const before = await center(node, 'source-backed node');
  await dragBy(page, node.locator('.node-title'), 82, 36);
  const after = await center(node, 'dragged source-backed node');

  expect(after.x - before.x).toBeGreaterThan(60);
  expect(after.y - before.y).toBeGreaterThan(20);
  await expectSource(page, SAMPLE_SOURCE);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed invalid node pointerdown does not reserve a gesture', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const captureIds: number[] = [];
    root.setPointerCapture = (pointerId: number) => captureIds.push(pointerId);
    (window as Window & { __canopyCaptureIds?: number[] }).__canopyCaptureIds = captureIds;
    const node = document.querySelector('.canvas-node');
    if (!node) throw new Error('source node is missing');
    const event = new Event('pointerdown', { bubbles: true });
    Object.defineProperties(event, {
      pointerId: { value: 61 },
      button: { value: 0 },
      clientX: { value: Number.POSITIVE_INFINITY },
      clientY: { value: Number.POSITIVE_INFINITY },
    });
    node.dispatchEvent(event);
  });

  await expect(page.locator('#canvas-root')).not.toHaveClass(/panning/);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 62,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);
  expect(await page.evaluate(() => (
    window as Window & { __canopyCaptureIds?: number[] }
  ).__canopyCaptureIds)).toEqual([62]);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 62,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  expect(runtimeErrors).toEqual([]);
});

test('source-backed canvas gestures lower into canonical source', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  await dragBetween(page, outputHandle(page, 'osc'), inputHandle(page, 'meter'));
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(1);
  await page.mouse.up();

  await expectSource(page, 'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)');
  await expect(page.locator('#edges path.edge')).toHaveCount(1);
  await expect(page.locator('#edges path.edge')).toHaveAttribute('d', /^M /);
  await expect(page.locator('#edges path.edge')).toHaveAttribute('aria-label', /^Disconnect /);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed self connection is rejected by compatibility validation', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  await dragBetween(page, outputHandle(page, 'osc'), inputHandle(page, 'osc'));
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(1);
  await page.mouse.up();

  await expect(page.locator('#edges path.edge')).toHaveCount(0);
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(0);
  await expectSource(page, SAMPLE_SOURCE);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed release hit ignores elements outside the canvas root', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const source = [...document.querySelectorAll('.handle.output')].find((handle) => (
      handle.closest('.canvas-node')?.querySelector('.node-title')?.textContent === 'osc'
    ));
    if (!source) throw new Error('source output handle is missing');
    const outside = document.createElement('div');
    outside.id = 'outside-release-target';
    outside.dataset.handle = 'input';
    outside.dataset.nodeId = 'meter';
    outside.dataset.portId = 'input';
    outside.style.cssText = 'position:fixed;left:0;top:0;width:32px;height:32px;z-index:99999';
    document.body.appendChild(outside);
    root.setPointerCapture = () => undefined;
    const rect = source.getBoundingClientRect();
    source.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 105,
      button: 0,
      clientX: rect.left + rect.width / 2,
      clientY: rect.top + rect.height / 2,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 105,
      buttons: 1,
      clientX: 16.25,
      clientY: 16.75,
    }));
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 105,
      button: 0,
      clientX: 16.25,
      clientY: 16.75,
    }));
  });

  await expect(page.locator('#edges path.edge')).toHaveCount(0);
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(0);
  await expectSource(page, SAMPLE_SOURCE);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  await page.evaluate(() => document.querySelector('#outside-release-target')?.remove());
  expect(runtimeErrors).toEqual([]);
});

test('source-backed wheel shares normalized camera semantics', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);
  const dispatchWheel = async (
    deltaY: number,
    deltaMode: number,
  ): Promise<boolean> => {
    return page.evaluate(({ deltaY, deltaMode }) => {
      const root = document.querySelector('#canvas-root') as HTMLDivElement;
      const rect = root.getBoundingClientRect();
      const event = new WheelEvent('wheel', {
        bubbles: true,
        cancelable: true,
        deltaY,
        deltaMode,
        clientX: rect.left + 120.25,
        clientY: rect.top + 80.75,
      });
      root.dispatchEvent(event);
      return event.defaultPrevented;
    }, { deltaY, deltaMode });
  };

  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  expect(await dispatchWheel(0, 0)).toBe(true);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  await dispatchWheel(-2, 1);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.setPointerCapture = () => undefined;
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 122,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);
  expect(await dispatchWheel(-100, 0)).toBe(true);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 122,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  await expect(page.locator('#canvas-root')).not.toHaveClass(/panning/);
  expect(runtimeErrors).toEqual([]);
});

test('source-backed connection keeps its preview while wheel is consumed', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  const start = await center(outputHandle(page, 'osc'), 'source output handle');
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(start.x + 40.25, start.y + 40.75, { steps: 4 });
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(1);

  const prevented = await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const rect = root.getBoundingClientRect();
    const event = new WheelEvent('wheel', {
      bubbles: true,
      cancelable: true,
      deltaY: -100,
      deltaMode: 0,
      clientX: rect.left + 120.25,
      clientY: rect.top + 80.75,
    });
    root.dispatchEvent(event);
    return event.defaultPrevented;
  });
  expect(prevented).toBe(true);
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(1);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');

  await page.mouse.up();
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(0);
  expect(runtimeErrors).toEqual([]);
});

test('source-backed pointercancel drops the local connection preview', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const source = [...document.querySelectorAll('.handle.output')].find((handle) => (
      handle.closest('.canvas-node')?.querySelector('.node-title')?.textContent === 'osc'
    ));
    if (!source) throw new Error('source output handle is missing');
    root.setPointerCapture = () => undefined;
    const rect = source.getBoundingClientRect();
    source.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 74,
      button: 0,
      clientX: rect.left + rect.width / 2,
      clientY: rect.top + rect.height / 2,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 74,
      buttons: 1,
      clientX: rect.left + rect.width / 2 + 40,
      clientY: rect.top + rect.height / 2 + 40,
    }));
    root.dispatchEvent(new PointerEvent('pointercancel', {
      bubbles: true,
      pointerId: 74,
      clientX: rect.left + rect.width / 2 + 40,
      clientY: rect.top + rect.height / 2 + 40,
    }));
  });
  await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));

  await expect(page.locator('#edges path.edge-pending')).toHaveCount(0);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  await expectSource(page, SAMPLE_SOURCE);
  expect(runtimeErrors).toEqual([]);
});

test('source-backed connection ignores non-finite preview moves', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  const source = outputHandle(page, 'osc');
  const start = await center(source, 'source output handle');
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.mouse.move(start.x + 40, start.y + 40, { steps: 4 });
  const pending = page.locator('#edges path.edge-pending');
  await expect(pending).toHaveCount(1);
  const before = await pending.getAttribute('d');

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root');
    if (!root) throw new Error('canvas root is missing');
    const event = new Event('pointermove', { bubbles: true });
    Object.defineProperties(event, {
      pointerId: { value: 1 },
      clientX: { value: Number.POSITIVE_INFINITY },
      clientY: { value: Number.POSITIVE_INFINITY },
      buttons: { value: 1 },
    });
    root.dispatchEvent(event);
  });
  await expect(pending).toHaveAttribute('d', before ?? '');
  expect(await pending.getAttribute('d')).toBe(before);
  await page.mouse.up();
  await expect(pending).toHaveCount(0);
  expect(runtimeErrors).toEqual([]);
});

test('source-backed overflowed edge geometry removes stale SVG paths', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);
  await dragBetween(page, outputHandle(page, 'osc'), inputHandle(page, 'meter'));
  await page.mouse.up();
  await expect(page.locator('#edges path.edge')).toHaveCount(1);

  const node = sourceNode(page, 'osc');
  const start = await center(node.locator('.node-title'), 'source node');
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root');
    if (!root) throw new Error('canvas root is missing');
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 1,
      clientX: 1.7e308,
      clientY: 1.0e308,
      buttons: 1,
    }));
  });
  await expect(page.locator('#edges path.edge')).toHaveCount(0);
  await page.mouse.up();
  expect(runtimeErrors).toEqual([]);
});

async function selectSourceNode(page: Page, binding: string): Promise<void> {
  const node = sourceNode(page, binding);
  await node.click();
  await expect(node).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
}

test('source-backed inspector rename lowers to canonical source and references', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await page.locator('#source-connect').click();
  await expectSource(page, 'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)');

  await selectSourceNode(page, 'osc');
  const renameInput = page.locator('#node-rename-input');
  await expect(renameInput).toHaveValue('osc');
  await renameInput.fill('lfo');
  await renameInput.press('Enter');

  await expectSource(page, 'lfo = sine(freq: 440Hz)\nmeter = scope(input: lfo)');
  // The rename re-mints the node's token, so the old binding is gone and the new
  // one is present — the node is now identified as `lfo`.
  await expect(sourceNode(page, 'osc')).toHaveCount(0);
  await expect(sourceNode(page, 'lfo')).toHaveCount(1);
  await expect(page.locator('#edges path.edge')).toHaveCount(1);
  await expect(page.locator('#source-status')).toHaveAttribute('data-tone', 'success');
  await expect(page.locator('#source-status')).toContainText(
    'Renamed node binding through graph-dsl source.',
  );
  await expect(page.locator('#action-stat')).toHaveText('3 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed inspector numeric parameter edit lowers to canonical source', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  await selectSourceNode(page, 'osc');
  const freqInput = page.locator('#node-param-freq');
  await expect(freqInput).toHaveValue('440');
  await freqInput.fill('880');
  await freqInput.press('Enter');

  await expectSource(page, 'osc = sine(freq: 880Hz)\nmeter = scope()');
  await expect(page.locator('#source-status')).toHaveAttribute('data-tone', 'success');
  await expect(page.locator('#source-status')).toContainText(
    'Updated freq through graph-dsl source.',
  );
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed selected edge deletion lowers into canonical source', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  await dragBetween(page, outputHandle(page, 'osc'), inputHandle(page, 'meter'));
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(1);
  await page.mouse.up();
  await expect(edgePaths(page)).toHaveCount(1);
  await expectSource(page, 'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)');

  const osc = sourceNode(page, 'osc');
  await osc.click();
  await expect(osc).toHaveClass(/(?:^|\s)selected(?:\s|$)/);

  await clickEdge(page, 0);
  await expect(edgePaths(page).first()).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(osc).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');

  await page.keyboard.press('Backspace');

  await expectSource(page, SAMPLE_SOURCE);
  await expect(page.locator('.canvas-node')).toHaveCount(2);
  await expect(edgePaths(page)).toHaveCount(0);
  await expect(page.locator('#edges path.edge.selected')).toHaveCount(0);
  await expect(osc).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(page.locator('#action-stat')).toHaveText('3 actions logged');
  await expect(page.locator('#source-status')).toHaveAttribute('data-tone', 'success');
  await expect(page.locator('#source-status')).toContainText(
    'Disconnected selected edge through graph-dsl source.',
  );
  expect(runtimeErrors).toEqual([]);
});

test('source-backed finite but Float-overflowing background anchors are rejected', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);
  await dispatchContextMenu(page, '#canvas-root', Number.MAX_VALUE, 0);

  await expect(page.locator('#context-menu [role="menu"]')).toBeHidden();
  await expectSource(page, SAMPLE_SOURCE);
  await expect(page.locator('.canvas-node')).toHaveCount(2);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed context menu inserts through canonical source lowering', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);
  await openBackgroundContextMenu(page);
  const menu = page.locator('#context-menu [role="menu"]');
  await menu.getByRole('menuitem', { name: 'Custom step' }).click();

  await expectSource(page, `${SAMPLE_SOURCE}\ncustom = custom()`);
  await expect(page.locator('.canvas-node')).toHaveCount(3);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed edge context menu disconnects its captured edge', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);
  await dragBetween(page, outputHandle(page, 'osc'), inputHandle(page, 'meter'));
  await page.mouse.up();
  await expect(edgePaths(page)).toHaveCount(1);
  await expectSource(page, 'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)');

  await clickEdge(page, 0, 'right');
  const menu = page.locator('#context-menu [role="menu"]');
  await expect(menu).toBeVisible();
  await expect(menu.getByRole('menuitem', { name: 'Disconnect edge' })).toHaveCount(1);
  await menu.getByRole('menuitem', { name: 'Disconnect edge' }).click();

  await expectSource(page, SAMPLE_SOURCE);
  await expect(edgePaths(page)).toHaveCount(0);
  await expect(page.locator('#source-status')).toHaveAttribute('data-tone', 'success');
  await expect(page.locator('#source-status')).toHaveText(
    'Disconnected selected edge through graph-dsl source.',
  );
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed selected node deletion lowers into canonical source', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  const meter = sourceNode(page, 'meter');
  await meter.click();
  await expect(meter).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await page.keyboard.press('Delete');

  await expectSource(page, 'osc = sine(freq: 440Hz)');
  await expect(page.locator('.canvas-node')).toHaveCount(1);
  await expect(sourceNode(page, 'meter')).toHaveCount(0);
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed deletion rejects unsafe survivor references', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await page.locator('#source-connect').click();
  await expectSource(page, 'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)');

  const osc = sourceNode(page, 'osc');
  await osc.click();
  await expect(osc).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await page.keyboard.press('Delete');

  await expectSource(page, 'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)');
  await expect(page.locator('.canvas-node')).toHaveCount(2);
  await expect(page.locator('#source-status')).toHaveAttribute('data-tone', 'error');
  await expect(page.locator('#source-status')).toContainText('Source delete rejected:');
  await expect(page.locator('#source-status')).toContainText('still references deleted binding');
  expect(runtimeErrors).toEqual([]);
});

test('source-backed deletion ignores source editor focus', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expect(page.locator('.canvas-node')).toHaveCount(2);

  // Select a canvas node so a missing focus guard WOULD delete it. The keydown
  // bubbles to the document handler even from CodeMirror (CM6 does not
  // stopPropagation by default), so `editableKeyboardTarget` is the only thing
  // between this Backspace and the MoonBit `deleteSelection` request.
  await sourceNode(page, 'meter').click();
  await expect(sourceNode(page, 'meter')).toHaveClass(/(?:^|\s)selected(?:\s|$)/);

  // Put the cursor at the end of the document so Backspace is a real editor
  // edit (deleting the trailing `)`), not a no-op at offset 0.
  await page.locator('#source-editor-cm .cm-content').focus();
  await page.keyboard.press('ControlOrMeta+End');
  await page.keyboard.press('Backspace');

  // The keystroke edited the source editor ...
  await expectSource(page, 'osc = sine(freq: 440Hz)\nmeter = scope(');
  // ... and did NOT delete the selected canvas node (the focus guard held).
  await expect(page.locator('.canvas-node')).toHaveCount(2);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

for (const invalidSource of INVALID_SOURCE_CASES) {
  test(`source-backed apply reports ${invalidSource.name} source as invalid`, async ({ page }) => {
    const runtimeErrors = collectRuntimeErrors(page);

    await page.goto('/?source=1');
    await expectSource(page, SAMPLE_SOURCE);
    await expect(page.locator('.canvas-node')).toHaveCount(2);

    await setSource(page, invalidSource.source);
    await page.locator('#source-apply').click();

    await expectSource(page, invalidSource.source);
    await expect(page.locator('.canvas-node')).toHaveCount(2);
    await expect(page.locator('#edges path.edge')).toHaveCount(0);
    await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
    const status = page.locator('#source-status');
    await expect(status).toHaveAttribute('role', 'status');
    await expect(status).toHaveAttribute('aria-live', 'polite');
    await expect(status).toHaveAttribute('aria-atomic', 'true');
    await expect(status).toHaveAttribute('data-tone', 'error');
    await expect(status).toContainText(
      'Current source is invalid; canvas is rendering last-good graph: current source is not graph-valid:',
    );
    await expect(page.locator('#validation-list .validation-item.error').first()).toBeVisible();

    expect(runtimeErrors).toEqual([]);
  });
}

test('source-backed editor recovers from a transiently-invalid edit without corrupting incremental deltas', async ({
  page,
}) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);
  await expect(page.locator('.canvas-node')).toHaveCount(2);

  // Delete `440Hz` with an incremental edit, leaving the buffer transiently
  // invalid (`osc = sine(freq: )`). The graph rolls back to last-good and the
  // editor diverges (dirty) — the precondition for the rebase corruption.
  const content = page.locator('#source-editor-cm .cm-content');
  await content.click();
  await page.keyboard.press('ControlOrMeta+Home');
  for (let i = 0; i < 'osc = sine(freq: '.length; i++) {
    await page.keyboard.press('ArrowRight');
  }
  for (let i = 0; i < '440Hz'.length; i++) {
    await page.keyboard.press('Shift+ArrowRight');
  }
  await page.keyboard.press('Delete');
  await expectSource(page, 'osc = sine(freq: )\nmeter = scope()');
  await expect(page.locator('#source-status')).toHaveAttribute('data-tone', 'error');
  await expect(page.locator('.canvas-node')).toHaveCount(2);

  // Type a different valid value at the cursor. With the buffer dirty, each
  // keystroke's delta is expressed against the editor text, not the graph's
  // rolled-back last-good source; replaying incrementally would splice into
  // the wrong coordinates (e.g. `220Hz440Hz`). It must recover and re-apply to
  // the graph as exactly the typed text.
  await page.keyboard.type('220Hz');

  // The CodeMirror buffer transiently shows the typed text either way, so the
  // graph source is the real observable. Let the 250ms graph→editor poll run a
  // couple of cycles: when the graph and editor disagree (only possible if the
  // graph was corrupted) the poll pushes the canonical source back into the
  // buffer. With the rebase fixed the graph holds exactly `220Hz`, the poll is
  // a no-op, and the buffer stays put; without the fix the deltas replay
  // against the rolled-back last-good source and the poll surfaces the
  // corrupted `220Hz440Hz` here.
  await page.waitForTimeout(600);
  expect(await cmText(page)).toBe('osc = sine(freq: 220Hz)\nmeter = scope()');
  await expect(page.locator('#source-status')).toHaveAttribute('data-tone', 'success');
  await expect(page.locator('.canvas-node')).toHaveCount(2);

  expect(runtimeErrors).toEqual([]);
});

test('source-backed mode mutates canonical source and render state together', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');

  await expect(page.locator('#source-panel')).toBeVisible();
  await expect(page.locator('#source-mode-toggle')).toHaveText('Return to canvas runtime');
  await expectSource(page, SAMPLE_SOURCE);
  await expect(page.locator('.canvas-node')).toHaveCount(2);
  await expect(page.locator('#edges path.edge')).toHaveCount(0);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');

  await page.locator('#source-connect').click();
  await expectSource(page, 'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)');
  await expect(page.locator('#edges path.edge')).toHaveCount(1);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');

  await page.locator('#source-insert').click();
  await expectSource(
    page,
    'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)\nreverb = plate()',
  );
  await expect(page.locator('.canvas-node')).toHaveCount(3);
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');

  await setSource(
    page,
    'osc = sine(freq: 440Hz)\nmeter = scope(input: osc)\nreverb = plate()\ntap = scope(input: reverb)',
  );
  await page.locator('#source-apply').click();
  await expect(page.locator('.canvas-node')).toHaveCount(4);
  await expect(page.locator('#edges path.edge')).toHaveCount(2);
  const status = page.locator('#source-status');
  await expect(status).toHaveAttribute('role', 'status');
  await expect(status).toHaveAttribute('aria-live', 'polite');
  await expect(status).toHaveAttribute('aria-atomic', 'true');
  await expect(status).toHaveAttribute('data-tone', 'success');
  await expect(status).toHaveText(
    'Source applied; render state is reparsed from Loom GraphDoc.',
  );

  expect(runtimeErrors).toEqual([]);
});

test('source-backed pointercancel interrupts a node drag without changing source', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);
  const node = sourceNode(page, 'osc');
  const before = await node.evaluate((element) => ({
    left: (element as HTMLElement).style.left,
    top: (element as HTMLElement).style.top,
  }));

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const node = [...document.querySelectorAll('.canvas-node')].find((candidate) => (
      candidate.querySelector('.node-title')?.textContent === 'osc'
    ));
    if (!node) throw new Error('source-backed node is missing');
    root.setPointerCapture = () => undefined;
    const rect = node.getBoundingClientRect();
    node.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 72,
      button: 0,
      clientX: rect.left + rect.width / 2,
      clientY: rect.top + rect.height / 2,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 72,
      buttons: 1,
      clientX: rect.left + rect.width / 2 + 48,
      clientY: rect.top + rect.height / 2 + 32,
    }));
    root.dispatchEvent(new PointerEvent('pointercancel', {
      bubbles: true,
      pointerId: 72,
      clientX: rect.left + rect.width / 2 + 48,
      clientY: rect.top + rect.height / 2 + 32,
    }));
  });
  await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));

  await expectSource(page, SAMPLE_SOURCE);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  const after = await node.evaluate((element) => ({
    left: (element as HTMLElement).style.left,
    top: (element as HTMLElement).style.top,
  }));
  expect(after.left).toBe(before.left);
  expect(after.top).toBe(before.top);
  expect(runtimeErrors).toEqual([]);
});

test('source-backed output connection shares the root pointer owner', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  const captureIds = await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const source = [...document.querySelectorAll('.handle.output')].find((handle) => (
      handle.closest('.canvas-node')?.querySelector('.node-title')?.textContent === 'osc'
    ));
    if (!source) throw new Error('source output handle is missing');
    const ids: number[] = [];
    root.setPointerCapture = (pointerId: number) => ids.push(pointerId);
    const rect = source.getBoundingClientRect();
    source.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 101,
      button: 0,
      clientX: rect.left + rect.width / 2,
      clientY: rect.top + rect.height / 2,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 101,
      buttons: 1,
      clientX: rect.left + rect.width / 2 + 40.25,
      clientY: rect.top + rect.height / 2 + 24.75,
    }));
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 102,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 102,
      buttons: 1,
      clientX: 220,
      clientY: 220,
    }));
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 102,
      clientX: 220,
      clientY: 220,
    }));
    return ids;
  });

  expect(captureIds).toEqual([101]);
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(1);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('lostpointercapture', {
      bubbles: true,
      pointerId: 101,
    }));
  });
  await expect(page.locator('#edges path.edge-pending')).toHaveCount(0);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 103,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);
  expect(runtimeErrors).toEqual([]);
});

test('source-backed capture failure does not enter a graph session', async ({ page }) => {
  const runtimeErrors = collectRuntimeErrors(page);

  await page.goto('/?source=1');
  await expectSource(page, SAMPLE_SOURCE);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.setPointerCapture = () => {
      throw new DOMException('pointer is no longer active', 'NotFoundError');
    };
    const source = [...document.querySelectorAll('.handle.output')].find((handle) => (
      handle.closest('.canvas-node')?.querySelector('.node-title')?.textContent === 'osc'
    ));
    if (!source) throw new Error('source output handle is missing');
    const rect = source.getBoundingClientRect();
    source.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 104,
      button: 0,
      clientX: rect.left + rect.width / 2,
      clientY: rect.top + rect.height / 2,
    }));
  });

  await expect(page.locator('#edges path.edge-pending')).toHaveCount(0);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  expect(runtimeErrors).toEqual([]);
});
