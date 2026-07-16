import { writeFile } from 'node:fs/promises';
import { test, expect, type Page } from '@playwright/test';
type GenUiSessionResult = {
  success: boolean;
  revision: number;
  mounted_ids: string[];
  error?: { code: string; message: string } | null;
};

type GenUiBrowserApi = {
  replayCandidate(candidateJson: string, capabilitiesJson: string): Promise<GenUiSessionResult>;
  replayCandidateAtRevision(
    baseRevision: number,
    candidateJson: string,
    capabilitiesJson: string,
  ): Promise<GenUiSessionResult>;
  sessionRevision(): number | null;
  resetSession(): void;
  sessionNewForTest(rootId: string): { success: boolean; handle: number; revision: number };
  sessionDisposeForTest(handle: number): void;
  asyncDriverNewForSession(sessionHandle: number, baseRevision: number): AsyncDriverStart;
}

type AsyncDriverTransition = {
  kind: string;
  reason?: string | null;
  generation_id?: number | null;
  revision?: number | null;
};

type AsyncDriverStart = {
  driver_handle: number;
  generation_id: number;
  revision: number;
};

type AsyncDriverStats = {
  abort_observed: boolean;
  commit_count: number;
};

type GenUiAsyncDriverApi = {
  asyncDriverNew(baseRevision: number): AsyncDriverStart;
  asyncDriverStart(driverHandle: number): AsyncDriverTransition & { generation_id: number };
  asyncDriverQueueChunk(
    driverHandle: number,
    generationId: number,
    baseRevision: number,
    sequence: number,
    payload: string,
  ): void;
  asyncDriverQueueFinal(
    driverHandle: number,
    generationId: number,
    baseRevision: number,
    sequence: number,
  ): void;
  asyncDriverQueueFailure(
    driverHandle: number,
    generationId: number,
    baseRevision: number,
    sequence: number,
    code: string,
    message: string,
  ): void;
  asyncDriverResolveNext(driverHandle: number): Promise<AsyncDriverTransition>;
  asyncDriverWaitNext(driverHandle: number): Promise<AsyncDriverTransition>;
  asyncDriverResolveCurrent(driverHandle: number): void;
  asyncDriverProviderNew(
    driverHandle: number,
    generationId: number,
    baseRevision: number,
    sequence: number,
  ): { provider_handle: number };
  asyncDriverProviderWait(providerHandle: number): Promise<AsyncDriverTransition>;
  asyncDriverProviderReject(providerHandle: number, code: string, message: string): void;
  asyncDriverProviderAbort(providerHandle: number): void;
  asyncDriverCancel(driverHandle: number): AsyncDriverTransition;
  asyncDriverRestart(driverHandle: number, baseRevision: number): AsyncDriverTransition & { generation_id: number };
  asyncDriverCommit(driverHandle: number, capabilitiesJson: string): GenUiSessionResult;
  asyncDriverStats(driverHandle: number): AsyncDriverStats;
  asyncDriverDispose(driverHandle: number): void;
};

type AsyncTransportResult =
  | { status: 'resolved'; value: unknown }
  | { status: 'rejected'; error: string };

declare global {
  interface Window {
    __canopyGenUiTest?: GenUiBrowserApi & GenUiAsyncDriverApi;
    __genuiPendingTransport?: Promise<AsyncTransportResult>;
  }
}

const VALID_CANDIDATE = JSON.stringify({
  type: 'component',
  name: 'stack',
  attributes: [],
  children: [{ type: 'text', value: 'Orders', attributes: [], children: [] }],
});
const VALID_CANDIDATE_CHANGED = JSON.stringify({
  type: 'component',
  name: 'stack',
  attributes: [],
  children: [
    { type: 'text', value: 'Orders', attributes: [], children: [] },
    { type: 'text', value: 'Recovery', attributes: [], children: [] },
  ],
});
const INVALID_CANDIDATE = JSON.stringify({
  type: 'raw_html',
  value: '<script>window.__unsafe = true</script>',
});
const CAPABILITIES = JSON.stringify({
  bindings: [],
  filter_operators: [],
  aggregations: [],
});

async function replayCandidate(
  page: Page,
  candidateJson: string,
  capabilitiesJson: string,
): Promise<GenUiSessionResult> {
  return page.evaluate(
    async ({ candidateJson: candidate, capabilitiesJson: capabilities }) => {
      const api = window.__canopyGenUiTest;
      if (!api) throw new Error('GenUI browser test API is unavailable');
      return api.replayCandidate(candidate, capabilities);
    },
    { candidateJson, capabilitiesJson },
  );
}

async function replayCandidateAtRevision(
  page: Page,
  baseRevision: number,
  candidateJson: string,
  capabilitiesJson: string,
): Promise<GenUiSessionResult> {
  return page.evaluate(
    async ({ baseRevision: revision, candidateJson: candidate, capabilitiesJson: capabilities }) => {
      const api = window.__canopyGenUiTest;
      if (!api) throw new Error('GenUI browser test API is unavailable');
      return api.replayCandidateAtRevision(revision, candidate, capabilities);
    },
    { baseRevision, candidateJson, capabilitiesJson },
  );
}

async function resetSession(page: Page): Promise<void> {
  await page.evaluate(() => {
    const api = window.__canopyGenUiTest;
    if (!api) throw new Error('GenUI browser test API is unavailable');
    api.resetSession();
  });
}

async function sessionRevision(page: Page): Promise<number | null> {
  return page.evaluate(() => {
    const api = window.__canopyGenUiTest;
    if (!api) throw new Error('GenUI browser test API is unavailable');
    return api.sessionRevision();
  });
}

