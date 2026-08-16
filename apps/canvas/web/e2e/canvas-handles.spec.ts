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

function contextMenuItems(page: Page): Locator {
  return page.locator('#context-menu [role="menuitem"]');
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

async function openBackgroundContextMenu(page: Page): Promise<void> {
  const box = await page.locator('#canvas-root').boundingBox();
  if (!box) {
    throw new Error('canvas root is not visible');
  }
  await page.mouse.click(box.x + box.width - 48, box.y + 48, { button: 'right' });
}

async function openBottomRightContextMenu(page: Page): Promise<void> {
  const box = await page.locator('#canvas-root').boundingBox();
  if (!box) {
    throw new Error('canvas root is not visible');
  }
  await page.mouse.click(box.x + box.width - 4, box.y + box.height - 4, { button: 'right' });
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

async function moveViewportOriginToMax(page: Page): Promise<void> {
  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.setPointerCapture = () => undefined;
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 51,
      button: 0,
      clientX: 0,
      clientY: 0,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 51,
      buttons: 1,
      clientX: Number.MAX_VALUE,
      clientY: 0,
    }));
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 51,
      button: 0,
      clientX: Number.MAX_VALUE,
      clientY: 0,
    }));
  });
  await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));
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

async function worldScale(page: Page): Promise<number> {
  const transform = await worldTransform(page);
  const match = transform.match(/scale\(([^)]+)\)/);
  if (!match) throw new Error(`world transform has no scale: ${transform}`);
  return Number(match[1]);
}

test('canvas wheel normalizes units and rejects no-op or active input', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  const dispatchWheel = async (
    deltaY: number,
    deltaMode: number,
    ctrlKey = false,
  ): Promise<boolean> => {
    return page.evaluate(({ deltaY, deltaMode, ctrlKey }) => {
      const root = document.querySelector('#canvas-root') as HTMLDivElement;
      const rect = root.getBoundingClientRect();
      const event = new WheelEvent('wheel', {
        bubbles: true,
        cancelable: true,
        deltaY,
        deltaMode,
        ctrlKey,
        clientX: rect.left + 120.25,
        clientY: rect.top + 80.75,
      });
      root.dispatchEvent(event);
      return event.defaultPrevented;
    }, { deltaY, deltaMode, ctrlKey });
  };

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  const initialTransform = await worldTransform(page);

  expect(await dispatchWheel(0, 0)).toBe(true);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  expect(await worldTransform(page)).toBe(initialTransform);

  await dispatchWheel(-50, 0);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  const pixelScale = await worldScale(page);

  await page.reload();
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await dispatchWheel(-2, 1);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  const lineScale = await worldScale(page);
  expect(lineScale).toBeCloseTo(pixelScale, 9);

  await page.reload();
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await dispatchWheel(-10, 0);
  const smallScale = await worldScale(page);
  await page.reload();
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await dispatchWheel(-100, 0);
  const largeScale = await worldScale(page);
  expect(largeScale).toBeGreaterThan(smallScale);

  await page.reload();
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.setPointerCapture = () => undefined;
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 121,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);
  const activeTransform = await worldTransform(page);
  expect(await dispatchWheel(-100, 0)).toBe(true);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  expect(await worldTransform(page)).toBe(activeTransform);
  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 121,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  await expect(page.locator('#canvas-root')).not.toHaveClass(/panning/);
  expect(runtimeErrors).toEqual([]);
});

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

test('non-finite background pointerdown does not reserve a canvas gesture', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const captureIds: number[] = [];
    root.setPointerCapture = (pointerId: number) => captureIds.push(pointerId);
    (window as Window & { __canopyCaptureIds?: number[] }).__canopyCaptureIds = captureIds;
    const event = new Event('pointerdown', { bubbles: true });
    Object.defineProperties(event, {
      pointerId: { value: 41 },
      button: { value: 0 },
      clientX: { value: Number.POSITIVE_INFINITY },
      clientY: { value: Number.POSITIVE_INFINITY },
    });
    root.dispatchEvent(event);
  });

  await expect(page.locator('#canvas-root')).not.toHaveClass(/panning/);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 42,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });

  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);
  expect(await page.evaluate(() => (
    window as Window & { __canopyCaptureIds?: number[] }
  ).__canopyCaptureIds)).toEqual([42]);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 42,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  expect(runtimeErrors).toEqual([]);
});

test('overflowed node pointerdown does not reserve the next canvas gesture', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);

  // Move the viewport origin to the largest finite coordinate. The later
  // finite screen point at -MAX_VALUE then overflows screen-to-world.
  await moveViewportOriginToMax(page);

  await page.locator('.canvas-node[data-node-id="1"]').evaluate((node) => {
    node.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 52,
      button: 0,
      clientX: -Number.MAX_VALUE,
      clientY: 0,
    }));
  });
  await expect(page.locator('#canvas-root')).not.toHaveClass(/panning/);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 53,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 53,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  expect(runtimeErrors).toEqual([]);
});

