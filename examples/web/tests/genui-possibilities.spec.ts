import { expect, test, type Locator, type Page } from '@playwright/test';

const prototypeUrl = process.env.GENUI_POSSIBILITIES_URL ?? '/genui-possibilities.html';

type ResponseContract = {
  name: string;
  arrival: string;
  cost: string;
  consequence: string;
  change: string;
  actionText: string;
};

const responseContracts: ResponseContract[] = [
  {
    name: 'Leave earlier',
    arrival: '16:05 today',
    cost: '¥0',
    consequence: 'Expected to run normally',
    change: 'Depart 1h 18m earlier',
    actionText: 'Apply to itinerary',
  },
  {
    name: 'Stay in Okayama',
    arrival: '09:05 tomorrow',
    cost: '+ ¥12,400',
    consequence: 'Avoids today’s ferry risk',
    change: 'Add an overnight stay',
    actionText: 'Apply to itinerary',
  },
  {
    name: 'Keep current plan',
    arrival: '18:20 today',
    cost: '¥0',
    consequence: '17:20 ferry may be cancelled',
    change: 'No itinerary change',
    actionText: 'Keep current itinerary',
  },
];

async function currentRevision(page: Page) {
  const label = await page.locator('#revision-label').textContent();
  const match = (label ?? '').match(/Revision\s+(\d+)/);
  return match ? Number(match[1]) : NaN;
}

async function itinerarySnapshot(page: Page) {
  return page.locator('#itinerary-list > li').evaluateAll((items) =>
    items.map((item) => item.textContent?.replace(/\s+/g, ' ').trim() ?? '')
  );
}

async function assertNodeSentinels(page: Page, selector: string, prefix: string) {
  const count = await page.locator(selector).count();
  for (let index = 0; index < count; index += 1) {
    await expect(page.locator(selector).nth(index)).toHaveAttribute('data-node-sentinel', `${prefix}-${index}`);
  }
}

async function markNodeSentinels(page: Page, selector: string, prefix: string) {
  await page.evaluate(
    ({ selector, prefix }) => {
      document.querySelectorAll(selector).forEach((node, index) => {
        node.setAttribute('data-node-sentinel', `${prefix}-${index}`);
      });
    },
    { selector, prefix },
  );
}

type Box = {
  left: number;
  right: number;
  top: number;
  bottom: number;
};

async function getBox(locator: Locator): Promise<Box> {
  return locator.evaluate((node: Element) => {
    const rect = node.getBoundingClientRect();
    return {
      left: rect.left,
      right: rect.right,
      top: rect.top,
      bottom: rect.bottom,
    };
  });
}

function boxesOverlap(a: Box, b: Box) {
  return a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
}

async function expectTabToFocus(page: Page, target: Locator) {
  for (let attempts = 0; attempts < 20; attempts += 1) {
    if (await target.evaluate((element) => element === document.activeElement)) {
      return;
    }
    await page.keyboard.press('Tab');
  }
  throw new Error(`Did not focus expected control after keyboard navigation`);
}

async function waitForNoOverflow(page: Page) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(0);
}

function parseCssDurationMs(value: string): number {
  return Math.max(
    ...value.split(',').map((part) => {
      const duration = part.trim();
      if (duration.endsWith('ms')) return Number(duration.slice(0, -2));
      if (duration.endsWith('s')) return Number(duration.slice(0, -1)) * 1000;
      return Number(duration);
    }),
  );
}

async function expectReducedMotionSuppressed(locator: Locator) {
  const motion = await locator.evaluate((node: Element) => {
    const nodeStyle = getComputedStyle(node);
    const htmlStyle = getComputedStyle(document.documentElement);
    return {
      transitionDuration: nodeStyle.transitionDuration,
      animationDuration: nodeStyle.animationDuration,
      scrollBehavior: htmlStyle.scrollBehavior,
    };
  });

  expect(parseCssDurationMs(motion.transitionDuration)).toBeLessThanOrEqual(0.01);
  expect(parseCssDurationMs(motion.animationDuration)).toBe(0);
  expect(motion.scrollBehavior).toBe('auto');
}