async function setDomApplyFailure(page: Page, enabled: boolean): Promise<void> {
  await page.evaluate((shouldFail) => {
    const root = document.getElementById('html-preview');
    if (!root) throw new Error('GenUI preview root is unavailable');
    const prototype = Node.prototype as typeof Node.prototype & {
      __canopyOriginalAppendChild?: typeof Node.prototype.appendChild;
      __canopyOriginalInsertBefore?: typeof Node.prototype.insertBefore;
    };
    if (shouldFail) {
      prototype.__canopyOriginalAppendChild ??= prototype.appendChild;
      prototype.__canopyOriginalInsertBefore ??= prototype.insertBefore;
      prototype.appendChild = function <T extends Node>(child: T): T {
        if (this === root || root.contains(this)) {
          throw new Error('browser test DOM apply failure');
        }
        return prototype.__canopyOriginalAppendChild!.call(this, child) as T;
      };
      prototype.insertBefore = function <T extends Node>(child: T, reference: Node | null): T {
        if (this === root || root.contains(this)) {
          throw new Error('browser test DOM apply failure');
        }
        return prototype.__canopyOriginalInsertBefore!.call(this, child, reference) as T;
      };
    } else {
      if (prototype.__canopyOriginalAppendChild) {
        prototype.appendChild = prototype.__canopyOriginalAppendChild;
      }

      if (prototype.__canopyOriginalInsertBefore) {
        prototype.insertBefore = prototype.__canopyOriginalInsertBefore;
      }
      delete prototype.__canopyOriginalAppendChild;
      delete prototype.__canopyOriginalInsertBefore;
    }
  }, enabled);
}

async function hostState(page: Page) {
  return page.evaluate(() => ({
    filter: (document.getElementById('data-filter-input') as HTMLInputElement).value,
    selection: document.getElementById('data-selection-status')?.textContent,
    detail: document.getElementById('data-detail-name')?.textContent,
    focusedOrderId: (document.activeElement as HTMLElement | null)?.dataset.orderId ?? null,
    selectedTestId: document.querySelector<HTMLElement>('[data-testid^="order-row-"][aria-selected="true"]')?.dataset.testid ?? null,
  }));
}

async function committedMarkup(page: Page): Promise<string> {
  return page.locator('#html-preview').evaluate((root) => {
    const committed = root.querySelector(':scope > [data-node-id]');
    if (!committed) return '';
    const clone = committed.cloneNode(true) as HTMLElement;
    clone.removeAttribute('data-node-id');
    clone.querySelectorAll('[data-node-id]').forEach((node) => node.removeAttribute('data-node-id'));
    return clone.outerHTML;
  });
}

