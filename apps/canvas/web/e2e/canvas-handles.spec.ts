import { expect, type Locator, type Page, test } from '@playwright/test';
import type { RenderState } from '../src/graph-adapter';
import { loggedActions } from './observations';

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
  const snapshot = await page.evaluate(async () => {
    const target = document.getElementById('canvas-render-layer');
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    if (!target) throw new Error('canvas render layer is not mounted');
    const eventName = 'canopy-canvas-render-state';
    const { promise, resolve } = Promise.withResolvers<RenderState>();
    const listener = (event: Event) => {
      target.removeEventListener(eventName, listener);
      resolve(JSON.parse((event as CustomEvent<string>).detail));
    };
    target.addEventListener(eventName, listener);
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
    return await promise;
  });
  expect(snapshot.viewport.x).toBe(Number.MAX_VALUE);
  await expectWorldMatches(page, snapshot);
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

async function expectWorldMatches(page: Page, snapshot: RenderState): Promise<void> {
  const expected = await page.evaluate((viewport) => {
    const style = document.createElement('div').style;
    style.transform = `translate(${viewport.x}px, ${viewport.y}px) scale(${viewport.scale})`;
    return style.transform;
  }, snapshot.viewport);
  await expect.poll(() => worldTransform(page)).toBe(expected);
}

async function worldScale(page: Page): Promise<number> {
  const transform = await worldTransform(page);
  const match = transform.match(/scale\(([^)]+)\)/);
  if (!match) throw new Error(`world transform has no scale: ${transform}`);
  return Number(match[1]);
}

async function captureNextRenderState(page: Page): Promise<RenderState> {
  const snapshot = await page.evaluate(async () => {
    const target = document.getElementById('canvas-render-layer');
    const root = document.getElementById('canvas-root');
    if (!target || !root) throw new Error('canvas render layer is not mounted');
    const eventName = 'canopy-canvas-render-state';
    const { promise, resolve } = Promise.withResolvers<RenderState>();
    const listener = (event: Event) => {
      target.removeEventListener(eventName, listener);
      resolve(JSON.parse((event as CustomEvent<string>).detail));
    };
    target.addEventListener(eventName, listener);
    root.dispatchEvent(new WheelEvent('wheel', {
      bubbles: true,
      cancelable: true,
      deltaY: -1,
      deltaMode: 0,
      clientX: 120.25,
      clientY: 80.75,
    }));
    return await promise;
  });
  await expectWorldMatches(page, snapshot);
  return snapshot;
}

