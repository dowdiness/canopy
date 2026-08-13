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
      Object.defineProperty(event, 'offsetX', { value: 100 });
      Object.defineProperty(event, 'offsetY', { value: 100 });
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
      });
      Object.defineProperty(event, 'offsetX', { value: 20 });
      Object.defineProperty(event, 'offsetY', { value: 20 });
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
      });
      Object.defineProperty(event, 'offsetX', { value: Number.NaN });
      Object.defineProperty(event, 'offsetY', { value: 10 });
      element.dispatchEvent(event);
    });
    await stage.evaluate((element) => {
      const event = new WheelEvent('wheel', {
        bubbles: true,
        deltaY: 100,
      });
      Object.defineProperty(event, 'offsetX', { value: Number.NaN });
      Object.defineProperty(event, 'offsetY', { value: 10 });
      element.dispatchEvent(event);
    });
    await expect(node).toHaveAttribute('transform', before ?? '');
    await expect(stage).not.toHaveAttribute('data-incr-active-pointer-id');
    await expect(stage).not.toHaveAttribute('data-incr-reducer-pointer-id');
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