test.describe('Generative UI Demo', () => {
  test('page loads and shows initial state', async ({ page }) => {
    await page.goto('/genui.html');
    await expect(page.locator('h1')).toHaveText('Generative UI');
    await expect(page.locator('#step-num')).toHaveText('—');
  });

  test('loads preset example', async ({ page }) => {
    await page.goto('/genui.html');
    await page.locator('button[data-example="0"]').click();
    const textarea = page.locator('#source-input');
    const val = await textarea.inputValue();
    expect(val.length).toBeGreaterThan(10);
    expect(val).toContain('div');
  });

  test('renders the host-owned JSON fixture as a table', async ({ page }) => {
    await page.goto('/genui.html');
    const table = page.getByRole('table', { name: 'Orders' });
    const rows = table.locator('tbody').getByRole('row');
    await expect(rows).toHaveCount(6);
    await expect(page.getByTestId('data-row-count')).toHaveText('6');
    await expect(page.getByTestId('data-summary-count')).toHaveText('6');
    await expect(page.getByTestId('data-summary-total')).toHaveText('$6,846.50');
    await expect(page.getByTestId('data-summary-average')).toHaveText('$1,141.08');
    await expect(rows.filter({ hasText: 'Acme renewal' })).toContainText('$1,280.50');
  });

  test('renders a validated one-shot recipe and checks the development answer', async ({ page }) => {
    await page.route('**/api/genui-spike', (route) => route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        recipe: {
          kind: 'filtered_orders',
          title: 'Pending orders requiring attention',
          filter: { field: 'status', operator: 'equals', value: 'pending' },
          columns: ['id', 'name', 'amount'],
          summary: { field: 'amount', aggregation: 'sum', label: 'Pending value' },
        },
        telemetry: {
          model: 'test-model',
          elapsedMs: 12,
          promptTokens: 20,
          outputTokens: 10,
        },
      }),
    }));
    await page.goto('/genui.html');

    await page.getByRole('button', { name: 'Generate one-shot view' }).click();
    await expect(page.locator('#spike-result')).toBeVisible();
    await expect(page.locator('#spike-summary-value')).toHaveText('$2,180.00');
    await expect(page.locator('#spike-table-body').getByRole('row')).toHaveCount(2);

    await page.getByLabel('Order IDs, comma separated').fill('ord-1002, ord-1006');
    await page.getByLabel('Total amount').fill('2180');
    await page.getByRole('button', { name: 'Check development answer' }).click();
    await expect(page.locator('#spike-answer-feedback')).toContainText('Correct.');
  });

  test('filters rows while preserving a selected host-owned row', async ({ page }) => {
    await page.goto('/genui.html');
    const table = page.getByRole('table', { name: 'Orders' });
    const rows = table.locator('tbody').getByRole('row');
    await page.getByTestId('order-row-ord-1002').click();
    await expect(page.getByRole('status')).toHaveText('Selected: Northstar onboarding (ord-1002)');
    await expect(page.getByTestId('data-detail-name')).toHaveText('Northstar onboarding');
    await expect(page.getByTestId('data-detail-name')).toBeVisible();

    await page.getByLabel('Filter name, status, or ID').fill('paid');
    await expect(rows).toHaveCount(3);
    await expect(page.getByTestId('data-row-count')).toHaveText('3');
    await expect(page.getByTestId('data-summary-count')).toHaveText('3');
    await expect(page.getByTestId('data-summary-total')).toHaveText('$2,486.50');
    await expect(page.getByTestId('data-summary-average')).toHaveText('$828.83');
    await expect(page.getByRole('status')).toHaveText('Selected: Northstar onboarding (ord-1002) — hidden by filter.');

    await page.getByRole('button', { name: 'Clear filter' }).click();
    await expect(rows).toHaveCount(6);
    await expect(page.getByTestId('order-row-ord-1002')).toHaveAttribute('aria-selected', 'true');
  });

  test('preserves keyboard focus when selecting a row', async ({ page }) => {
    await page.goto('/genui.html');
    const row = page.getByTestId('order-row-ord-1003');
    await row.focus();
    await row.press('Enter');
    await expect(row).toHaveAttribute('aria-selected', 'true');
    await expect(row).toBeFocused();
    await expect(page.getByTestId('data-detail-name')).toBeVisible();
  });

  test('switches to the CSV fixture while preserving detail and selection', async ({ page }) => {
    await page.goto('/genui.html');
    await page.getByTestId('order-row-ord-1004').click();
    await expect(page.getByTestId('data-detail-id')).toHaveText('ord-1004');
    await expect(page.getByTestId('data-detail-amount')).toHaveText('$2,180.00');

    const csvSource = page.getByRole('button', { name: 'CSV fixture' });
    await csvSource.click();
    await expect(csvSource).toHaveAttribute('aria-pressed', 'true');
    await expect(page.getByRole('button', { name: 'JSON fixture' })).toHaveAttribute('aria-pressed', 'false');
    await expect(page.getByTestId('data-row-count')).toHaveText('6');
    await expect(page.getByTestId('data-detail-name')).toHaveText('Lumen migration');
    await expect(page.getByRole('status')).toHaveText('Selected: Lumen migration (ord-1004)');
  });

  test('async driver rejects cancelled late events and commits only the active generation', async ({ page }) => {
    await page.goto('/genui.html');
    await page.getByTestId('order-row-ord-1002').click();
    await page.getByLabel('Filter name, status, or ID').fill('paid');
    const beforeHostState = await hostState(page);
    const initial = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    expect(initial.success).toBe(true);
    const beforeMarkup = await committedMarkup(page);
    const beforeRevision = await page.evaluate(() => window.__canopyGenUiTest?.sessionRevision() ?? null);
    expect(beforeRevision).toBe(initial.revision);

    const start = await page.evaluate((revision) => {
      const api = window.__canopyGenUiTest;
      if (!api) throw new Error('GenUI browser test API is unavailable');
      return api.asyncDriverNew(revision);
    }, initial.revision);
    const generationA = start.generation_id;
    await page.evaluate(
      ({ handle, generationId, revision, payload }) =>
        window.__canopyGenUiTest!.asyncDriverQueueChunk(handle, generationId, revision, 0, payload),
      {
        handle: start.driver_handle,
        generationId: generationA,
        revision: initial.revision,
        payload: VALID_CANDIDATE,
      },
    );
    await page.evaluate((handle) => {
      const api = window.__canopyGenUiTest;
      if (!api) throw new Error('GenUI browser test API is unavailable');
      window.__genuiPendingTransport = api.asyncDriverWaitNext(handle).then(
        (value) => ({ status: 'resolved', value }),
        (error) => ({ status: 'rejected', error: String(error) }),
      );
    }, start.driver_handle);
    await page.evaluate(() => Promise.resolve());
    const cancelled = await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverCancel(handle), start.driver_handle);
    expect(cancelled.kind).toBe('cancelled');
    expect(await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverStats(handle), start.driver_handle)).toEqual({
      abort_observed: true,
      commit_count: 0,
    });
    const cancelledTransport = await page.evaluate(() => window.__genuiPendingTransport);
    expect(cancelledTransport?.status).toBe('rejected');
    const restarted = await page.evaluate(
      ({ handle, revision }) => window.__canopyGenUiTest!.asyncDriverRestart(handle, revision),
      { handle: start.driver_handle, revision: initial.revision },
    );
    expect(restarted.generation_id).not.toBe(generationA);

    await page.evaluate(
      ({ handle, generationId, revision, payload }) =>
        window.__canopyGenUiTest!.asyncDriverQueueChunk(handle, generationId, revision, 1, payload),
      {
        handle: start.driver_handle,
        generationId: generationA,
        revision: initial.revision,
        payload: VALID_CANDIDATE_CHANGED,
      },
    );
    const late = await page.evaluate(
      (handle) => window.__canopyGenUiTest!.asyncDriverResolveNext(handle),
      start.driver_handle,
    );
    expect(late.kind).toBe('ignored');
    expect(await page.evaluate(() => window.__canopyGenUiTest?.sessionRevision() ?? null)).toBe(beforeRevision);
    expect(await committedMarkup(page)).toBe(beforeMarkup);
    await page.evaluate(
      ({ handle, generationId, revision }) =>
        window.__canopyGenUiTest!.asyncDriverQueueFailure(
          handle,
          generationId,
          revision,
          1,
          'ProviderFailure',
          'late A failure',
        ),
      {
        handle: start.driver_handle,
        generationId: generationA,
        revision: initial.revision,
      },
    );
    const lateFailure = await page.evaluate(
      (handle) => window.__canopyGenUiTest!.asyncDriverResolveNext(handle),
      start.driver_handle,
    );
    expect(lateFailure).toEqual({
      kind: 'provider_failed',
      code: 'ProviderFailure',
      reason: 'late A failure',
    });
    expect(await page.evaluate(() => window.__canopyGenUiTest?.sessionRevision() ?? null)).toBe(beforeRevision);
    expect(await committedMarkup(page)).toBe(beforeMarkup);

    const generationB = restarted.generation_id;
    await page.evaluate(
      ({ handle, generationId, revision, payload }) =>
        window.__canopyGenUiTest!.asyncDriverQueueChunk(handle, generationId, revision, 0, payload),
      {
        handle: start.driver_handle,
        generationId: generationB,
        revision: initial.revision,
        payload: VALID_CANDIDATE_CHANGED,
      },
    );
    await page.evaluate(
      ({ handle, generationId, revision, sequence }) =>
        window.__canopyGenUiTest!.asyncDriverQueueFinal(handle, generationId, revision, sequence),
      {
        handle: start.driver_handle,
        generationId: generationB,
        revision: initial.revision,
        sequence: 1,
      },
    );
    await page.evaluate((handle) => {
      const api = window.__canopyGenUiTest;
      if (!api) throw new Error('GenUI browser test API is unavailable');
      window.__genuiPendingTransport = api.asyncDriverWaitNext(handle).then(
        (value) => ({ status: 'resolved', value }),
        (error) => ({ status: 'rejected', error: String(error) }),
      );
    }, start.driver_handle);
    await page.evaluate(() => Promise.resolve());
    await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverResolveCurrent(handle), start.driver_handle);
    const activeTransport = await page.evaluate(() => window.__genuiPendingTransport);
    expect(activeTransport).toEqual({
      status: 'resolved',
      value: { kind: 'chunk_accepted', sequence: 0 },
    });
    await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverResolveNext(handle), start.driver_handle);
    const committed = await page.evaluate(
      ({ handle, capabilities }) => window.__canopyGenUiTest!.asyncDriverCommit(handle, capabilities),
      { handle: start.driver_handle, capabilities: CAPABILITIES },
    );
    expect(committed.success).toBe(true);
    expect(committed.revision).toBe(initial.revision + 1);
    expect(await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverStats(handle), start.driver_handle)).toEqual({
      abort_observed: true,
      commit_count: 1,
    });
    expect(await committedMarkup(page)).not.toBe(beforeMarkup);
    expect(await hostState(page)).toEqual(beforeHostState);
    await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverDispose(handle), start.driver_handle);
  });

  test('duplicate async waits reject without consuming the next item', async ({ page }) => {
    await page.goto('/genui.html');
    const initial = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    expect(initial.success).toBe(true);
    const start = await page.evaluate((revision) => window.__canopyGenUiTest!.asyncDriverNew(revision), initial.revision);
    await page.evaluate(
      ({ handle, generationId, revision, payload }) =>
        window.__canopyGenUiTest!.asyncDriverQueueChunk(handle, generationId, revision, 0, payload),
      {
        handle: start.driver_handle,
        generationId: start.generation_id,
        revision: initial.revision,
        payload: VALID_CANDIDATE,
      },
    );
    await page.evaluate(
      ({ handle, generationId, revision }) =>
        window.__canopyGenUiTest!.asyncDriverQueueFinal(handle, generationId, revision, 1),
      {
        handle: start.driver_handle,
        generationId: start.generation_id,
        revision: initial.revision,
      },
    );
    await page.evaluate((handle) => {
      const api = window.__canopyGenUiTest;
      if (!api) throw new Error('GenUI browser test API is unavailable');
      window.__genuiPendingTransport = api.asyncDriverWaitNext(handle).then(
        (value) => ({ status: 'resolved', value }),
        (error) => ({ status: 'rejected', error: String(error) }),
      );
    }, start.driver_handle);
    await page.evaluate(() => Promise.resolve());
    const duplicate = await page.evaluate(async (handle) => {
      const api = window.__canopyGenUiTest;
      if (!api) throw new Error('GenUI browser test API is unavailable');
      return Promise.race([
        api.asyncDriverWaitNext(handle).then((value) => ({ status: 'resolved' as const, value })),
        new Promise<{ status: 'timeout' }>((resolve) => setTimeout(() => resolve({ status: 'timeout' }), 250)),
      ]);
    }, start.driver_handle);
    expect(duplicate).toEqual({
      status: 'resolved',
      value: { kind: 'driver_error', reason: 'async driver wait already pending' },
    });
    const cancelled = await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverCancel(handle), start.driver_handle);
    expect(cancelled.kind).toBe('cancelled');
    expect((await page.evaluate(() => window.__genuiPendingTransport))?.status).toBe('rejected');
    expect(await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverResolveNext(handle), start.driver_handle)).toEqual({
      kind: 'ignored',
      reason: 'terminal_state',
    });
    await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverDispose(handle), start.driver_handle);
  });
  test('cancelled wait continuation cannot clear a restarted wait', async ({ page }) => {
    await page.goto('/genui.html');
    const initial = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    expect(initial.success).toBe(true);
    const start = await page.evaluate((revision) => window.__canopyGenUiTest!.asyncDriverNew(revision), initial.revision);
    const race = await page.evaluate(
      async ({ handle, generationId, revision, payload }) => {
        const api = window.__canopyGenUiTest;
        if (!api) throw new Error('GenUI browser test API is unavailable');
        api.asyncDriverQueueChunk(handle, generationId, revision, 0, payload);
        const first = api.asyncDriverWaitNext(handle).then(
          (value) => ({ status: 'resolved' as const, value }),
          (error) => ({ status: 'rejected' as const, error: String(error) }),
        );
        api.asyncDriverResolveCurrent(handle);
        const cancelled = api.asyncDriverCancel(handle);
        const restarted = api.asyncDriverRestart(handle, revision);
        api.asyncDriverQueueChunk(handle, restarted.generation_id, revision, 0, payload);
        const second = api.asyncDriverWaitNext(handle).then(
          (value) => ({ status: 'resolved' as const, value }),
          (error) => ({ status: 'rejected' as const, error: String(error) }),
        );
        const firstResult = await first;
        api.asyncDriverResolveCurrent(handle);
        const secondResult = await Promise.race([
          second,
          new Promise<{ status: 'timeout' }>((resolve) => setTimeout(() => resolve({ status: 'timeout' }), 250)),
        ]);
        return { cancelled, first: firstResult, second: secondResult };
      },
      {
        handle: start.driver_handle,
        generationId: start.generation_id,
        revision: initial.revision,
        payload: VALID_CANDIDATE,
      },
    );
    expect(race.cancelled.kind).toBe('cancelled');
    expect(race.first).toEqual({
      status: 'resolved',
      value: { kind: 'ignored', reason: 'stale_generation' },
    });
    expect(race.second).toEqual({
      status: 'resolved',
      value: { kind: 'chunk_accepted', sequence: 0 },
    });
    await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverDispose(handle), start.driver_handle);
  });


  test('stale resolve continuation preserves the active wait slot', async ({ page }) => {
    await page.goto('/genui.html');
    const initial = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    expect(initial.success).toBe(true);
    const start = await page.evaluate((revision) => window.__canopyGenUiTest!.asyncDriverNew(revision), initial.revision);
    const race = await page.evaluate(
      async ({ handle, generationId, revision, payload }) => {
        const api = window.__canopyGenUiTest;
        if (!api) throw new Error('GenUI browser test API is unavailable');
        api.asyncDriverQueueChunk(handle, generationId, revision, 0, payload);
        const first = api.asyncDriverResolveNext(handle);
        const cancelled = api.asyncDriverCancel(handle);
        const restarted = api.asyncDriverRestart(handle, revision);
        api.asyncDriverQueueChunk(handle, restarted.generation_id, revision, 0, payload);
        const second = api.asyncDriverWaitNext(handle).then(
          (value) => ({ status: 'resolved' as const, value }),
          (error) => ({ status: 'rejected' as const, error: String(error) }),
        );
        const firstResult = await first;
        api.asyncDriverResolveCurrent(handle);
        const secondResult = await Promise.race([
          second,
          new Promise<{ status: 'timeout' }>((resolve) => setTimeout(() => resolve({ status: 'timeout' }), 250)),
        ]);
        return { cancelled, first: firstResult, second: secondResult };
      },
      {
        handle: start.driver_handle,
        generationId: start.generation_id,
        revision: initial.revision,
        payload: VALID_CANDIDATE,
      },
    );
    expect(race.cancelled.kind).toBe('cancelled');
    expect(race.first).toEqual({ kind: 'ignored', reason: 'stale_generation' });
    expect(race.second).toEqual({
      status: 'resolved',
      value: { kind: 'chunk_accepted', sequence: 0 },
    });
    await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverDispose(handle), start.driver_handle);
  });

  test('async provider abort resolves through the real Promise wait path', async ({ page }) => {
    await page.goto('/genui.html');
    const initial = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    expect(initial.success).toBe(true);
    const start = await page.evaluate((revision) => window.__canopyGenUiTest!.asyncDriverNew(revision), initial.revision);
    const provider = await page.evaluate(
      ({ handle, generationId, revision }) =>
        window.__canopyGenUiTest!.asyncDriverProviderNew(handle, generationId, revision, 0),
      {
        handle: start.driver_handle,
        generationId: start.generation_id,
        revision: initial.revision,
      },
    );
    await page.evaluate((providerHandle) => {
      window.__genuiPendingTransport = window.__canopyGenUiTest!.asyncDriverProviderWait(providerHandle).then(
        (value) => ({ status: 'resolved', value }),
        (error) => ({ status: 'rejected', error: String(error) }),
      );
    }, provider.provider_handle);
    await page.evaluate(() => Promise.resolve());
    await page.evaluate(
      (providerHandle) => window.__canopyGenUiTest!.asyncDriverProviderAbort(providerHandle),
      provider.provider_handle,
    );
    expect(await page.evaluate(() => window.__genuiPendingTransport)).toEqual({
      status: 'resolved',
      value: { kind: 'aborted' },
    });
    expect(await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverStats(handle), start.driver_handle)).toEqual({
      abort_observed: true,
      commit_count: 0,
    });
    await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverDispose(handle), start.driver_handle);
  });

  test('provider Promise rejection terminalizes the generation before later input', async ({ page }) => {
    await page.goto('/genui.html');
    const initial = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    expect(initial.success).toBe(true);
    const beforeMarkup = await committedMarkup(page);
    const start = await page.evaluate((revision) => window.__canopyGenUiTest!.asyncDriverNew(revision), initial.revision);
    const provider = await page.evaluate(
      ({ handle, generationId, revision }) =>
        window.__canopyGenUiTest!.asyncDriverProviderNew(handle, generationId, revision, 0),
      {
        handle: start.driver_handle,
        generationId: start.generation_id,
        revision: initial.revision,
      },
    );
    const failure = await page.evaluate(async (providerHandle) => {
      const api = window.__canopyGenUiTest!;
      const pending = api.asyncDriverProviderWait(providerHandle);
      api.asyncDriverProviderReject(providerHandle, 'quota', 'provider quota');
      return pending;
    }, provider.provider_handle);
    expect(failure).toEqual({
      kind: 'provider_failed',
      code: 'quota',
      reason: 'provider quota',
    });

    await page.evaluate(
      ({ handle, generationId, revision, payload }) =>
        window.__canopyGenUiTest!.asyncDriverQueueChunk(
          handle,
          generationId,
          revision,
          0,
          payload,
        ),
      {
        handle: start.driver_handle,
        generationId: start.generation_id,
        revision: initial.revision,
        payload: VALID_CANDIDATE_CHANGED,
      },
    );
    expect(await page.evaluate(
      (handle) => window.__canopyGenUiTest!.asyncDriverResolveNext(handle),
      start.driver_handle,
    )).toEqual({ kind: 'ignored', reason: 'terminal_state' });

    await page.evaluate(
      ({ handle, generationId, revision }) =>
        window.__canopyGenUiTest!.asyncDriverQueueFinal(
          handle,
          generationId,
          revision,
          1,
        ),
      {
        handle: start.driver_handle,
        generationId: start.generation_id,
        revision: initial.revision,
      },
    );
    expect(await page.evaluate(
      (handle) => window.__canopyGenUiTest!.asyncDriverResolveNext(handle),
      start.driver_handle,
    )).toEqual({ kind: 'ignored', reason: 'terminal_state' });

    const commit = await page.evaluate(
      ({ handle, capabilities }) => window.__canopyGenUiTest!.asyncDriverCommit(handle, capabilities),
      { handle: start.driver_handle, capabilities: CAPABILITIES },
    );
    expect(commit.success).toBe(false);
    expect(commit.revision).toBe(initial.revision);
    expect(await page.evaluate(() => window.__canopyGenUiTest?.sessionRevision() ?? null)).toBe(initial.revision);
    expect(await committedMarkup(page)).toBe(beforeMarkup);
    expect(await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverStats(handle), start.driver_handle)).toEqual({
      abort_observed: false,
      commit_count: 0,
    });
    await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverDispose(handle), start.driver_handle);
  });

  test('async provider failure cancels the generation and cannot commit', async ({ page }) => {
    await page.goto('/genui.html');
    const initial = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    expect(initial.success).toBe(true);
    const start = await page.evaluate((revision) => window.__canopyGenUiTest!.asyncDriverNew(revision), initial.revision);

    await page.evaluate(
      ({ handle, generationId, revision }) =>
        window.__canopyGenUiTest!.asyncDriverQueueFailure(
          handle,
          generationId,
          revision,
          0,
          'ProviderFailure',
          'scripted provider failure',
        ),
      {
        handle: start.driver_handle,
        generationId: start.generation_id,
        revision: initial.revision,
      },
    );
    const failure = await page.evaluate(
      (handle) => window.__canopyGenUiTest!.asyncDriverResolveNext(handle),
      start.driver_handle,
    );
    expect(failure).toEqual({
      kind: 'provider_failed',
      code: 'ProviderFailure',
      reason: 'scripted provider failure',
    });
    expect(await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverStats(handle), start.driver_handle)).toEqual({
      abort_observed: false,
      commit_count: 0,
    });
    const commit = await page.evaluate(
      ({ handle, capabilities }) => window.__canopyGenUiTest!.asyncDriverCommit(handle, capabilities),
      { handle: start.driver_handle, capabilities: CAPABILITIES },
    );
    expect(commit.success).toBe(false);
    expect(commit.revision).toBe(initial.revision);
    expect(await page.evaluate(() => window.__canopyGenUiTest?.sessionRevision() ?? null)).toBe(initial.revision);
    await page.evaluate((handle) => window.__canopyGenUiTest!.asyncDriverDispose(handle), start.driver_handle);
  });

  test('property: async drivers isolate two sessions across disposal and late events', async ({ page }) => {
    await page.goto('/genui.html');
    await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    await page.evaluate(() => {
      for (const id of ['async-root-a', 'async-root-b']) {
        const root = document.createElement('div');
        root.id = id;
        document.body.appendChild(root);
      }
    });
    const sessions = await page.evaluate(() => {
      const api = window.__canopyGenUiTest!;
      return [
        api.sessionNewForTest('async-root-a'),
        api.sessionNewForTest('async-root-b'),
      ];
    });
    const rootBeforeDispose = await page.locator('#async-root-a').innerHTML();
    expect(sessions[0].success).toBe(true);
    expect(sessions[1].success).toBe(true);
    expect(sessions[0].handle).not.toBe(sessions[1].handle);

    const drivers = await page.evaluate(
      ([first, second]) => {
        const api = window.__canopyGenUiTest!;
        return [
          api.asyncDriverNewForSession(first.handle, first.revision),
          api.asyncDriverNewForSession(second.handle, second.revision),
        ];
      },
      sessions,
    );
    expect(drivers[0].driver_handle).not.toBe(drivers[1].driver_handle);

    await page.evaluate(
      ({ driver, generationId, revision, payload }) =>
        window.__canopyGenUiTest!.asyncDriverQueueChunk(
          driver,
          generationId,
          revision,
          0,
          payload,
        ),
      {
        driver: drivers[0].driver_handle,
        generationId: drivers[0].generation_id,
        revision: sessions[0].revision,
        payload: VALID_CANDIDATE,
      },
    );
    await page.evaluate((driver) => window.__canopyGenUiTest!.asyncDriverDispose(driver), drivers[0].driver_handle);
    const lateDisposed = await page.evaluate(
      (driver) => window.__canopyGenUiTest!.asyncDriverResolveNext(driver),
      drivers[0].driver_handle,
    );
    expect(lateDisposed.kind).toBe('driver_error');

    await page.evaluate(
      ({ driver, generationId, revision, payload }) =>
        window.__canopyGenUiTest!.asyncDriverQueueChunk(
          driver,
          generationId,
          revision,
          0,
          payload,
        ),
      {
        driver: drivers[1].driver_handle,
        generationId: drivers[1].generation_id,
        revision: sessions[1].revision,
        payload: VALID_CANDIDATE,
      },
    );
    expect(await page.evaluate((driver) => window.__canopyGenUiTest!.asyncDriverResolveNext(driver), drivers[1].driver_handle)).toEqual({
      kind: 'chunk_accepted',
      sequence: 0,
    });
    await page.evaluate(
      ({ driver, generationId, revision }) =>
        window.__canopyGenUiTest!.asyncDriverQueueFinal(driver, generationId, revision, 1),
      {
        driver: drivers[1].driver_handle,
        generationId: drivers[1].generation_id,
        revision: sessions[1].revision,
      },
    );
    expect(await page.evaluate((driver) => window.__canopyGenUiTest!.asyncDriverResolveNext(driver), drivers[1].driver_handle)).toEqual({
      kind: 'finalized',
    });
    const committedB = await page.evaluate(
      ({ driver, capabilities }) => window.__canopyGenUiTest!.asyncDriverCommit(driver, capabilities),
      { driver: drivers[1].driver_handle, capabilities: CAPABILITIES },
    );
    expect(committedB.success).toBe(true);
    expect(committedB.revision).toBe(sessions[1].revision + 1);
    expect(committedB.mounted_ids.length).toBeGreaterThan(0);
    const rootsAfterCommit = await page.evaluate(() => ({
      a: document.getElementById('async-root-a')?.innerHTML ?? '',
      b: document.getElementById('async-root-b')?.innerHTML ?? '',
    }));
    expect(rootsAfterCommit.a).toBe(rootBeforeDispose);
    expect(rootsAfterCommit.b).toContain('Orders');
    expect(rootsAfterCommit.b).toContain('data-node-id');
    expect(await page.evaluate((driver) => window.__canopyGenUiTest!.asyncDriverStats(driver), drivers[1].driver_handle)).toEqual({
      abort_observed: false,
      commit_count: 1,
    });

    await page.evaluate((driver) => window.__canopyGenUiTest!.asyncDriverDispose(driver), drivers[1].driver_handle);
    await page.evaluate((handle) => window.__canopyGenUiTest!.sessionDisposeForTest(handle), sessions[0].handle);
    await page.evaluate((handle) => window.__canopyGenUiTest!.sessionDisposeForTest(handle), sessions[1].handle);
  });


  test('streaming completes and shows tree + HTML nodes', async ({ page }) => {
    test.setTimeout(60000);

    await page.goto('/genui.html');
    await page.locator('button[data-example="0"]').click();

    await page.locator('#stream-btn').click();

    // Wait for streaming complete
    await expect(page.locator('#status-bar')).toContainText('DOM nodes rendered', { timeout: 45000 });

    // Verify tree output
    const treeHtml = await page.locator('#tree-output').innerHTML();
    expect(treeHtml).toContain('node-id');
    expect(treeHtml).toContain('Root');

    // Verify HTML rendered preview shows elements
    const htmlContent = await page.locator('#html-preview').innerHTML();
    expect(htmlContent.length).toBeGreaterThan(10);
    expect(htmlContent).not.toContain('Stream JSX to see rendered output.');

    const heading = page.locator('#html-preview h1');
    const headingStyle = await heading.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        borderLeftWidth: style.borderLeftWidth,
        paddingLeft: style.paddingLeft,
      };
    });
    expect(headingStyle).toEqual({
      borderLeftWidth: '0px',
      paddingLeft: '0px',
    });
    await expect(heading).toHaveAttribute('data-node-id', /\d+/);

    // Verify DOM node count is shown
    const nodeCount = await page.locator('#html-node-count').textContent();
    expect(parseInt(nodeCount ?? '0')).toBeGreaterThan(0);
  });

  test('multiple examples produce DOM nodes', async ({ page }) => {
    test.setTimeout(90000);

    await page.goto('/genui.html');

    for (let i = 0; i < 3; i++) {
      await page.locator(`button[data-example="${i}"]`).click();
      await page.locator('#stream-btn').click();
      await expect(page.locator('#status-bar')).toContainText('DOM nodes rendered', { timeout: 45000 });
    }
  });
  test('generates and commits the constrained data candidate through the browser action', async ({ page }) => {
    await page.goto('/genui.html');
    await page.getByRole('button', { name: 'Generate candidate' }).click();
    await expect(page.locator('#status-bar')).toContainText(
      'Candidate committed through replay, validation, dry-run, and DOM apply.',
    );
    await expect(page.locator('#html-preview [data-genui-kind="stack"]')).toBeVisible();
    await expect(page.locator('#html-preview [data-genui-kind="table"]')).toHaveCount(1);
    await expect(page.locator('#html-preview')).toContainText('Orders');
  });

  test('rejects invalid candidates without changing committed preview or revision', async ({ page }) => {
    await page.goto('/genui.html');
    const accepted = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    expect(accepted.success).toBe(true);
    const beforeMarkup = await page.locator('#html-preview').innerHTML();
    const rejected = await replayCandidate(page, INVALID_CANDIDATE, CAPABILITIES);
    expect(rejected.success).toBe(false);
    expect(rejected.error?.code).toBe('CandidateValidationError');
    expect(rejected.revision).toBe(accepted.revision);
    expect(await sessionRevision(page)).toBe(accepted.revision);
    expect(await page.locator('#html-preview').innerHTML()).toBe(beforeMarkup);
  });

  test('rejects stale candidate bases without changing committed preview or revision', async ({ page }) => {
    await page.goto('/genui.html');
    const accepted = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    expect(accepted.success).toBe(true);
    const beforeMarkup = await page.locator('#html-preview').innerHTML();
    const stale = await replayCandidateAtRevision(
      page,
      accepted.revision - 1,
      VALID_CANDIDATE,
      CAPABILITIES,
    );
    expect(stale.success).toBe(false);
    expect(stale.error?.code).toBe('BaseRevisionMismatch');
    expect(stale.revision).toBe(accepted.revision);
    expect(await sessionRevision(page)).toBe(accepted.revision);
    expect(await page.locator('#html-preview').innerHTML()).toBe(beforeMarkup);
  });

  test('keeps failed DOM applies uncommitted and repairs on the next render', async ({ page }) => {
    await page.goto('/genui.html');
    await page.getByLabel('Filter name, status, or ID').fill('paid');
    const selectedRow = page.getByTestId('order-row-ord-1003');
    await selectedRow.click();
    await selectedRow.focus();
    const beforeHostState = await hostState(page);

    const accepted = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    expect(accepted.success).toBe(true);
    await setDomApplyFailure(page, true);
    let failed: GenUiSessionResult;
    try {
      failed = await replayCandidate(page, VALID_CANDIDATE_CHANGED, CAPABILITIES);
    } finally {
      await setDomApplyFailure(page, false);
    }
    expect(failed.success).toBe(false);
    expect(failed.error?.code).toBe('DomApplyError');
    expect(failed.revision).toBe(accepted.revision);
    expect(await sessionRevision(page)).toBe(accepted.revision);
    expect(await hostState(page)).toEqual(beforeHostState);

    const repaired = await replayCandidate(page, VALID_CANDIDATE_CHANGED, CAPABILITIES);
    expect(repaired.success).toBe(true);
    expect(repaired.revision).toBe(accepted.revision + 1);
    expect(await sessionRevision(page)).toBe(repaired.revision);
    await expect(page.locator('#html-preview [data-genui-kind="stack"]')).toBeVisible();
    expect(await hostState(page)).toEqual(beforeHostState);
  });

  test('replays the same candidate deterministically from fresh sessions', async ({ page }) => {
    await page.goto('/genui.html');
    const first = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    const firstMarkup = await committedMarkup(page);
    await resetSession(page);
    const second = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    const secondMarkup = await committedMarkup(page);
    expect(second.success).toBe(true);
    expect(second.success).toBe(first.success);
    expect(second.revision).toBe(first.revision);
    expect(second.mounted_ids.length).toBe(first.mounted_ids.length);
    expect(secondMarkup).toBe(firstMarkup);
  });

  test('attaches reproducible GenUI safety measurements', async ({ page }, testInfo) => {
    test.setTimeout(60000);
    await page.goto('/genui.html');
    await page.getByLabel('Filter name, status, or ID').fill('paid');
    const selectedRow = page.getByTestId('order-row-ord-1003');
    await selectedRow.click();
    await selectedRow.focus();
    const beforeHostState = await hostState(page);
    const latencySamples: Array<{ duration_ms: number; success: boolean; revision: number }> = [];
    for (let i = 0; i < 5; i += 1) {
      const sample = await page.evaluate(async ({ candidate, capabilities }) => {
        const api = window.__canopyGenUiTest;
        if (!api) throw new Error('GenUI browser test API is unavailable');
        api.resetSession();
        const start = performance.now();
        const result = await api.replayCandidate(candidate, capabilities);
        return { duration_ms: performance.now() - start, success: result.success, revision: result.revision };
      }, { candidate: VALID_CANDIDATE, capabilities: CAPABILITIES });
      latencySamples.push(sample);
    }

    let invalidRejected = 0;
    for (let i = 0; i < 3; i += 1) {
      const result = await replayCandidate(page, INVALID_CANDIDATE, CAPABILITIES);
      if (!result.success && result.error?.code === 'CandidateValidationError') invalidRejected += 1;
    }

    const currentRevision = await sessionRevision(page);
    if (currentRevision === null) throw new Error('expected a committed session revision');
    const staleBeforeRevision = currentRevision;
    const staleBeforeMarkup = await committedMarkup(page);
    let staleRejected = 0;
    for (let i = 0; i < 3; i += 1) {
      const result = await replayCandidateAtRevision(
        page,
        currentRevision - 1,
        VALID_CANDIDATE,
        CAPABILITIES,
      );
      if (!result.success && result.error?.code === 'BaseRevisionMismatch') staleRejected += 1;
    }
    const staleAfterRevision = await sessionRevision(page);
    const staleAfterMarkup = await committedMarkup(page);
    const staleStatePreserved =
      staleAfterRevision === staleBeforeRevision && staleAfterMarkup === staleBeforeMarkup;

    await setDomApplyFailure(page, true);
    let failedApply: GenUiSessionResult;
    try {
      failedApply = await replayCandidate(page, VALID_CANDIDATE_CHANGED, CAPABILITIES);
    } finally {
      await setDomApplyFailure(page, false);
    }
    const repaired = await replayCandidate(page, VALID_CANDIDATE_CHANGED, CAPABILITIES);
    const afterHostState = await hostState(page);
    const hostStateLoss = JSON.stringify(beforeHostState) === JSON.stringify(afterHostState) ? 0 : 1;
    expect(afterHostState).toEqual(beforeHostState);

    await resetSession(page);
    const deterministicFirst = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    const deterministicFirstMarkup = await committedMarkup(page);
    await resetSession(page);
    const deterministicSecond = await replayCandidate(page, VALID_CANDIDATE, CAPABILITIES);
    const deterministicSecondMarkup = await committedMarkup(page);
    const heap = await page.evaluate(() => {
      const memory = (performance as Performance & {
        memory?: { usedJSHeapSize: number; totalJSHeapSize: number; jsHeapSizeLimit: number };
      }).memory;
      return memory
        ? { available: true, used_js_heap_size: memory.usedJSHeapSize, total_js_heap_size: memory.totalJSHeapSize }
        : { available: false };
    });
    const metrics = {
      sample_counts: {
        latency: latencySamples.length,
        invalid: 3,
        stale: 3,
        dom_failure_and_repair: 1,
        deterministic_replays: 2,
      },
      latency_samples: latencySamples,
      rejection: {
        invalid_rejected: invalidRejected,
        stale_rejected: staleRejected,
        attempted: 6,
        rate: (invalidRejected + staleRejected) / 6,
      },
      stale_base_state: {
        before_revision: staleBeforeRevision,
        after_revision: staleAfterRevision,
        before_markup: staleBeforeMarkup,
        after_markup: staleAfterMarkup,
      },
      host_state: {
        before: beforeHostState,
        after: afterHostState,
      },
      dom_apply: {
        failed: {
          success: failedApply.success,
          revision: failedApply.revision,
          error_code: failedApply.error?.code ?? null,
        },
        repaired: {
          success: repaired.success,
          revision: repaired.revision,
          error_code: repaired.error?.code ?? null,
        },
      },
      repair_count:
        repaired.success &&
        !failedApply.success &&
        failedApply.error?.code === 'DomApplyError'
          ? 1
          : 0,
      zero_counts: {
        stale_candidate_commits:
          staleRejected === 3 && staleStatePreserved
            ? 0
            : 1,
        host_state_loss: hostStateLoss,
        falsely_committed_failed_apply:
          failedApply.success ||
          failedApply.error?.code !== 'DomApplyError' ||
          failedApply.revision !== currentRevision
            ? 1
            : 0,
        deterministic_replay_mismatches:
          deterministicFirst.success &&
          deterministicSecond.success &&
          deterministicFirst.revision === deterministicSecond.revision &&
          deterministicFirst.mounted_ids.length === deterministicSecond.mounted_ids.length &&
          deterministicFirstMarkup === deterministicSecondMarkup
            ? 0
            : 1,
      },
      heap,
    };
    expect(latencySamples).toHaveLength(5);
    expect(latencySamples.every((sample) => sample.success)).toBe(true);
    expect(invalidRejected).toBe(3);
    expect(staleRejected).toBe(3);
    expect(metrics.rejection.rate).toBe(1);
    expect(metrics.repair_count).toBe(1);
    const metricsPath = testInfo.outputPath('genui-safety-metrics.json');
    await writeFile(metricsPath, JSON.stringify(metrics, null, 2), 'utf8');
    await testInfo.attach('genui-safety-metrics.json', {
      path: metricsPath,
      contentType: 'application/json',
    });
    expect(metrics.zero_counts).toEqual({
      stale_candidate_commits: 0,
      host_state_loss: 0,
      falsely_committed_failed_apply: 0,
      deterministic_replay_mismatches: 0,
    });
  });

});