test('Rabbita keyed nodes preserve DOM identity when snapshot order changes', async ({ page }) => {
  await page.goto('/');

  const firstBefore = await page.locator('.canvas-node').nth(0).elementHandle();
  const secondBefore = await page.locator('.canvas-node').nth(1).elementHandle();
  const firstId = await page.locator('.canvas-node').nth(0).getAttribute('data-node-id');
  const secondId = await page.locator('.canvas-node').nth(1).getAttribute('data-node-id');
  if (!firstBefore || !secondBefore || !firstId || !secondId) {
    throw new Error('expected keyed workflow nodes');
  }

  const snapshot = await captureNextRenderState(page);
  snapshot.nodes.reverse();
  await page.evaluate((nextSnapshot) => {
    const target = document.getElementById('canvas-render-layer');
    if (!target) throw new Error('canvas render layer is not mounted');
    target.dispatchEvent(new CustomEvent('canopy-canvas-render-state', {
      detail: JSON.stringify(nextSnapshot),
    }));
  }, snapshot);
  await expect.poll(() => page.locator('.canvas-node').evaluateAll(
    nodes => nodes.map(node => node.getAttribute('data-node-id')),
  )).toEqual(snapshot.nodes.map((node: { id: string }) => node.id));

  const firstAfter = await page.locator(`.canvas-node[data-node-id="${firstId}"]`).elementHandle();
  const secondAfter = await page.locator(`.canvas-node[data-node-id="${secondId}"]`).elementHandle();
  if (!firstAfter || !secondAfter) throw new Error('expected reordered keyed workflow nodes');
  expect(await firstAfter.evaluate((node, before) => node === before, firstBefore)).toBe(true);
  expect(await secondAfter.evaluate((node, before) => node === before, secondBefore)).toBe(true);
});

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
    cancelPointer = false,
  ): Promise<{ defaultPrevented: boolean; snapshot: RenderState }> => {
    return page.evaluate(async ({ deltaY, deltaMode, ctrlKey, cancelPointer }) => {
      const root = document.querySelector('#canvas-root') as HTMLDivElement;
      const target = document.getElementById('canvas-render-layer');
      if (!target) throw new Error('canvas render layer is not mounted');
      const eventName = 'canopy-canvas-render-state';
      const { promise, resolve } = Promise.withResolvers<RenderState>();
      const listener = (event: Event) => {
        target.removeEventListener(eventName, listener);
        resolve(JSON.parse((event as CustomEvent<string>).detail));
      };
      target.addEventListener(eventName, listener);
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
      if (cancelPointer) {
        // Active wheel input publishes nothing. Cancel the unchanged pan to
        // acknowledge the queued rejection without committing a pointer-up action.
        root.dispatchEvent(new PointerEvent('pointercancel', {
          bubbles: true,
          pointerId: 121,
          button: 0,
          clientX: 20,
          clientY: 20,
        }));
      }
      return { defaultPrevented: event.defaultPrevented, snapshot: await promise };
    }, { deltaY, deltaMode, ctrlKey, cancelPointer });
  };

  await page.goto('/');
  await expect(page.locator('.canvas-node').first()).toBeVisible();
  await expect.poll(() => loggedActions(page)).toBe(0);
  const initialTransform = await worldTransform(page);

  const noOpWheel = await dispatchWheel(0, 0);
  expect(noOpWheel.defaultPrevented).toBe(true);
  await expectWorldMatches(page, noOpWheel.snapshot);
  expect(noOpWheel.snapshot.action_count).toBe(0);
  await expect.poll(() => loggedActions(page)).toBe(0);
  expect(await worldTransform(page)).toBe(initialTransform);

  const pixelWheel = await dispatchWheel(-50, 0);
  expect(pixelWheel.defaultPrevented).toBe(true);
  await expectWorldMatches(page, pixelWheel.snapshot);
  await expect.poll(() => loggedActions(page)).toBe(1);
  const pixelScale = await worldScale(page);

  await page.reload();
  await expect(page.locator('.canvas-node').first()).toBeVisible();
  const lineWheel = await dispatchWheel(-2, 1);
  expect(lineWheel.defaultPrevented).toBe(true);
  await expectWorldMatches(page, lineWheel.snapshot);
  await expect.poll(() => loggedActions(page)).toBe(1);
  const lineScale = await worldScale(page);
  expect(lineScale).toBeCloseTo(pixelScale, 9);

  await page.reload();
  await expect(page.locator('.canvas-node').first()).toBeVisible();
  const smallWheel = await dispatchWheel(-10, 0);
  await expectWorldMatches(page, smallWheel.snapshot);
  const smallScale = await worldScale(page);
  await page.reload();
  await expect(page.locator('.canvas-node').first()).toBeVisible();
  const largeWheel = await dispatchWheel(-100, 0);
  await expectWorldMatches(page, largeWheel.snapshot);
  const largeScale = await worldScale(page);
  expect(largeScale).toBeGreaterThan(smallScale);

  await page.reload();
  await expect(page.locator('.canvas-node').first()).toBeVisible();
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
  const activeWheel = await dispatchWheel(-100, 0, false, true);
  expect(activeWheel.defaultPrevented).toBe(true);
  await expect(page.locator('#canvas-root')).not.toHaveClass(/panning/);
  expect(activeWheel.snapshot.action_count).toBe(0);
  await expectWorldMatches(page, activeWheel.snapshot);
  await expect.poll(() => loggedActions(page)).toBe(0);
  expect(await worldTransform(page)).toBe(activeTransform);
  expect(runtimeErrors).toEqual([]);
});

