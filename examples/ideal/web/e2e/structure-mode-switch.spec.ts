import { test, expect } from '@playwright/test';

// Regression for #428.
//
// Switching Text -> Structure logged
//   `RangeError: Invalid content for node module: <>`
// whenever the projection read returned "null" (a transient protected-read
// failure) and `buildDoc` fell back to an empty `module` node. The editor
// schema requires `module` content `let_def* term`, so an empty module is
// invalid and the throw aborted the whole structure mount.

test.describe('Structure mode switch (#428)', () => {
  test('Text -> Structure renders without uncaught errors and updates inspector', async ({
    page,
  }) => {
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(String(e)));
    page.on('console', (msg) => {
      if (msg.type() === 'error') errors.push(msg.text());
    });

    await page.goto('/');
    await expect(page.getByLabel('Code editor')).toBeVisible();

    // Default mode is Text; switching to Structure mounts the ProseMirror host.
    await page.getByRole('button', { name: 'Structure' }).click();

    // The structure surface renders.
    await page.waitForFunction(
      () => {
        const ce = document.querySelector('canopy-editor');
        return ce?.shadowRoot?.querySelector('.structure-block') != null;
      },
      { timeout: 10000 },
    );

    // No RangeError / content error escaped from the structure path.
    expect(
      errors.filter((e) => /RangeError|Invalid content for node/.test(e)),
    ).toEqual([]);

    // Selecting a node still updates the inspector.
    const inspector = page.getByLabel('Node inspector');
    await expect(inspector).toBeVisible();

    const varCoords = await page.evaluate(() => {
      const ce = document.querySelector('canopy-editor');
      const el = ce?.shadowRoot?.querySelector('.structure-var_ref');
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    });
    expect(varCoords).not.toBeNull();
    await page.mouse.click(varCoords!.x, varCoords!.y);

    await expect(inspector.locator('.inspector-value').first()).toBeVisible({
      timeout: 5000,
    });
  });

  test('buildStructureDoc falls back to a schema-valid doc when the projection is unavailable', async ({
    page,
  }) => {
    await page.goto('/');
    await expect(page.getByLabel('Code editor')).toBeVisible();

    // Directly exercise the fallback path that #428 crashed on: a "null"
    // projection must yield a schema-valid document instead of throwing.
    // `editorSchema.node(...)` validates content on construction, so the
    // pre-fix empty-`module` fallback threw here; `doc.check()` re-validates.
    const result = await page.evaluate(async () => {
      const mod = await import('/src/structure-runtime.ts');
      const doc = mod.buildStructureDoc('null');
      doc.check();
      return { type: doc.type.name, childCount: doc.childCount };
    });

    expect(result.type).toBe('doc');
    expect(result.childCount).toBe(1);
  });
});
