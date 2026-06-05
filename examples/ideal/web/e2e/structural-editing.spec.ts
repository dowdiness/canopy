import { test, expect } from '@playwright/test';

// The structural editing overlay requires a ProseMirror NodeSelection.
// In Structure mode, clicking on compound nodes (lambda, app, let_def) creates
// a NodeSelection, while leaf nodes (int, var) may activate inline CM6 editors
// instead. The Var node overlay test passes because var_ref nodes handle
// clicks differently from int_literal nodes (which have slider widgets).

async function setupStructureMode(page: import('@playwright/test').Page) {
  await page.goto('/');
  await page.getByRole('button', { name: 'Structure' }).click();
  await expect(page.getByLabel('Code editor')).toBeVisible();
  await page.waitForFunction(() => {
    const ce = document.querySelector('canopy-editor');
    return ce?.shadowRoot?.querySelector('.structure-block') !== null;
  }, { timeout: 10000 });
}

async function selectNodeInEditor(
  page: import('@playwright/test').Page,
  type: string,
  nth = 0,
) {
  const selectorMap: Record<string, string> = {
    int: '.structure-int_literal',
    var: '.structure-var_ref',
    lambda: '.structure-lambda',
    app: '.structure-application',
    let: '.structure-let_def',
    module: '.structure-module',
  };
  const base = selectorMap[type] ?? `.structure-${type}`;
  const coords = await page.evaluate(
    ({ base, nth }) => {
      const ce = document.querySelector('canopy-editor');
      if (!ce?.shadowRoot) return null;
      const els = ce.shadowRoot.querySelectorAll(base);
      const el = els[nth];
      if (!el) return null;
      const rect = el.getBoundingClientRect();
      return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
    },
    { base, nth },
  );
  if (!coords) throw new Error(`Node not found: ${type}[${nth}]`);
  await page.mouse.click(coords.x, coords.y);
  await page.waitForTimeout(300);
}

async function openVarActionOverlay(page: import('@playwright/test').Page) {
  await setupStructureMode(page);
  await selectNodeInEditor(page, 'var', 0);
  await page.keyboard.press('Space');
  await expect(page.locator('.action-overlay-panel')).toBeVisible({
    timeout: 5000,
  });
}

async function expectActiveActionItem(
  page: import('@playwright/test').Page,
  index: number,
) {
  const items = page.locator('.action-overlay-item');
  await expect(items.nth(index)).toHaveAttribute('data-active', 'true');
  await expect(
    page.locator('.action-overlay-item[data-active="true"]'),
  ).toHaveCount(1);
}

async function focusActionByLabel(
  page: import('@playwright/test').Page,
  label: string,
) {
  const items = page.locator('.action-overlay-item');
  const labels = (await items.locator('.action-label-text').allTextContents()).map(
    (text) => text.trim(),
  );
  const index = labels.findIndex((text) => text === label);
  expect(index).toBeGreaterThanOrEqual(0);
  for (let i = 0; i < index; i += 1) {
    await page.keyboard.press('ArrowDown');
  }
  await expectActiveActionItem(page, index);
}

test.describe('Structural Editing - Seed', () => {
  test('loads in Structure mode', async ({ page }) => {
    await setupStructureMode(page);
    // Verify structure blocks rendered
    const blockCount = await page.evaluate(() => {
      const ce = document.querySelector('canopy-editor');
      return ce?.shadowRoot?.querySelectorAll('.structure-block').length ?? 0;
    });
    expect(blockCount).toBeGreaterThan(0);
  });

  test('structure view contains expected node types', async ({ page }) => {
    await setupStructureMode(page);
    const nodeTypes = await page.evaluate(() => {
      const ce = document.querySelector('canopy-editor');
      if (!ce?.shadowRoot) return [];
      const classes = new Set<string>();
      ce.shadowRoot.querySelectorAll('[class*="structure-"]').forEach((el) => {
        el.classList.forEach((c) => {
          if (c.startsWith('structure-')) classes.add(c);
        });
      });
      return [...classes].sort();
    });
    expect(nodeTypes).toContain('structure-module');
    expect(nodeTypes).toContain('structure-lambda');
    expect(nodeTypes).toContain('structure-var_ref');
  });
});