test('Rabbita edge paths preserve keyed identity and focus on selection updates', async ({ page }) => {
  await page.goto('/');
  await expect(edgePaths(page).first()).toBeVisible();
  const edge = edgePaths(page).first();
  await edge.focus();
  await expect(edge).toBeFocused();
  await edge.evaluate((node) => {
    (window as typeof window & { __canvasEdgeIdentity?: SVGPathElement }).__canvasEdgeIdentity =
      node as SVGPathElement;
  });

  await clickEdge(page, 0);
  await expect(edge).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  const identity = await edge.evaluate((node) => {
    const windowWithIdentity = window as typeof window & {
      __canvasEdgeIdentity?: SVGPathElement;
    };
    return {
      same: windowWithIdentity.__canvasEdgeIdentity === node,
      focused: document.activeElement === node,
      edgeId: node.getAttribute('data-edge-id'),
    };
  });
  expect(identity.same).toBe(true);
  expect(identity.focused).toBe(true);
  expect(identity.edgeId).toBeTruthy();
});

test('edge keyboard activation selects without actions or Space scrolling', async ({ page }) => {
  await page.goto('/');
  await expect(edgePaths(page).first()).toBeVisible();
  await expect.poll(() => loggedActions(page)).toBe(0);

  const backgroundDefaultPrevented = await page.locator('#canvas-root').evaluate((node) => {
    const event = new KeyboardEvent('keydown', {
      bubbles: true,
      cancelable: true,
      key: 'Enter',
    });
    node.dispatchEvent(event);
    return event.defaultPrevented;
  });
  expect(backgroundDefaultPrevented).toBe(false);

  const first = edgePaths(page).first();
  await first.focus();
  const unrelatedDefaultPrevented = await first.evaluate((node) => {
    const event = new KeyboardEvent('keydown', {
      bubbles: true,
      cancelable: true,
      key: 'ArrowRight',
    });
    node.dispatchEvent(event);
    return event.defaultPrevented;
  });
  expect(unrelatedDefaultPrevented).toBe(false);
  await first.evaluate((node) => {
    (window as typeof window & { __canvasKeyboardEdgeIdentity?: SVGPathElement }).__canvasKeyboardEdgeIdentity =
      node as SVGPathElement;
  });
  await page.keyboard.press('Enter');
  await expect(first).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(first).toBeFocused();
  expect(await first.evaluate((node) => {
    const windowWithIdentity = window as typeof window & {
      __canvasKeyboardEdgeIdentity?: SVGPathElement;
    };
    return windowWithIdentity.__canvasKeyboardEdgeIdentity === node;
  })).toBe(true);
  await expect.poll(() => loggedActions(page)).toBe(0);

  const second = edgePaths(page).nth(1);
  await second.focus();
  const defaultPrevented = await second.evaluate((node) => {
    const event = new KeyboardEvent('keydown', {
      bubbles: true,
      cancelable: true,
      code: 'Space',
      key: ' ',
    });
    node.dispatchEvent(event);
    return event.defaultPrevented;
  });
  expect(defaultPrevented).toBe(true);
  await expect(second).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(second).toBeFocused();
  await expect.poll(() => loggedActions(page)).toBe(0);

  const third = edgePaths(page).nth(2);
  await third.focus();
  const legacySpaceDefaultPrevented = await third.evaluate((node) => {
    const event = new KeyboardEvent('keydown', {
      bubbles: true,
      cancelable: true,
      code: 'Space',
      key: 'Spacebar',
    });
    node.dispatchEvent(event);
    return event.defaultPrevented;
  });
  expect(legacySpaceDefaultPrevented).toBe(true);
  await expect(third).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(third).toBeFocused();
  await expect.poll(() => loggedActions(page)).toBe(0);
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
  await expect(page.locator('.canvas-node').first()).toBeVisible();
  await expect(edgePaths(page)).toHaveCount(3);
  await expect(pendingEdgePaths(page)).toHaveCount(0);
  await expect(edgePaths(page).first()).toHaveAttribute('d', /^M /);
  await expect(edgePaths(page).first()).toHaveAttribute('role', 'button');
  await expect(edgePaths(page).first()).toHaveAttribute('tabindex', '0');
  await expect(edgePaths(page).first()).toHaveAttribute('data-edge-id');
  await expect(edgePaths(page).first()).toHaveAttribute('aria-label', /^Connection /);
  expect(runtimeErrors).toEqual([]);

  const source = outputHandle(page, 1);

  const ctrlClickStart = await center(source, 'node 1 output handle');
  await page.keyboard.down('Control');
  await page.mouse.move(ctrlClickStart.x, ctrlClickStart.y);
  await page.mouse.down();
  await page.mouse.up();
  await page.keyboard.up('Control');

  const cancelStart = await center(source, 'node 1 output handle');
  const cancelTarget = await canvasBackgroundPoint(page);
  await page.mouse.move(cancelStart.x, cancelStart.y);
  await page.mouse.down();
  await page.mouse.move(cancelTarget.x, cancelTarget.y, { steps: 4 });
  // The rejected Control-click publishes nothing; the completed canceled drag
  // below drains both queued gestures before these no-op assertions.
  await expect(pendingEdgePaths(page)).toHaveCount(1);
  await page.mouse.up();
  await expect(pendingEdgePaths(page)).toHaveCount(0);
  await expect(edgePaths(page)).toHaveCount(3);
  await expect.poll(() => loggedActions(page)).toBe(0);

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
  await expect(page.locator('.canvas-node').first()).toBeVisible();

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
  await expect(page.locator('.canvas-node').first()).toBeVisible();

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
  await expect(page.locator('.canvas-node').first()).toBeVisible();

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const captureIds: number[] = [];
    (window as Window & { __canopyCaptureIds?: number[] }).__canopyCaptureIds = captureIds;
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
  });

  // Rabbita drains subscription messages on a microtask; wait for the queued
  // pointer sequence before observing the imperative pointer-capture calls.
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);
  const captureIds = await page.evaluate(() => (
    (window as Window & { __canopyCaptureIds?: number[] }).__canopyCaptureIds ?? []
  ));
  expect(captureIds).toEqual([51, 53]);
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
  await expect(page.locator('.canvas-node').first()).toBeVisible();
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
  await expect.poll(() => loggedActions(page)).toBe(0);
  expect(runtimeErrors).toEqual([]);
});