test('same-frame viewport changes use current geometry for pointerdown', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);

  const captureIds = await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const captureIds: number[] = [];
    root.setPointerCapture = (pointerId: number) => captureIds.push(pointerId);
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 51,
      button: 0,
      clientX: 0,
      clientY: 0,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 51,
      buttons: 1,
      clientX: Number.MAX_VALUE,
      clientY: 0,
    }));
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 51,
      button: 0,
      clientX: Number.MAX_VALUE,
      clientY: 0,
    }));

    const node = document.querySelector('.canvas-node[data-node-id="1"]');
    if (!node) throw new Error('canvas node is missing');
    node.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 52,
      button: 0,
      clientX: -Number.MAX_VALUE * 0.75,
      clientY: 0,
    }));
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 53,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
    return captureIds;
  });

  expect(captureIds).toEqual([51, 53]);
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);
  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 53,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  expect(runtimeErrors).toEqual([]);
});

test('invalid add-node context geometry leaves selection unchanged', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await clickEdge(page, 0);
  await expect(edgePaths(page).first()).toHaveClass(/(?:^|\s)selected(?:\s|$)/);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true });
    Object.defineProperties(event, {
      clientX: { value: Number.POSITIVE_INFINITY },
      clientY: { value: Number.POSITIVE_INFINITY },
    });
    root.dispatchEvent(event);
  });

  await expect(page.locator('#context-menu [role="menu"]')).toBeHidden();
  await expect(edgePaths(page).first()).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('overflowed add-node context geometry leaves state unchanged', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await moveViewportOriginToMax(page);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true });
    Object.defineProperties(event, {
      clientX: { value: -Number.MAX_VALUE },
      clientY: { value: 0 },
    });
    root.dispatchEvent(event);
  });

  await expect(page.locator('#context-menu [role="menu"]')).toBeHidden();
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('invalid background context requests preserve an existing menu and state', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(edgePaths(page)).toHaveCount(3);
  await moveViewportOriginToMax(page);
  await dispatchContextMenu(page, '#edges path.edge', 0, 0);
  const menu = page.locator('#context-menu [role="menu"]');
  await expect(menu).toBeVisible();
  await expect(page.locator('#edges path.edge.selected')).toHaveCount(1);

  await dispatchContextMenu(page, '#canvas-root', -Number.MAX_VALUE, 0);

  await expect(menu).toBeVisible();
  await expect(page.locator('#edges path.edge.selected')).toHaveCount(1);
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('finite but Float-overflowing edge anchors are rejected', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(edgePaths(page)).toHaveCount(3);
  await dispatchContextMenu(page, '#edges path.edge', Number.MAX_VALUE, 0);

  await expect(page.locator('#context-menu [role="menu"]')).toBeHidden();
  await expect(page.locator('#edges path.edge.selected')).toHaveCount(0);
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
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

test('selected canvas edge deletes before a coexisting node selection', async ({ page }) => {
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

  const node = page.locator('.canvas-node[data-node-id="1"]');
  await node.click();
  await expect(node).toHaveClass(/(?:^|\s)selected(?:\s|$)/);

  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  await clickEdge(page, 0);
  await expect(edgePaths(page).nth(0)).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(node).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');

  await page.keyboard.press('Delete');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(edgePaths(page)).toHaveCount(2);
  await expect(page.locator('#edges path.edge.selected')).toHaveCount(0);
  await expect(node).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');

  await page.keyboard.press('Delete');
  await expect(page.locator('.canvas-node')).toHaveCount(5);
  await expect(page.locator('.canvas-node[data-node-id="1"]')).toHaveCount(0);
  await expect(edgePaths(page)).toHaveCount(2);
  await expect(page.locator('#action-stat')).toHaveText('3 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('Delete closes an edge context menu after deleting the captured edge', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(edgePaths(page)).toHaveCount(3);

  await clickEdge(page, 0, 'right');
  const menu = page.locator('#context-menu [role="menu"]');
  await expect(menu).toBeVisible();

  await page.keyboard.press('Delete');

  await expect(edgePaths(page)).toHaveCount(2);
  await expect(menu).toBeHidden();
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('Backspace closes a background context menu after deleting selected nodes', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  const node = page.locator('.canvas-node[data-node-id="2"]');
  await node.click();
  await expect(node).toHaveClass(/(?:^|\s)selected(?:\s|$)/);

  await openBackgroundContextMenu(page);
  const menu = page.locator('#context-menu [role="menu"]');
  await expect(menu).toBeVisible();

  await page.keyboard.press('Backspace');

  await expect(page.locator('.canvas-node')).toHaveCount(5);
  await expect(menu).toBeHidden();
  await expect(page.locator('#action-stat')).toHaveText('2 actions logged');
  expect(runtimeErrors).toEqual([]);
});

test('canvas context menu adds a node from the MoonBit catalog', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);

  await openBackgroundContextMenu(page);
  const menu = page.locator('#context-menu [role="menu"]');
  await expect(menu.getByRole('menuitem', { name: 'Timer trigger' })).toHaveCount(1);
  await menu.getByRole('menuitem', { name: 'Timer trigger' }).click();

  await expect(page.locator('.canvas-node')).toHaveCount(7);
  await expect(page.locator('.canvas-node .node-title', { hasText: 'Timer trigger' })).toHaveCount(2);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('canvas edge context menu disconnects the edge', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') {
      runtimeErrors.push(message.text());
    }
  });

  await page.goto('/');
  await expect(edgePaths(page)).toHaveCount(3);

  await clickEdge(page, 0, 'right');
  await page.getByRole('menuitem', { name: 'Disconnect edge' }).click();

  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(edgePaths(page)).toHaveCount(2);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('canvas context menu supports headless keyboard navigation and dismissal', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') {
      runtimeErrors.push(message.text());
    }
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);

  const menu = page.locator('#context-menu [role="menu"]');
  const canvasRoot = page.locator('#canvas-root');
  const searchInput = page.locator('#node-search');
  const items = contextMenuItems(page);

  await openBackgroundContextMenu(page);
  await expect(menu).toBeVisible();
  await expect(items).toHaveCount(7);
  await expect(items.nth(0)).toHaveAttribute('data-active', 'true');
  await expect(items.nth(0)).toBeFocused();

  await page.keyboard.press('ArrowDown');
  await expect(items.nth(1)).toHaveAttribute('data-active', 'true');
  await expect(items.nth(1)).toBeFocused();

  await page.keyboard.press('End');
  await expect(items.nth(6)).toHaveAttribute('data-active', 'true');
  await expect(items.nth(6)).toBeFocused();

  await page.keyboard.press('Home');
  await expect(items.nth(0)).toHaveAttribute('data-active', 'true');
  await expect(items.nth(0)).toBeFocused();

  await page.keyboard.press('Escape');
  await expect(menu).toBeHidden();
  await expect(canvasRoot).toBeFocused();

  await openBackgroundContextMenu(page);
  await searchInput.focus();
  await page.keyboard.press('Escape');
  await expect(menu).toBeHidden();
  await expect(canvasRoot).toBeFocused();

  await openBackgroundContextMenu(page);
  await searchInput.click();
  await expect(menu).toBeHidden();
  await expect(searchInput).toBeFocused();

  await openBottomRightContextMenu(page);
  await expect(page.locator('#context-menu [role="menu"]')).toBeVisible();
  await expect.poll(async () => {
    const box = await page.locator('#context-menu [role="menu"]').boundingBox();
    const viewport = page.viewportSize();
    if (!box || !viewport) return false;
    return box.x >= 0 &&
      box.y >= 0 &&
      box.x + box.width <= viewport.width &&
      box.y + box.height <= viewport.height;
  }).toBe(true);
  await page.keyboard.press('Escape');
  await expect(menu).toBeHidden();
  await expect(canvasRoot).toBeFocused();

  await openBackgroundContextMenu(page);
  await expect(items.nth(0)).toBeFocused();
  await page.keyboard.press('ArrowDown');
  await expect(items.nth(1)).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.locator('.canvas-node')).toHaveCount(7);
  await expect(menu).toBeHidden();
  await expect(canvasRoot).toBeFocused();

  await openBackgroundContextMenu(page);
  await expect(items.nth(0)).toBeFocused();
  await page.keyboard.press('ArrowDown');
  await expect(items.nth(1)).toBeFocused();
  await page.keyboard.press('Space');
  await expect(page.locator('.canvas-node')).toHaveCount(8);
  await expect(menu).toBeHidden();
  await expect(canvasRoot).toBeFocused();
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

