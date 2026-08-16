import { test, expect } from '@playwright/test';

async function waitForEditorReady(page: import('@playwright/test').Page) {
  await page.goto('/');
  await expect(page).toHaveTitle('Canopy Editor');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-editor') !== null;
  }, { timeout: 10000 });
}

test.describe('Bottom panel — interactive Incr Canvas', () => {
  test('renders CellId-backed nodes and supports local drag', async ({ page }) => {
    await waitForEditorReady(page);
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'Incr Canvas' }).click();

    const panel = page.locator('#canopy-incr-canvas-container');
    await expect(panel).toBeVisible();
    const nodes = panel.locator('.incr-canvas-node');
    await expect(nodes.first()).toBeVisible({ timeout: 5000 });
    await expect(nodes).not.toHaveCount(0);

    const node = nodes.first();
    const before = await node.getAttribute('transform');
    const box = await node.boundingBox();
    expect(box).not.toBeNull();
    if (!box) return;

    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2 + 40, box.y + box.height / 2 + 12);
    await page.mouse.up();

    await expect(node).not.toHaveAttribute('transform', before ?? '');
  });

  test('claims only the first synchronous pointer gesture', async ({ page }) => {
    await waitForEditorReady(page);
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'Incr Canvas' }).click();

    const stage = page.locator('.incr-canvas-interaction');
    await expect(stage).toBeVisible({ timeout: 5000 });
    const box = await stage.boundingBox();
    expect(box).not.toBeNull();
    if (!box) return;

    await page.mouse.move(box.x + 40, box.y + 40);
    await page.mouse.down();
    const firstClaim = await stage.getAttribute('data-incr-active-pointer-id');
    expect(firstClaim).not.toBeNull();

    await stage.evaluate((element) => {
      const event = new PointerEvent('pointerdown', {
        bubbles: true,
        pointerId: 2,
        clientX: 100,
        clientY: 100,
      });
      element.dispatchEvent(event);
    });
    await expect(stage).toHaveAttribute(
      'data-incr-active-pointer-id',
      firstClaim ?? '',
    );
    await page.mouse.up();
  });

  test('recovers from lost capture before admitting the next pointer', async ({ page }) => {
    await waitForEditorReady(page);
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'Incr Canvas' }).click();

    const stage = page.locator('.incr-canvas-interaction');
    await expect(stage).toBeVisible({ timeout: 5000 });
    const box = await stage.boundingBox();
    expect(box).not.toBeNull();
    if (!box) return;

    await page.mouse.move(box.x + box.width - 20, box.y + box.height / 2);
    await page.mouse.down();
    const pointerId = await stage.getAttribute('data-incr-active-pointer-id');
    expect(pointerId).not.toBeNull();
    if (!pointerId) return;
    await expect(stage).toHaveAttribute('data-incr-reducer-pointer-id', pointerId);

    await page.waitForTimeout(50);
    await stage.evaluate((element, id) => {
      element.dispatchEvent(new PointerEvent('lostpointercapture', {
        bubbles: true,
        pointerId: Number(id),
      }));
    }, pointerId);
    await expect.poll(() => stage.getAttribute('data-incr-active-pointer-id'))
      .toBeNull();
    await expect(stage).not.toHaveAttribute('data-incr-reducer-pointer-id');
    await page.mouse.up();

    await page.mouse.down();
    const nextPointerId = await stage.getAttribute('data-incr-active-pointer-id');
    expect(nextPointerId).not.toBeNull();
    await expect(stage).toHaveAttribute(
      'data-incr-reducer-pointer-id',
      nextPointerId ?? '',
    );
    await stage.evaluate((element) => {
      element.dispatchEvent(new PointerEvent('lostpointercapture', {
        bubbles: true,
        pointerId: 999,
      }));
    });
    await expect(stage).toHaveAttribute(
      'data-incr-reducer-pointer-id',
      nextPointerId ?? '',
    );
    await page.mouse.up();
  });

  test('rejects a DOM pointer-capture failure before entering the reducer', async ({ page }) => {
    await waitForEditorReady(page);
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'Incr Canvas' }).click();

    const stage = page.locator('.incr-canvas-interaction');
    await expect(stage).toBeVisible({ timeout: 5000 });
    await stage.evaluate((element) => {
      element.setPointerCapture = () => {
        throw new DOMException('pointer is no longer active', 'NotFoundError');
      };
      const event = new PointerEvent('pointerdown', {
        bubbles: true,
        pointerId: 92,
        clientX: 20,
        clientY: 20,
      });
      element.dispatchEvent(event);
    });

    await expect(stage).not.toHaveAttribute('data-incr-active-pointer-id');
    await expect(stage).not.toHaveAttribute('data-incr-reducer-pointer-id');
  });

  test('rejects non-finite browser geometry without moving the graph', async ({ page }) => {
    await waitForEditorReady(page);
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'Incr Canvas' }).click();

    const panel = page.locator('#canopy-incr-canvas-container');
    const node = panel.locator('.incr-canvas-node').first();
    const stage = panel.locator('.incr-canvas-interaction');
    await expect(node).toBeVisible({ timeout: 5000 });
    const before = await node.getAttribute('transform');

    await stage.evaluate((element) => {
      const event = new PointerEvent('pointerdown', {
        bubbles: true,
        pointerId: 91,
        clientX: 0,
        clientY: 10,
      });
      Object.defineProperty(event, 'clientX', { value: Number.NaN });
      element.dispatchEvent(event);
    });
    await stage.evaluate((element) => {
      const event = new WheelEvent('wheel', {
        bubbles: true,
        deltaY: 100,
        clientX: 0,
        clientY: 10,
      });
      Object.defineProperty(event, 'clientX', { value: Number.NaN });
      element.dispatchEvent(event);
    });
    await expect(node).toHaveAttribute('transform', before ?? '');
    await expect(stage).not.toHaveAttribute('data-incr-active-pointer-id');
    await expect(stage).not.toHaveAttribute('data-incr-reducer-pointer-id');
  });

  test('keeps fractional root coordinates and currentTarget origin stable', async ({ page }) => {
    const openCanvas = async () => {
      await page.reload();
      await expect(page.getByRole('button', { name: 'Panels' })).toBeVisible();
      await page.getByRole('button', { name: 'Panels' }).click();
      await page.getByRole('tab', { name: 'Incr Canvas' }).click();
      const stage = page.locator('.incr-canvas-interaction');
      const node = page.locator('#canopy-incr-canvas-container .incr-canvas-node').first();
      await expect(stage).toBeVisible({ timeout: 5000 });
      await expect(node).toBeVisible({ timeout: 5000 });
      return { stage, node };
    };

    await waitForEditorReady(page);
    const first = await openCanvas();
    const firstBox = await first.stage.boundingBox();
    expect(firstBox).not.toBeNull();
    if (!firstBox) return;
    const fractional = {
      x: firstBox.x + 20.25,
      y: firstBox.y + 20.75,
    };
    const child = first.stage.locator('.incr-canvas-svg-host');
    const beforeChild = await first.node.getAttribute('transform');
    await child.evaluate((element, point) => {
      const event = new WheelEvent('wheel', {
        bubbles: true,
        deltaY: -120,
        clientX: 0,
        clientY: 0,
      });
      Object.defineProperty(event, 'clientX', { value: point.x });
      Object.defineProperty(event, 'clientY', { value: point.y });
      element.dispatchEvent(event);
    }, fractional);
    await expect(first.node).not.toHaveAttribute('transform', beforeChild ?? '');
    const childTransform = await first.node.getAttribute('transform');

    const second = await openCanvas();
    const beforeRoot = await second.node.getAttribute('transform');
    await second.stage.evaluate((element, point) => {
      const event = new WheelEvent('wheel', {
        bubbles: true,
        deltaY: -120,
        clientX: 0,
        clientY: 0,
      });
      Object.defineProperty(event, 'clientX', { value: point.x });
      Object.defineProperty(event, 'clientY', { value: point.y });
      element.dispatchEvent(event);
    }, fractional);
    await expect(second.node).not.toHaveAttribute('transform', beforeRoot ?? '');
    expect(await second.node.getAttribute('transform')).toBe(childTransform);

    const third = await openCanvas();
    const beforeRounded = await third.node.getAttribute('transform');
    const rounded = { x: Math.round(fractional.x), y: Math.round(fractional.y) };
    await third.stage.evaluate((element, point) => {
      const event = new WheelEvent('wheel', {
        bubbles: true,
        deltaY: -120,
        clientX: 0,
        clientY: 0,
      });
      Object.defineProperty(event, 'clientX', { value: point.x });
      Object.defineProperty(event, 'clientY', { value: point.y });
      element.dispatchEvent(event);
    }, rounded);
    await expect(third.node).not.toHaveAttribute('transform', beforeRounded ?? '');
    expect(await third.node.getAttribute('transform')).not.toBe(childTransform);
  });

  test('replaces raw SVG panels cleanly when switching tabs', async ({ page }) => {
    await waitForEditorReady(page);
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'Incr Graph' }).click();
    await expect(page.locator('#canopy-incr-container svg')).toHaveCount(1, {
      timeout: 5000,
    });

    await page.getByRole('tab', { name: 'Incr Canvas' }).click();
    await expect(page.locator('#canopy-incr-canvas-container')).toBeVisible();
    await expect(page.locator('#canopy-incr-container')).toHaveCount(0);

    await page.getByRole('tab', { name: 'Incr Graph' }).click();
    await expect(page.locator('#canopy-incr-container svg')).toHaveCount(1, {
      timeout: 5000,
    });
    await expect(page.locator('#canopy-incr-canvas-container')).toHaveCount(0);
  });

  test('normalizes wheel units and ignores zero or active input', async ({ page }) => {
    const openCanvas = async () => {
      await page.reload();
      await expect(page.getByRole('button', { name: 'Panels' })).toBeVisible();
      await page.getByRole('button', { name: 'Panels' }).click();
      await page.getByRole('tab', { name: 'Incr Canvas' }).click();
      const stage = page.locator('.incr-canvas-interaction');
      const node = page.locator('#canopy-incr-canvas-container .incr-canvas-node').first();
      await expect(stage).toBeVisible({ timeout: 5000 });
      await expect(node).toBeVisible({ timeout: 5000 });
      return { stage, node };
    };

    const dispatchWheel = async (
      stage: import('@playwright/test').Locator,
      deltaY: number,
      deltaMode: number,
    ) => {
      await stage.evaluate((element, values) => {
        const rect = element.getBoundingClientRect();
        element.dispatchEvent(new WheelEvent('wheel', {
          bubbles: true,
          deltaY: values.deltaY,
          deltaMode: values.deltaMode,
          clientX: rect.left + 80,
          clientY: rect.top + 60,
        }));
      }, { deltaY, deltaMode });
    };

    await waitForEditorReady(page);
    const first = await openCanvas();
    const initial = await first.node.getAttribute('transform');
    await dispatchWheel(first.stage, 0, 0);
    await expect(first.node).toHaveAttribute('transform', initial ?? '');
    await dispatchWheel(first.stage, -50, 0);
    await expect(first.node).not.toHaveAttribute('transform', initial ?? '');
    const pixel = await first.node.getAttribute('transform');

    const second = await openCanvas();
    await dispatchWheel(second.stage, -2, 1);
    await expect(second.node).toHaveAttribute('transform', pixel ?? '');

    const third = await openCanvas();
    const beforeActive = await third.node.getAttribute('transform');
    const stageBox = await third.stage.boundingBox();
    expect(stageBox).not.toBeNull();
    if (!stageBox) return;
    await page.mouse.move(stageBox.x + stageBox.width - 24, stageBox.y + 120);
    await page.mouse.down();
    await dispatchWheel(third.stage, -100, 0);
    await expect(third.node).toHaveAttribute('transform', beforeActive ?? '');
    await page.mouse.up();
  });

  test('supports background pan and anchor zoom without changing graph identity', async ({
    page,
  }) => {
    await waitForEditorReady(page);
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'Incr Canvas' }).click();

    const panel = page.locator('#canopy-incr-canvas-container');
    const stage = panel.locator('.incr-canvas-interaction');
    const node = panel.locator('.incr-canvas-node').first();
    await expect(node).toBeVisible({ timeout: 5000 });
    const before = await node.getAttribute('transform');
    const cellId = await node.getAttribute('data-cell-id');
    const stageBox = await stage.boundingBox();
    expect(stageBox).not.toBeNull();
    if (!stageBox) return;

    await page.mouse.move(stageBox.x + stageBox.width - 24, stageBox.y + 120);
    await page.mouse.down();
    await page.mouse.move(stageBox.x + stageBox.width - 4, stageBox.y + 120);
    await page.mouse.up();
    await expect(node).not.toHaveAttribute('transform', before ?? '');

    const afterPan = await node.getAttribute('transform');
    await page.mouse.wheel(0, -120);
    await expect(node).not.toHaveAttribute('transform', afterPan ?? '');
    await expect(node).toHaveAttribute('data-cell-id', cellId ?? '');
  });
});
