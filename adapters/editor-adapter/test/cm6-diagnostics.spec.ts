import { expect, test } from "@playwright/test";

test("renders range and point diagnostics, then clears both", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));

  await page.goto("/test/cm6-diagnostics.html");

  const result = page.locator("#result");
  await expect(result).toHaveAttribute("data-result", "markers-ready");
  await expect(page.locator(".cm-lintRange-warning")).toHaveCount(1);
  await expect(page.locator(".cm-lintPoint-error")).toHaveCount(1);

  await page.evaluate(async () => {
    const harnessWindow = window as typeof window & {
      clearCm6Diagnostics: () => Promise<void>;
    };
    await harnessWindow.clearCm6Diagnostics();
  });

  await expect(result).toHaveAttribute("data-result", "pass");
  await expect(page.locator(".cm-lintRange-warning")).toHaveCount(0);
  await expect(page.locator(".cm-lintPoint-error")).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});