test('pointercancel interrupts a canvas drag without committing it', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  const node = page.locator('.canvas-node[data-node-id="1"]');
  const before = await node.evaluate((element) => ({
    left: (element as HTMLElement).style.left,
    top: (element as HTMLElement).style.top,
    rect: element.getBoundingClientRect().toJSON(),
  }));

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const node = document.querySelector('.canvas-node[data-node-id="1"]');
    if (!node) throw new Error('canvas node is missing');
    root.setPointerCapture = () => undefined;
    const rect = node.getBoundingClientRect();
    node.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 71,
      button: 0,
      clientX: rect.left + rect.width / 2,
      clientY: rect.top + rect.height / 2,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 71,
      buttons: 1,
      clientX: rect.left + rect.width / 2 + 48,
      clientY: rect.top + rect.height / 2 + 32,
    }));
    root.dispatchEvent(new PointerEvent('pointercancel', {
      bubbles: true,
      pointerId: 71,
      clientX: rect.left + rect.width / 2 + 48,
      clientY: rect.top + rect.height / 2 + 32,
    }));
  });
  await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));

  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');
  await expect(node).not.toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  const after = await node.evaluate((element) => ({
    left: (element as HTMLElement).style.left,
    top: (element as HTMLElement).style.top,
    rect: element.getBoundingClientRect().toJSON(),
  }));
  expect(after.left).toBe(before.left);
  expect(after.top).toBe(before.top);
  expect(runtimeErrors).toEqual([]);
});