test.describe('generative itinerary decision', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(prototypeUrl);
  });

  test('focal question and decision fields are explicit and stable', async ({ page }) => {
    await expect(page.getByRole('heading', { name: 'How should this journey change?' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Compare responses' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'What would change' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Choose what happens next' })).toBeVisible();
    await expect(page.getByRole('group', { name: 'Current artifact' })).toContainText('Naoshima journey');
    await expect(page.locator('#itinerary-list')).toHaveAttribute('role', 'list');

    const responses = page.getByRole('radio');
    const applyButton = page.getByRole('button', { name: 'Apply to itinerary' });
    const undoButton = page.getByRole('button', { name: 'Undo last change' });
    const clearSelectionButton = page.getByRole('button', { name: 'Clear selection' });
    const revision = page.locator('#revision-label');
    const selectionDetail = page.locator('#selection-detail');

    await expect(responses).toHaveCount(responseContracts.length);
    await expect(applyButton).toBeDisabled();
    await expect(clearSelectionButton).toBeDisabled();
    await expect(undoButton).toBeDisabled();
    await expect(revision).toHaveText('Revision 3');
    await expect(selectionDetail).toContainText('Select a response to see exactly what would change in your itinerary.');

    for (const contract of responseContracts) {
      const row = page.getByRole('radio', { name: contract.name });
      await expect(row).toBeVisible();
      await expect(row).toHaveAttribute('aria-checked', 'false');
      await expect(row).toContainText(contract.name);
      await expect(row).toContainText(contract.consequence);
      await expect(row).toContainText(contract.arrival);
      await expect(row).toContainText(contract.cost);
      await expect(row).toContainText(contract.change);
    }
  });

  test('response radiogroup supports roving arrow-key navigation', async ({ page }) => {
    const responses = page.getByRole('radio');

    await responses.first().focus();
    await expect(responses.first()).toBeFocused();
    await page.keyboard.press('ArrowDown');

    await expect(responses.nth(1)).toBeFocused();
    await expect(responses.nth(1)).toHaveAttribute('aria-checked', 'true');
    await expect(responses.first()).toHaveAttribute('tabindex', '-1');
    await expect(responses.nth(1)).toHaveAttribute('tabindex', '0');

    await page.keyboard.press('End');
    await expect(responses.last()).toBeFocused();
    await expect(responses.last()).toHaveAttribute('aria-checked', 'true');

    await page.keyboard.press('Home');
    await expect(responses.first()).toBeFocused();
    await expect(responses.first()).toHaveAttribute('aria-checked', 'true');

    await page.keyboard.press('Space');
    await expect(responses.first()).toBeFocused();
    await expect(page.locator('#selection-detail')).toContainText('Previewing');
  });

  test('selection previews before and after values without mutating the itinerary and applies once', async ({ page }) => {
    const itinerary = page.locator('#itinerary-list > li');
    const responses = page.getByRole('radio');
    const applyButton = page.getByRole('button', { name: /(Apply to itinerary|Keep current itinerary)/i });
    const clearSelectionButton = page.getByRole('button', { name: 'Clear selection' });
    const undoButton = page.getByRole('button', { name: 'Undo last change' });
    const revisionLabel = page.locator('#revision-label');
    const selectionDetail = page.locator('#selection-detail');
    const status = page.getByRole('status');

    await expect(itinerary).toHaveCount(4);
    await expect(revisionLabel).toHaveText('Revision 3');
    await expect(applyButton).toBeDisabled();
    await expect(clearSelectionButton).toBeDisabled();
    await markNodeSentinels(page, '#itinerary-list > li', 'itinerary');
    await markNodeSentinels(page, '[role="radio"]', 'response');

    const originalItinerary = await itinerarySnapshot(page);
    const response = responses.first();
    const firstStop = itinerary.first();
    const protectedStop = itinerary.nth(3);
    await response.click();

    await expect(applyButton).toBeEnabled();
    await expect(clearSelectionButton).toBeEnabled();
    await expect(response).toHaveAttribute('aria-checked', 'true');
    await expect(selectionDetail).toContainText('Previewing');
    await expect(selectionDetail).toContainText(responseContracts[0].name);
    await expect(revisionLabel).toHaveText('Revision 3');
    await expect(page.locator('#plan-status')).toHaveText('Needs attention');
    await expect(firstStop.getByRole('group', { name: 'Current stop' })).toContainText('Kyoto Station');
    await expect(firstStop.getByRole('group', { name: 'Current stop' })).toContainText('14:10');
    await expect(firstStop.getByRole('group', { name: 'Proposed stop' })).toContainText('Kyoto Station');
    await expect(firstStop.getByRole('group', { name: 'Proposed stop' })).toContainText('12:52');
    await expect(firstStop.locator('.protected-badge')).toBeHidden();
    await expect(protectedStop).toContainText('Chichu Art Museum');
    await expect(protectedStop).toContainText('Protected');
    await expect(protectedStop).toContainText('Unchanged in preview');

    await clearSelectionButton.click();
    await expect(revisionLabel).toHaveText('Revision 3');
    await expect(response).toHaveAttribute('aria-checked', 'false');
    await expect(response).toBeFocused();
    await expect(applyButton).toBeDisabled();
    await expect(clearSelectionButton).toBeDisabled();
    await expect(selectionDetail).toContainText('Select a response to see exactly what would change in your itinerary.');
    await expect(status).toContainText('Selection cleared. Current itinerary unchanged.');
    await expect(firstStop.getByRole('group', { name: 'Current stop' })).toContainText('14:10');
    await expect(firstStop.getByRole('group', { name: 'Proposed stop' })).toBeHidden();
    await expect(protectedStop.locator('.change-note')).toBeHidden();

    await response.click();
    await applyButton.click();
    await expect(revisionLabel).toHaveText('Revision 4');
    await expect(undoButton).toBeEnabled();
    await expect(status).toContainText(`${responseContracts[0].name} applied to the itinerary.`);
    await expect(page.locator('#plan-status')).toHaveText('Updated · booking unchanged');
    await expect(firstStop.getByRole('group', { name: 'Current stop' })).toContainText('12:52');
    await expect(firstStop.getByRole('group', { name: 'Proposed stop' })).toBeHidden();
    await assertNodeSentinels(page, '#itinerary-list > li', 'itinerary');
    await assertNodeSentinels(page, '[role="radio"]', 'response');

    const undoBox = await getBox(undoButton);
    const revisionBox = await getBox(revisionLabel);
    expect(undoBox.left).toBeGreaterThan(revisionBox.left);
    expect(Math.abs(undoBox.top - revisionBox.top)).toBeLessThanOrEqual(20);

    await undoButton.click();
    await expect(revisionLabel).toHaveText('Revision 5');
    await expect(status).toContainText('Previous itinerary restored as a new revision.');
    await expect(await itinerarySnapshot(page)).toEqual(originalItinerary);
    await expect(page.locator('#plan-status')).toHaveText('Previous plan restored');
    await expect(undoButton).toBeDisabled();
    await expect(applyButton).toBeDisabled();
  });

  test('desktop responses keep decision parity with no overflow and reachable controls', async ({ page }) => {
    const itineraryRegion = page.getByRole('region', { name: 'Kyoto to Naoshima' });
    const decisionRegion = page.getByRole('region', { name: 'How should this journey change?' });
    const previewRegion = page.getByRole('region', { name: 'What would change' });
    const actionRegion = page.getByRole('region', { name: 'Choose what happens next' });
    const responses = page.getByRole('radio');
    const itinerary = itineraryRegion.getByRole('list');
    const revision = page.locator('#revision-label');
    const undoButton = page.getByRole('button', { name: 'Undo last change' });
    const compare = page.getByRole('radiogroup', { name: 'Compare responses' });
    const clearSelectionButton = page.getByRole('button', { name: 'Clear selection' });

    await waitForNoOverflow(page);
    await expect(itineraryRegion).toBeVisible();
    await expect(decisionRegion).toBeVisible();
    await expect(compare).toBeVisible();
    await expect(revision).toBeVisible();
    await expect(undoButton).toBeVisible();
    await expect(itinerary).toBeVisible();
    await expect(previewRegion).toBeVisible();
    await expect(actionRegion.getByRole('button', { name: 'Apply to itinerary' })).toBeVisible();
    await expect(clearSelectionButton).toBeVisible();

    for (let index = 0; index < responseContracts.length; index += 1) {
      const contract = responseContracts[index];
      const row = responses.nth(index);
      await expect(row).toContainText(contract.arrival);
      await expect(row).toContainText(contract.cost);
      await expect(row).toContainText(contract.consequence);
      await expect(row).toContainText(contract.change);
    }
  });

  test('tablet comparison reflows without horizontal overflow', async ({ page }) => {
    await page.setViewportSize({ width: 640, height: 900 });

    await waitForNoOverflow(page);
    await expect(page.locator('.comparison-labels')).toBeHidden();
  });

  test('mobile keeps arrival, cost, and consequence without overflow or obstruction', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });

    await waitForNoOverflow(page);

    const responses = page.getByRole('radio');
    for (let index = 0; index < responseContracts.length; index += 1) {
      const contract = responseContracts[index];
      const row = responses.nth(index);
      await expect(row).toContainText(contract.arrival);
      await expect(row).toContainText(contract.cost);
      await expect(row).toContainText(contract.consequence);
    }

    const selected = responses.first();
    const selectionDetail = page.locator('#selection-detail');
    const applyButton = page.getByRole('button', { name: /(Apply to itinerary|Keep current itinerary)/i });
    const undoButton = page.getByRole('button', { name: 'Undo last change' });
    const revisionLabel = page.locator('#revision-label');
    const clearSelectionButton = page.getByRole('button', { name: 'Clear selection' });
    await selected.click();
    await expect(selectionDetail).toContainText('Previewing');
    await expect(selectionDetail).toContainText(responseContracts[0].name);

    const selectedBox = await getBox(selected);
    const previewBox = await getBox(selectionDetail);
    const applyBox = await getBox(applyButton);
    const clearSelectionBox = await getBox(clearSelectionButton);
    const revisionBox = await getBox(revisionLabel);

    expect(boxesOverlap(applyBox, selectedBox)).toBe(false);
    expect(boxesOverlap(applyBox, previewBox)).toBe(false);
    expect(boxesOverlap(applyBox, revisionBox)).toBe(false);
    expect(boxesOverlap(clearSelectionBox, selectedBox)).toBe(false);
    expect(boxesOverlap(clearSelectionBox, previewBox)).toBe(false);
    expect(boxesOverlap(clearSelectionBox, revisionBox)).toBe(false);

    await applyButton.click();
    await expect(undoButton).toBeEnabled();
    await expect(page.getByRole('status')).toContainText(`${responseContracts[0].name} applied to the itinerary.`);
    await expect(undoButton).toBeVisible();
  });

  test('keyboard-only flow preserves authority, reversibility, and live feedback', async ({ page }) => {
    const responses = page.getByRole('radio');
    const applyButton = page.getByRole('button', { name: /(Apply to itinerary|Keep current itinerary)/i });
    const undoButton = page.getByRole('button', { name: 'Undo last change' });
    const revision = page.locator('#revision-label');

    const initialRevision = await currentRevision(page);
    await expect(revision).toHaveText(`Revision ${initialRevision}`);

    await responses.first().focus();
    await expect(responses.first()).toBeFocused();
    await expect(responses.first()).toHaveAttribute('aria-checked', 'false');
    await page.keyboard.press('ArrowDown');
    await expect(responses.nth(1)).toBeFocused();
    await page.keyboard.press('Home');
    await expect(responses.first()).toBeFocused();
    await page.keyboard.press('Space');
    await expect(applyButton).toBeEnabled();
    await expect(applyButton).toHaveAccessibleName(responseContracts[0].actionText);

    await expectTabToFocus(page, applyButton);
    await expect(applyButton).toBeFocused();
    await page.keyboard.press(' ');

    await expect(revision).toHaveText(`Revision ${initialRevision + 1}`);
    await expect(page.getByRole('status')).toContainText(`${responseContracts[0].name} applied to the itinerary.`);
    await expect(revision).toBeVisible();
    await expectTabToFocus(page, undoButton);
    await expect(undoButton).toBeFocused();
    await expect(applyButton).toBeDisabled();

    await page.keyboard.press(' ');
    await expect(revision).toHaveText(`Revision ${initialRevision + 2}`);
    await expect(page.getByRole('status')).toContainText('Previous itinerary restored as a new revision.');
    await expect(undoButton).toBeDisabled();
  });

  test('reduced-motion and forced-colors preserve decision behavior', async ({ page }) => {
    const responseName = responseContracts[2].name;
    const selectionDetail = page.locator('#selection-detail');
    const applyButton = page.getByRole('button', { name: /(Apply to itinerary|Keep current itinerary)/i });
    const undoButton = page.getByRole('button', { name: 'Undo last change' });
    const revision = page.locator('#revision-label');
    const status = page.getByRole('status');

    await page.emulateMedia({ reducedMotion: 'reduce' });
    expect(await page.evaluate(() => matchMedia('(prefers-reduced-motion: reduce)').matches)).toBe(true);
    const compactResponse = page.getByRole('radio', { name: responseName });
    await expect(compactResponse).toBeVisible();
    await expectReducedMotionSuppressed(compactResponse);

    await compactResponse.click();
    await expectReducedMotionSuppressed(compactResponse);
    await expect(selectionDetail).toContainText('Previewing');
    await expect(selectionDetail).toContainText(responseName);
    await expect(applyButton).toBeEnabled();
    const before = await currentRevision(page);
    await applyButton.click();
    await expect(revision).toHaveText(`Revision ${before + 1}`);
    await expect(status).toContainText('No booking was changed.');
    await expect(undoButton).toBeEnabled();
    await undoButton.click();
    await expect(revision).toHaveText(`Revision ${before + 2}`);

    await page.emulateMedia({ reducedMotion: 'no-preference', forcedColors: 'active', contrast: 'more' });
    await page.goto(prototypeUrl);
    expect(await page.evaluate(() => matchMedia('(forced-colors: active)').matches)).toBe(true);
    expect(await page.evaluate(() => matchMedia('(prefers-contrast: more)').matches)).toBe(true);
    const response = page.getByRole('radio', { name: responseContracts[2].name });
    await expect(response).toBeVisible();
    await response.click();
    await expect(response).toHaveAttribute('aria-checked', 'true');
    await expect(response).toContainText(responseContracts[2].consequence);
    await expect(selectionDetail).toContainText('Previewing');
    await expect(selectionDetail).toContainText(responseContracts[2].name);
    await expect(page.locator('#itinerary-list > li').nth(3)).toContainText('Protected');
    await expect(applyButton).toHaveAccessibleName(responseContracts[2].actionText);
    const highContrastRevision = await currentRevision(page);
    await applyButton.click();
    await expect(revision).toHaveText(`Revision ${highContrastRevision + 1}`);
    await expect(status).toContainText('No booking was changed.');
  });
});
