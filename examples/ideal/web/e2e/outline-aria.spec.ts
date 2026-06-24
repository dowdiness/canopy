// E2E test: WAI-ARIA tree semantics emitted by the headless `@treeview`
// behavior (lib/treeview). The behavior's `tree_attrs` / `treeitem_attrs` return
// opaque `@html.Attrs`, so the rendered DOM is their only coverage. These tests
// pin the active-descendant tree pattern: focus stays on the container, the
// active row is tracked by `aria-activedescendant`, and rows carry
// role/level/selected/expanded.
import { test, expect } from '@playwright/test';

test.describe('Outline ARIA (treeview behavior)', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await expect(page).toHaveTitle('Canopy Editor');
    await page.getByRole('button', { name: 'Basics' }).click();
    await expect(page.getByLabel('AST outline')).toBeVisible();
  });

  function outline(page: import('@playwright/test').Page) {
    return page.getByLabel('AST outline');
  }

  test('tree container exposes role=tree and a distinct label', async ({ page }) => {
    const rows = outline(page).locator('.tree-rows');
    await expect(rows).toHaveAttribute('role', 'tree');
    // Distinct from the ancestor "AST outline" region so getByLabel stays unambiguous.
    await expect(rows).toHaveAttribute('aria-label', 'Outline tree');
    await expect(rows).toHaveAttribute('tabindex', '0');
    // getByLabel('AST outline') must still resolve to exactly one element.
    await expect(page.getByLabel('AST outline')).toHaveCount(1);
  });

  test('rows are treeitems with a 1-based aria-level', async ({ page }) => {
    const root = outline(page).locator('.tree-row').first();
    await expect(root).toHaveAttribute('role', 'treeitem');
    // depth 0 → aria-level 1 (WAI-ARIA APG is 1-based).
    await expect(root).toHaveAttribute('aria-level', '1');
  });

  test('selecting a node sets aria-selected and wires aria-activedescendant', async ({ page }) => {
    const tree = outline(page).locator('.tree-rows');
    const targetLabel = outline(page).locator('.tree-label-text', { hasText: /^module/ }).first();
    await targetLabel.click();

    const selectedRow = outline(page).locator('.tree-row.selected');
    await expect(selectedRow).toHaveAttribute('aria-selected', 'true');

    // The container's active descendant must point at the selected row's id,
    // and that id must resolve to an existing element.
    const activeId = await tree.getAttribute('aria-activedescendant');
    expect(activeId).toBeTruthy();
    const rowId = await selectedRow.getAttribute('id');
    expect(activeId).toBe(rowId);
    expect(rowId).toMatch(/^canopy-outline-treeitem-/);
  });

  test('collapse/expand hides and restores descendants with a collapsed badge', async ({ page }) => {
    // The root module node has children, so it is expandable.
    const rows = outline(page).locator('.tree-row');
    const root = rows.first();
    const descendants = outline(page).locator('.tree-row.depth-1');
    await expect(root).toHaveAttribute('aria-expanded', 'true');
    await expect(descendants).toHaveCount(3);
    await expect(root.locator('.collapsed-badge')).toHaveCount(0);
    const expandedRowCount = await rows.count();
    expect(expandedRowCount).toBeGreaterThan(1);

    // Collapse via the row's toggle button; descendants leave the DOM and the
    // badge reports the hidden direct-child count.
    await root.locator('.tree-toggle').click();
    await expect(root).toHaveAttribute('aria-expanded', 'false');
    await expect(rows).toHaveCount(1);
    await expect(descendants).toHaveCount(0);
    await expect(root.locator('.collapsed-badge')).toHaveText('3');

    // Expanding restores the original visible tree and removes the badge.
    await root.locator('.tree-toggle').click();
    await expect(root).toHaveAttribute('aria-expanded', 'true');
    await expect(rows).toHaveCount(expandedRowCount);
    await expect(descendants).toHaveCount(3);
    await expect(root.locator('.collapsed-badge')).toHaveCount(0);
  });
});