test('canvas pan clears the hovered inspector on the first active move', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  const node = page.locator('.canvas-node[data-node-id="1"]');
  const rect = await node.boundingBox();
  if (!rect) throw new Error('hover target is missing');

  await page.evaluate(({ left, top }) => {
    const node = document.querySelector('.canvas-node[data-node-id="1"]');
    if (!node) throw new Error('hover target is missing');
    node.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 119,
      clientX: left + 20,
      clientY: top + 20,
    }));
  }, { left: rect.x, top: rect.y });
  await expect(page.locator('#inspector-node .inspector-title')).toHaveText('Timer trigger');

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.setPointerCapture = () => undefined;
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 120,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 120,
      buttons: 1,
      clientX: 60,
      clientY: 60,
    }));
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 120,
      button: 0,
      clientX: 60,
      clientY: 60,
    }));
  });

  await expect(page.locator('#inspector-node .inspector-empty')).toHaveText(
    'Select or hover a node to inspect its sparse derived details.',
  );
  expect(runtimeErrors).toEqual([]);
});

test('canvas root owns one pointer and interrupts once on lost capture', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);

  const captureIds = await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const ids: number[] = [];
    root.setPointerCapture = (pointerId: number) => ids.push(pointerId);
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 81,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 82,
      button: 0,
      clientX: 24,
      clientY: 24,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 81,
      buttons: 1,
      clientX: 60,
      clientY: 60,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 82,
      buttons: 1,
      clientX: 240,
      clientY: 240,
    }));
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 82,
      clientX: 240,
      clientY: 240,
    }));
    return ids;
  });
  expect(captureIds).toEqual([81]);
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('lostpointercapture', {
      bubbles: true,
      pointerId: 999,
    }));
  });
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('lostpointercapture', {
      bubbles: true,
      pointerId: 81,
    }));
    root.dispatchEvent(new PointerEvent('lostpointercapture', {
      bubbles: true,
      pointerId: 81,
    }));
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 81,
    }));
  });
  await expect(page.locator('#canvas-root')).not.toHaveClass(/panning/);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 83,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});

test('canvas capture failure leaves the root session idle', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.setPointerCapture = () => {
      throw new DOMException('pointer is no longer active', 'NotFoundError');
    };
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 91,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  await expect(page.locator('#canvas-root')).not.toHaveClass(/panning/);
  await expect(page.locator('#action-stat')).toHaveText('0 actions logged');

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    root.setPointerCapture = () => undefined;
    root.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 92,
      button: 0,
      clientX: 20,
      clientY: 20,
    }));
  });
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);
  expect(runtimeErrors).toEqual([]);
});

test('canvas pointer coordinates keep fractional child-target input', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  const captureIds = await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const node = document.querySelector('.canvas-node[data-node-id="1"]');
    const child = node?.querySelector('.node-title');
    if (!node || !child) throw new Error('canvas child target is missing');
    const ids: number[] = [];
    root.setPointerCapture = (pointerId: number) => ids.push(pointerId);
    const rect = child.getBoundingClientRect();
    child.dispatchEvent(new PointerEvent('pointerdown', {
      bubbles: true,
      pointerId: 93,
      button: 0,
      clientX: rect.left + 12.25,
      clientY: rect.top + 8.75,
    }));
    root.dispatchEvent(new PointerEvent('pointermove', {
      bubbles: true,
      pointerId: 93,
      buttons: 1,
      clientX: rect.left + 40.5,
      clientY: rect.top + 28.25,
    }));
    root.dispatchEvent(new PointerEvent('pointerup', {
      bubbles: true,
      pointerId: 93,
      button: 0,
      clientX: rect.left + 40.5,
      clientY: rect.top + 28.25,
    }));
    return ids;
  });

  expect(captureIds).toEqual([93]);
  await expect(page.locator('#action-stat')).toHaveText('1 action logged');
  expect(runtimeErrors).toEqual([]);
});
