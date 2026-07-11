// Seed test for Playwright Test Agents.
// This is the entry point referenced by the planner agent.

import { test, expect } from '@playwright/test';

test.describe('Canopy Editor', () => {
  test('seed', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle('Canopy Editor');

    // Switch to Structure mode
    await page.getByRole('button', { name: 'Structure' }).click();

    // The outline panel shows the AST tree
    await expect(page.getByLabel('AST outline')).toBeVisible();

    // The main editor area shows structured AST blocks
    await expect(page.getByLabel('Code editor')).toBeVisible();

    // Example buttons load different lambda calculus programs
    // Available: Basics, Composition, Currying, Conditional, Pipeline
  });
});