test('overflowed add-node context geometry leaves state unchanged', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node').first()).toBeVisible();
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
  await expect.poll(() => loggedActions(page)).toBe(1);
  expect(runtimeErrors).toEqual([]);
});

test('invalid background context requests preserve an existing menu and state', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node').first()).toBeVisible();
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
  await expect.poll(() => loggedActions(page)).toBe(1);
  expect(runtimeErrors).toEqual([]);
});

test('finite but Float-overflowing edge anchors are rejected', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node').first()).toBeVisible();
  await expect(edgePaths(page)).toHaveCount(3);
  await dispatchContextMenu(page, '#edges path.edge', Number.MAX_VALUE, 0);

  await expect(page.locator('#context-menu [role="menu"]')).toBeHidden();
  await expect(page.locator('#edges path.edge.selected')).toHaveCount(0);
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect.poll(() => loggedActions(page)).toBe(0);
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
  await expect(page.locator('.canvas-node').first()).toBeVisible();
  await expect(edgePaths(page)).toHaveCount(3);

  const node = page.locator('.canvas-node[data-node-id="2"]');
  await node.click();
  await expect(node).toHaveClass(/(?:^|\s)selected(?:\s|$)/);

  await page.keyboard.press('Delete');
  await expect(page.locator('.canvas-node')).toHaveCount(5);
  await expect(page.locator('.canvas-node[data-node-id="2"]')).toHaveCount(0);
  await expect(edgePaths(page)).toHaveCount(1);
  await expect.poll(() => loggedActions(page)).toBe(2);
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
  await expect(page.locator('.canvas-node').first()).toBeVisible();
  await expect(edgePaths(page)).toHaveCount(3);

  const node = page.locator('.canvas-node[data-node-id="1"]');
  await node.click();
  await expect(node).toHaveClass(/(?:^|\s)selected(?:\s|$)/);

  await expect.poll(() => loggedActions(page)).toBe(1);
  await clickEdge(page, 0);
  await expect(edgePaths(page).nth(0)).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect(node).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect.poll(() => loggedActions(page)).toBe(1);

  await page.keyboard.press('Delete');
  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(edgePaths(page)).toHaveCount(2);
  await expect(page.locator('#edges path.edge.selected')).toHaveCount(0);
  await expect(node).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await expect.poll(() => loggedActions(page)).toBe(2);

  await page.keyboard.press('Delete');
  await expect(page.locator('.canvas-node')).toHaveCount(5);
  await expect(page.locator('.canvas-node[data-node-id="1"]')).toHaveCount(0);
  await expect(edgePaths(page)).toHaveCount(2);
  await expect.poll(() => loggedActions(page)).toBe(3);
  expect(runtimeErrors).toEqual([]);
});

