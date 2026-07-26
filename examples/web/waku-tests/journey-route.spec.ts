import { expect, test } from '@playwright/test';

test('restores Journey reducer state after a same-document route cycle', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: /Journey Proposals/ }).click();
  await expect(page).toHaveURL(/\/journey$/);
  await expect(page.getByRole('heading', { name: 'How should this journey change?' }))
    .toBeFocused();

  await page.getByRole('radio', { name: 'Leave earlier' }).click();
  await page.getByRole('button', { name: 'Apply to itinerary' }).click();
  await expect(page.locator('#revision-label')).toHaveText('Revision 4');

  await page.getByRole('link', { name: 'Canopy home' }).click();
  await expect(page).toHaveURL(/\/$/);
  await page.getByRole('link', { name: /Journey Proposals/ }).click();

  await expect(page.locator('#revision-label')).toHaveText('Revision 4');
  await expect(page.locator('#plan-status')).toHaveText('Updated · booking unchanged');
});

test('resets Journey reducer state on full reload', async ({ page }) => {
  await page.goto('/journey');
  await page.getByRole('radio', { name: 'Leave earlier' }).click();
  await page.getByRole('button', { name: 'Apply to itinerary' }).click();
  await expect(page.locator('#revision-label')).toHaveText('Revision 4');

  await page.reload();

  await expect(page.locator('#revision-label')).toHaveText('Revision 3');
  await expect(page.locator('#plan-status')).toHaveText('Needs attention');
  await expect(page.getByRole('button', { name: 'Undo last change' })).toBeDisabled();
});

test('restores the focused Journey response on browser traversal', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: /Journey Proposals/ }).click();
  const response = page.getByRole('radio', { name: 'Stay in Okayama' });
  await response.click();
  await expect(response).toBeFocused();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await expect(page).toHaveURL(/\/journey$/);

  await expect(page.getByRole('radio', { name: 'Stay in Okayama' })).toBeFocused();
  await expect(page.getByRole('radio', { name: 'Stay in Okayama' }))
    .toHaveAttribute('aria-checked', 'true');
});

test('repeated Journey route cycles release listeners and the toast timer', async ({ page }) => {
  await page.addInitScript(() => {
    const listenerRecords: Array<{
      target: EventTarget;
      type: string;
      listener: EventListenerOrEventListenerObject;
    }> = [];
    const toastTimers = new Set<number>();
    const originalAdd = EventTarget.prototype.addEventListener;
    const originalRemove = EventTarget.prototype.removeEventListener;
    const originalSetTimeout = window.setTimeout.bind(window);
    const originalClearTimeout = window.clearTimeout.bind(window);
    const isJourneyTarget = (target: EventTarget) =>
      target instanceof Element &&
      target.closest('[data-imperative-demo-host="journey"]') !== null;

    EventTarget.prototype.addEventListener = function (type, listener, options) {
      if (listener !== null && isJourneyTarget(this)) {
        listenerRecords.push({ target: this, type, listener });
      }
      originalAdd.call(this, type, listener, options);
    };
    EventTarget.prototype.removeEventListener = function (type, listener, options) {
      const index = listener === null ? -1 : listenerRecords.findIndex(
        (record) => record.target === this && record.type === type && record.listener === listener,
      );
      if (index >= 0) listenerRecords.splice(index, 1);
      originalRemove.call(this, type, listener, options);
    };
    window.setTimeout = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
      let timer = 0;
      const wrapped = typeof handler === 'function'
        ? (...callbackArgs: unknown[]) => {
            toastTimers.delete(timer);
            return handler(...callbackArgs);
          }
        : handler;
      timer = originalSetTimeout(wrapped, timeout, ...args);
      if (timeout === 2_800) toastTimers.add(timer);
      return timer;
    }) as typeof window.setTimeout;
    window.clearTimeout = ((timer?: number) => {
      if (timer !== undefined) toastTimers.delete(timer);
      originalClearTimeout(timer);
    }) as typeof window.clearTimeout;
    Object.defineProperty(window, '__journeyResources', {
      value: {
        listenerCount: () => listenerRecords.length,
        timerCount: () => toastTimers.size,
      },
    });
  });

  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');

  for (let cycle = 0; cycle < 2; cycle += 1) {
    await page.getByRole('link', { name: /Journey Proposals/ }).click();
    await expect(page.getByRole('radio')).toHaveCount(3);
    expect(await page.evaluate(
      () => (window as unknown as {
        __journeyResources: { listenerCount(): number };
      }).__journeyResources.listenerCount(),
    )).toBeGreaterThan(0);

    if (cycle === 0) {
      await page.getByRole('radio', { name: 'Leave earlier' }).click();
      await page.getByRole('button', { name: 'Apply to itinerary' }).click();
      expect(await page.evaluate(
        () => (window as unknown as {
          __journeyResources: { timerCount(): number };
        }).__journeyResources.timerCount(),
      )).toBe(1);
    }

    await page.getByRole('link', { name: 'Canopy home' }).click();
    await expect(page).toHaveURL(/\/$/);
    expect(await page.evaluate(
      () => {
        const resources = (window as unknown as {
          __journeyResources: { listenerCount(): number; timerCount(): number };
        }).__journeyResources;
        return [resources.listenerCount(), resources.timerCount()];
      },
    )).toEqual([0, 0]);
  }
});
