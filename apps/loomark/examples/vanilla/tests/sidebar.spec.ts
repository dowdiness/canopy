import { expect, test } from "@playwright/test"

test("mobile sidebar routes child key events, wraps focus, and restores across reopen", async ({ page }) => {
  await page.goto("/")
  const trigger = page.getByRole("button", { name: "Open test navigation" })
  const dialog = page.getByRole("dialog", { name: "Test mobile navigation" })
  const close = dialog.getByRole("button", { name: "Close navigation" })
  const middle = dialog.getByRole("button", { name: "Middle action" })
  const last = dialog.getByRole("button", { name: "Last action" })
  for (let cycle = 0; cycle < 3; cycle++) {
    await trigger.press("Enter")
    await expect(dialog).toBeVisible()
    await expect(dialog).toHaveAttribute("aria-modal", "true")
    await expect.poll(() => dialog.evaluate(element => element.contains(document.activeElement))).toBe(true)
    await close.focus()
    // The key event originates at a child button, not the dialog listener root.
    await close.press("Shift+Tab")
    await expect(last).toBeFocused()
    await last.press("Tab")
    await expect(close).toBeFocused()
    await close.press("Tab")
    await expect(middle).toBeFocused() // skips the disabled button
    await middle.press("Tab")
    await expect(last).toBeFocused()
    await last.press("Escape")
    await expect(dialog).toBeHidden()
    await expect(trigger).toHaveAttribute("aria-expanded", "false")
    await expect(trigger).toBeFocused()
  }
})