test('Delete closes an edge context menu after deleting the captured edge', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(edgePaths(page).first()).toBeVisible();

  await clickEdge(page, 0, 'right');
  const menu = page.locator('#context-menu [role="menu"]');
  await expect(menu).toBeVisible();

  await page.keyboard.press('Delete');

  await expect(edgePaths(page)).toHaveCount(2);
  await expect(menu).toBeHidden();
  await expect.poll(() => loggedActions(page)).toBe(1);
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
  await expect.poll(() => loggedActions(page)).toBe(2);
  expect(runtimeErrors).toEqual([]);
});

test('library search and context menu insert the chosen catalog node', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  const nodes = page.locator('.canvas-node');
  const timers = nodes.filter({ has: page.locator('.node-title', { hasText: /^Timer trigger$/ }) });
  await expect(nodes.first()).toBeVisible();
  const beforeNodes = await nodes.count();
  const beforeTimers = await timers.count();
  const beforeActions = await loggedActions(page);
  const catalog = page.locator('.library-item strong');
  await expect(catalog.first()).toBeVisible();
  const unfiltered = await catalog.allTextContents();
  const search = page.getByRole('searchbox');
  await search.fill('  tImEr  ');
  await expect(catalog).toHaveText(['Timer trigger']);
  await page.getByRole('button', { name: /Timer trigger/ }).click();
  await expect(nodes).toHaveCount(beforeNodes + 1);
  await expect(timers).toHaveCount(beforeTimers + 1);
  await expect.poll(() => loggedActions(page)).toBe(beforeActions + 1);
  await search.fill('no-such-catalog-node');
  await expect(catalog).toHaveCount(0);
  await search.fill('');
  await expect(catalog).toHaveText(unfiltered);

  await openBackgroundContextMenu(page);
  const menu = page.locator('#context-menu [role="menu"]');
  await expect(menu.getByRole('menuitem', { name: 'Timer trigger' })).toHaveCount(1);
  await menu.getByRole('menuitem', { name: 'Timer trigger' }).click();

  await expect(nodes).toHaveCount(beforeNodes + 2);
  await expect(timers).toHaveCount(beforeTimers + 2);
  await expect.poll(() => loggedActions(page)).toBe(beforeActions + 2);
  expect(runtimeErrors).toEqual([]);
});

