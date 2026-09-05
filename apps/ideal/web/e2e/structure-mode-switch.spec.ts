import { test, expect } from '@playwright/test';

// Regression for #428.
//
// Switching Text -> Structure logged
//   `RangeError: Invalid content for node module: <>`
// whenever the projection read returned "null" (a transient protected-read
// failure) and `buildDoc` fell back to an empty `module` node. The editor
// schema requires `module` content `let_def* term`, so an empty module is
// invalid and the throw aborted the whole structure mount.

// Snapshot publication matrix: activation publishes without an edit; accepted
// local/history and external refresh publish after refresh; unrelated UI and
// selection-only events do not. A snapshot supplied during runtime loading is
// the one mounted; disconnect/remount cannot mount an older host snapshot.
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

  test('Structure mounts the latest application snapshot after delayed runtime loading', async ({ page }) => {
    let release!: () => void;
    let requested!: () => void;
    const gate = new Promise<void>(resolve => { release = resolve; });
    const loading = new Promise<void>(resolve => { requested = resolve; });
    await page.route('**/src/structure-runtime.ts*', async route => {
      requested();
      await gate;
      await route.continue();
    });
    try {
      await page.goto('/');
      await page.getByRole('button', { name: 'Structure', exact: true }).click();
      await loading;
      await page.getByRole('button', { name: 'Currying', exact: true }).click();
      await expect(page.getByLabel('AST outline')).toContainText('add5');
      release();
      await expect(page.locator('canopy-editor .structure-module')).toContainText('add5');
    } finally {
      release();
    }
  });

  test('reinserting the same editor element remounts the latest Structure snapshot', async ({ page }) => {
    const room = `reinsert-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    await page.goto(`/#${room}`);
    await expect(page.getByLabel('Code editor')).toBeVisible();

    // Detach an active renderer, not just its inactive Text-mode host.
    await page.getByRole('button', { name: 'Currying', exact: true }).click();
    await page.getByRole('button', { name: 'Structure', exact: true }).click();
    await expect(page.locator('canopy-editor .structure-module')).toContainText('add5');
    await page.evaluate(() => {
      const editor = document.querySelector('canopy-editor');
      if (!editor?.parentNode) throw new Error('canopy-editor not mounted');
      const parent = editor.parentNode;
      const marker = editor.nextSibling;
      parent.removeChild(editor);
      parent.insertBefore(editor, marker);
    });

    await expect(page.locator('canopy-editor .structure-module')).toContainText('add5');
  });

  test('saved document reloads and renders in Structure mode', async ({ page }) => {
    const room = `structure-restore-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const key = `canopy-doc-${room}`;
    await page.goto(`/#${room}`);
    await expect(page.getByLabel('Code editor')).toBeVisible();
    await page.getByRole('button', { name: 'Currying', exact: true }).click();
    await expect(page.getByLabel('AST outline')).toContainText('add5');
    await expect.poll(
      () => page.evaluate(storageKey => localStorage.getItem(storageKey), key),
    ).not.toBeNull();

    await page.reload();
    await expect(page.getByLabel('Code editor')).toBeVisible();
    await page.getByRole('button', { name: 'Structure', exact: true }).click();
    await expect(page.locator('canopy-editor .structure-module')).toContainText('add5');
  });

  test('leaving Structure before runtime release does not mount a stale session', async ({ page }) => {
    let release!: () => void;
    let requested!: () => void;
    const gate = new Promise<void>(resolve => { release = resolve; });
    const loading = new Promise<void>(resolve => { requested = resolve; });
    await page.route('**/src/structure-runtime.ts*', async route => {
      requested();
      await gate;
      await route.continue();
    });
    try {
      await page.goto('/');
      await page.getByRole('button', { name: 'Structure', exact: true }).click();
      await loading;
      await page.getByRole('button', { name: 'Text', exact: true }).click();
      release();
      // Observe completion before asserting absence; checking before releasing
      // the request would pass even if the stale continuation mounted later.
      await page.evaluate(async () => { await import('/src/structure-runtime.ts'); });
      await expect(page.locator('canopy-editor .structure-block')).toHaveCount(0);
      await page.getByRole('button', { name: 'Currying', exact: true }).click();
      await page.getByRole('button', { name: 'Structure', exact: true }).click();
      await expect(page.locator('canopy-editor .structure-module')).toContainText('add5');
    } finally {
      release();
    }
  });

  test('Structure session renders the application-supplied snapshot without a CRDT getter', async ({
    page,
  }) => {
    await page.goto('/');
    const result = await page.evaluate(async () => {
      const mod = await import('/src/structure-runtime.ts');
      const parent = document.createElement('div');
      const host = document.createElement('div');
      const projection = {
        node_id: 7,
        kind: ['Int', 7],
        children: [],
        start: 0,
        end: 0,
      };
      const session = mod.createStructureModeSession(parent, host, JSON.stringify(projection));
      try {
        const initial = parent.querySelector('.structure-value')?.textContent;
        session.reconcile(JSON.stringify({ ...projection, kind: ['Int', 42] }));
        const changed = parent.querySelector('.structure-value')?.textContent;
        session.reconcile('null');
        const unavailable = parent.querySelector('.structure-value')?.textContent;
        return { initial, changed, unavailable };
      } finally {
        session.destroy();
      }
    });
    expect(result).toEqual({ initial: '7', changed: '42', unavailable: '42' });
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