test.describe('Structural Editing - Overlay on Var nodes', () => {
  // Var nodes reliably create NodeSelection when clicked in structure mode

  test('Space opens overlay on selected Var node', async ({ page }) => {
    await setupStructureMode(page);
    await selectNodeInEditor(page, 'var', 0);
    await page.keyboard.press('Space');
    await expect(page.locator('.action-overlay-panel')).toBeVisible({ timeout: 5000 });
    await expect(page.locator('.action-overlay-scrim')).toBeVisible();
  });

  test('overlay shows Inline and Rename for Var', async ({ page }) => {
    await setupStructureMode(page);
    await selectNodeInEditor(page, 'var', 0);
    await page.keyboard.press('Space');
    const overlay = page.locator('.action-overlay-panel');
    await expect(overlay).toBeVisible({ timeout: 5000 });
    await expect(
      overlay.locator('.action-overlay-item').filter({ hasText: 'Inline' }),
    ).toBeVisible();
    await expect(
      overlay.locator('.action-overlay-item').filter({ hasText: 'Rename' }),
    ).toBeVisible();
    await expect(
      overlay.locator('.action-overlay-item').filter({ hasText: 'Delete' }),
    ).toBeVisible();
  });

  test('Arrow keys, Home, and End move active menu item', async ({ page }) => {
    await openVarActionOverlay(page);
    const items = page.locator('.action-overlay-item');
    const count = await items.count();
    expect(count).toBeGreaterThan(1);

    await expectActiveActionItem(page, 0);
    await page.keyboard.press('ArrowDown');
    await expectActiveActionItem(page, 1);
    await page.keyboard.press('ArrowUp');
    await expectActiveActionItem(page, 0);
    await page.keyboard.press('End');
    await expectActiveActionItem(page, count - 1);
    await page.keyboard.press('Home');
    await expectActiveActionItem(page, 0);
  });

  test('Enter activates focused menu item', async ({ page }) => {
    await openVarActionOverlay(page);
    await focusActionByLabel(page, 'Rename');
    await page.keyboard.press('Enter');
    await expect(page.locator('.name-prompt-container')).toBeVisible({
      timeout: 5000,
    });
    await expect(page.locator('.name-prompt-label')).toContainText('New name');
  });

  test('Space activates focused menu item', async ({ page }) => {
    await openVarActionOverlay(page);
    await focusActionByLabel(page, 'Rename');
    await page.keyboard.press('Space');
    await expect(page.locator('.name-prompt-container')).toBeVisible({
      timeout: 5000,
    });
    await expect(page.locator('.name-prompt-label')).toContainText('New name');
  });

  test('Escape dismisses overlay', async ({ page }) => {
    await setupStructureMode(page);
    await selectNodeInEditor(page, 'var', 0);
    await page.keyboard.press('Space');
    await expect(page.locator('.action-overlay-panel')).toBeVisible({
      timeout: 5000,
    });
    await page.keyboard.press('Escape');
    await expect(page.locator('.action-overlay-panel')).not.toBeVisible();
  });

  test('clicking scrim dismisses overlay', async ({ page }) => {
    await setupStructureMode(page);
    await selectNodeInEditor(page, 'var', 0);
    await page.keyboard.press('Space');
    await expect(page.locator('.action-overlay-panel')).toBeVisible({
      timeout: 5000,
    });
    await page.locator('.action-overlay-scrim').click({ force: true });
    await expect(page.locator('.action-overlay-panel')).not.toBeVisible();
  });

  test('d key deletes selected Var node', async ({ page }) => {
    await setupStructureMode(page);
    await selectNodeInEditor(page, 'var', 0);
    await page.keyboard.press('Space');
    await expect(page.locator('.action-overlay-panel')).toBeVisible({
      timeout: 5000,
    });
    await page.keyboard.press('d');
    await expect(page.locator('.action-overlay-panel')).not.toBeVisible();
  });

  test('r key shows name prompt for Rename', async ({ page }) => {
    await setupStructureMode(page);
    await selectNodeInEditor(page, 'var', 0);
    await page.keyboard.press('Space');
    await expect(page.locator('.action-overlay-panel')).toBeVisible({
      timeout: 5000,
    });
    await page.keyboard.press('r');
    await expect(page.locator('.name-prompt-container')).toBeVisible({
      timeout: 5000,
    });
    await expect(page.locator('.name-prompt-label')).toContainText('New name');
  });

  test('empty name shows error on Rename', async ({ page }) => {
    await setupStructureMode(page);
    await selectNodeInEditor(page, 'var', 0);
    await page.keyboard.press('Space');
    await expect(page.locator('.action-overlay-panel')).toBeVisible({
      timeout: 5000,
    });
    await page.keyboard.press('r');
    await expect(page.locator('.name-prompt-input')).toBeVisible({
      timeout: 5000,
    });
    await page.locator('.name-prompt-input').focus();
    await page.keyboard.press('Enter');
    await expect(page.locator('.name-prompt-error')).toContainText('Enter a name to continue');
  });

  test('Escape cancels name prompt', async ({ page }) => {
    await setupStructureMode(page);
    await selectNodeInEditor(page, 'var', 0);
    await page.keyboard.press('Space');
    await expect(page.locator('.action-overlay-panel')).toBeVisible({
      timeout: 5000,
    });
    await page.keyboard.press('r');
    await expect(page.locator('.name-prompt-container')).toBeVisible({
      timeout: 5000,
    });
    await page.keyboard.press('Escape');
    await expect(page.locator('.action-overlay-panel')).not.toBeVisible();
  });
});