test('canvas context menu arranges a multi-selection compactly', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') {
      runtimeErrors.push(message.text());
    }
  });

  await page.goto('/');

  const first = page.locator('.canvas-node[data-node-id="1"]');
  const second = page.locator('.canvas-node[data-node-id="2"]');
  await first.click();
  await expect(first).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  await second.click({ modifiers: ['Shift'] });
  await expect(second).toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  const boundsArea = async (): Promise<number> => {
    const a = await first.boundingBox();
    const b = await second.boundingBox();
    if (!a || !b) throw new Error('selected nodes are not visible');
    return (Math.max(a.x + a.width, b.x + b.width) - Math.min(a.x, b.x))
      * (Math.max(a.y + a.height, b.y + b.height) - Math.min(a.y, b.y));
  };
  const beforeArea = await boundsArea();
  const beforeActions = await loggedActions(page);

  await openBackgroundContextMenu(page);
  const items = contextMenuItems(page);
  await expect(items.first()).toHaveText(/Arrange compactly/);
  await items.first().click();

  await expect.poll(boundsArea).toBeLessThan(beforeArea);
  const packedFirst = await first.boundingBox();
  const packedSecond = await second.boundingBox();
  if (!packedFirst || !packedSecond) throw new Error('arranged nodes are not visible');
  expect(
    packedFirst.x + packedFirst.width <= packedSecond.x
    || packedSecond.x + packedSecond.width <= packedFirst.x
    || packedFirst.y + packedFirst.height <= packedSecond.y
    || packedSecond.y + packedSecond.height <= packedFirst.y,
  ).toBe(true);
  await expect.poll(() => loggedActions(page)).toBe(beforeActions + 1);
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
  await expect(edgePaths(page).first()).toBeVisible();

  await clickEdge(page, 0, 'right');
  await page.getByRole('menuitem', { name: 'Disconnect edge' }).click();

  await expect(page.locator('.canvas-node')).toHaveCount(6);
  await expect(edgePaths(page)).toHaveCount(2);
  await expect.poll(() => loggedActions(page)).toBe(1);
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
  const nodes = page.locator('.canvas-node');
  await expect(nodes.first()).toBeVisible();
  const beforeNodes = await nodes.count();

  const menu = page.locator('#context-menu [role="menu"]');
  const canvasRoot = page.locator('#canvas-root');
  const searchInput = page.locator('#node-search');
  const items = contextMenuItems(page);

  await openBackgroundContextMenu(page);
  await expect(menu).toBeVisible();
  await expect(items.nth(0)).toHaveAttribute('data-active', 'true');
  await expect(items.nth(0)).toBeFocused();

  await page.keyboard.press('ArrowDown');
  await expect(items.nth(1)).toHaveAttribute('data-active', 'true');
  await expect(items.nth(1)).toBeFocused();

  await page.keyboard.press('End');
  await expect(items.last()).toHaveAttribute('data-active', 'true');
  await expect(items.last()).toBeFocused();

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
  await expect(nodes).toHaveCount(beforeNodes + 1);
  await expect(menu).toBeHidden();
  await expect(canvasRoot).toBeFocused();

  await openBackgroundContextMenu(page);
  await expect(items.nth(0)).toBeFocused();
  await page.keyboard.press('ArrowDown');
  await expect(items.nth(1)).toBeFocused();
  await page.keyboard.press('Space');
  await expect(nodes).toHaveCount(beforeNodes + 2);
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
  await expect.poll(() => loggedActions(page)).toBe(1);
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
  await expect(page.locator('.canvas-node').first()).toBeVisible();

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
  // Omit compatibility at the publication boundary, not in the graph model.
  await page.evaluate(() => {
    document.getElementById('canvas-render-layer')!.addEventListener(
      'canopy-canvas-render-state',
      (event) => {
        const snapshot: RenderState = JSON.parse((event as CustomEvent<string>).detail);
        snapshot.input_compatibility = [];
        Object.defineProperty(event, 'detail', { value: JSON.stringify(snapshot) });
      },
      { capture: true },
    );
  });
  await page.mouse.move(start.x + 60, start.y + 40);
  await expect(inputHandle(page, 5)).toHaveClass(/(?:^|\s)incompatible-target(?:\s|$)/);

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
  await expect(page.locator('.canvas-node').first()).toBeVisible();
  const node = page.locator('.canvas-node[data-node-id="1"]');
  const before = await node.evaluate((element) => ({
    left: (element as HTMLElement).style.left,
    top: (element as HTMLElement).style.top,
    rect: element.getBoundingClientRect().toJSON(),
  }));

  const snapshot = await page.evaluate(async () => {
    const target = document.getElementById('canvas-render-layer');
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const node = document.querySelector('.canvas-node[data-node-id="1"]');
    if (!target || !node) throw new Error('canvas render targets are missing');
    const eventName = 'canopy-canvas-render-state';
    const { promise, resolve } = Promise.withResolvers<RenderState>();
    const listener = (event: Event) => {
      target.removeEventListener(eventName, listener);
      resolve(JSON.parse((event as CustomEvent<string>).detail));
    };
    target.addEventListener(eventName, listener);
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
    return await promise;
  });

  await expect.poll(() => loggedActions(page)).toBe(0);
  await expect(node).not.toHaveClass(/(?:^|\s)selected(?:\s|$)/);
  const expectedNode = snapshot.nodes.find((candidate) => candidate.id === '1');
  if (!expectedNode) throw new Error('canceled drag snapshot is missing node 1');
  await expect.poll(() => node.evaluate((element) => ({
    left: (element as HTMLElement).style.left,
    top: (element as HTMLElement).style.top,
  }))).toEqual({
    left: `${expectedNode.x}px`,
    top: `${expectedNode.y}px`,
  });
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
  await expect(page.locator('.canvas-node').first()).toBeVisible();
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
  await expect(page.locator('.canvas-node').first()).toBeVisible();

  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const ids: number[] = [];
    (window as Window & { __canopyCaptureIds?: number[] }).__canopyCaptureIds = ids;
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
  });
  await expect(page.locator('#canvas-root')).toHaveClass(/panning/);
  const captureIds = await page.evaluate(() => (
    (window as Window & { __canopyCaptureIds?: number[] }).__canopyCaptureIds ?? []
  ));
  expect(captureIds).toEqual([81]);

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
  await expect.poll(() => loggedActions(page)).toBe(1);

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
  await expect.poll(() => loggedActions(page)).toBe(1);
  expect(runtimeErrors).toEqual([]);
});

test('canvas capture failure leaves the root session idle', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('pageerror', (error) => runtimeErrors.push(error.message));
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(message.text());
  });

  await page.goto('/');
  await expect(page.locator('.canvas-node').first()).toBeVisible();

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
  await expect.poll(() => loggedActions(page)).toBe(0);

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
  await expect(page.locator('.canvas-node').first()).toBeVisible();
  await page.evaluate(() => {
    const root = document.querySelector('#canvas-root') as HTMLDivElement;
    const node = document.querySelector('.canvas-node[data-node-id="1"]');
    const child = node?.querySelector('.node-title');
    if (!node || !child) throw new Error('canvas child target is missing');
    const ids: number[] = [];
    (window as Window & { __canopyCaptureIds?: number[] }).__canopyCaptureIds = ids;
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
  });

  await expect.poll(() => loggedActions(page)).toBe(1);
  const captureIds = await page.evaluate(() => (
    (window as Window & { __canopyCaptureIds?: number[] }).__canopyCaptureIds ?? []
  ));
  expect(captureIds).toEqual([93]);
  expect(runtimeErrors).toEqual([]);
});
