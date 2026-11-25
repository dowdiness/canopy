import { expect, test, type Page } from "@playwright/test"
import {
  encodeStoredDocument,
  readStoredDocumentRaw,
  replaceStoreRecords,
  sourceKey,
} from "./document-store.ts"

// The production index packs heights measured by the browser. Seed storage
// before startup, then exercise the real editor, persistence and navigation.

const documents = [
  "```ts\nconst result = write_document(argument_one, argument_two, argument_three);\n```",
  "# Reading notes\n\nKeep the useful passages close.",
  "# A longer thought\n\n" + "Writing gives an idea room to grow. Keep the details that help the next reader. ".repeat(20),
  "# 買い物\n\n- 玄米\n- オリーブオイル\n- 来週のお弁当の材料",
  "# Workshop\n\n- Write the first draft\n- Share it\n- Listen",
  "# Small idea\n\nA quiet place for a thought.",
  "# Journal\n\n" + "今日は散歩の途中で考えたことを書き留める。".repeat(25),
  "# Recipe\n\n1. Warm the oven\n2. Mix the ingredients\n3. Bake",
].map((text, index) => ({
  document_id: `00000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
  text,
}))

type Box = { id: string, left: number, top: number, right: number, bottom: number }

const errors = new WeakMap<Page, string[]>()

test.beforeEach(async ({ page }) => {
  const seen: string[] = []
  errors.set(page, seen)
  page.on("pageerror", error => seen.push(error.message))
  await page.setViewportSize({ width: 1280, height: 720 })
  // Slots slide to new places; without motion, their boxes are final at once.
  await page.emulateMedia({ reducedMotion: "reduce" })
  await page.goto("/about/index.html")
  // Most recently changed first, so cards list in this order.
  await replaceStoreRecords(page, documents.map((document, index) => ({
    key: sourceKey(document.document_id),
    value: encodeStoredDocument(document, documents.length - index),
  })))
  await page.goto("/#/")
  await expect(page.locator(".grid.cards > .slot:not([hidden])")).toHaveCount(documents.length)
  await packed(page)
})

test.afterEach(async ({ page }) => {
  expect(errors.get(page)).toEqual([])
})

/** Wait until the grid shows every card, all measured. */
async function packed(page: Page) {
  await expect(page.locator(".grid.cards > .slot:not([hidden])").first()).toBeVisible()
  await expect(page.locator("#card-measure")).toHaveCount(0)
}

/** Every packed slot's box, in reading order. */
function boxes(page: Page): Promise<Box[]> {
  return page.locator(".grid.cards > .slot:not([hidden])").evaluateAll(slots => slots.map(slot => {
    const rect = slot.getBoundingClientRect()
    return {
      id: slot.firstElementChild!.id,
      left: rect.left,
      top: rect.top,
      right: rect.right,
      bottom: rect.bottom,
    }
  }))
}

/**
 * What would show a wrong packing: cards whose text overflows their slot,
 * slots taller or shorter than the card drawn in them, and slots that
 * overlap.
 */
function layoutFaults(page: Page) {
  return page.locator(".grid.cards").evaluate(grid => {
    const slots = [...grid.querySelectorAll<HTMLElement>(":scope > .slot:not([hidden])")]
    const cards = slots.map(slot => slot.firstElementChild as HTMLElement)
    const overflowing = cards
      .filter(card => card.scrollHeight > card.clientHeight + 1)
      .map(card => card.id)
    const mismatched = cards.filter((card, i) => {
      const height = card.style.height
      card.style.height = "auto"
      const natural = Math.ceil(card.getBoundingClientRect().height)
      card.style.height = height
      return Math.abs(natural - slots[i].getBoundingClientRect().height) > 1
    }).map(card => card.id)
    const rects = slots.map(slot => slot.getBoundingClientRect())
    const overlapping: string[] = []
    rects.forEach((a, i) => rects.slice(i + 1).forEach((b, j) => {
      if (a.left < b.right - 1 && b.left < a.right - 1 &&
        a.top < b.bottom - 1 && b.top < a.bottom - 1) {
        overlapping.push(`${cards[i].id}/${cards[i + 1 + j].id}`)
      }
    }))
    const narrowest = Math.min(...rects.map(rect => rect.width))
    const wide = rects.filter(rect => rect.width > narrowest * 1.5).length
    const gridRight = grid.getBoundingClientRect().right
    const outside = rects.filter(rect => rect.right > gridRight + 1).length
    return { overflowing, mismatched, overlapping, outside, wide }
  })
}

async function expectPackedWell(page: Page) {
  const faults = await layoutFaults(page)
  expect(faults).toMatchObject({ overflowing: [], mismatched: [], overlapping: [], outside: 0 })
  return faults
}

function overlap(a0: number, a1: number, b0: number, b1: number) {
  return Math.min(a1, b1) - Math.max(a0, b0) > 1
}

function focusedId(page: Page) {
  return page.evaluate(() => document.activeElement?.id ?? "")
}

/** Text the repository committed for the `index`th seeded document. */
async function savedText(page: Page, index: number) {
  const value = await readStoredDocumentRaw(page, sourceKey(documents[index].document_id))
  return JSON.parse(value as string).text
}

/** Press `key` and return the card focus moves to after the next render. */
async function pressFrom(page: Page, from: string, key: string) {
  await page.keyboard.press(key)
  await expect.poll(() => focusedId(page)).not.toBe(from)
  return focusedId(page)
}

test("cards are packed at their drawn heights, with long notes across two columns", async ({ page }) => {
  const faults = await expectPackedWell(page)
  expect(faults.wide).toBeGreaterThan(0)
})

test("a narrower window packs the cards again once the width holds still", async ({ page }) => {
  const before = await page.locator(".grid.cards").evaluate(grid => grid.style.width)
  for (const width of [1200, 1100, 1000, 900]) {
    await page.setViewportSize({ width, height: 720 })
  }
  await expect.poll(() => page.locator(".grid.cards").evaluate(grid => grid.style.width))
    .not.toBe(before)
  await packed(page)
  await expectPackedWell(page)
})

test("a search paints its matches in any case and keeps cards at their measured heights", async ({ page }) => {
  await page.locator("#document-index-search").fill("WRIT")
  await expect(page.locator(".count")).toHaveText(/^\d+ of \d+$/)
  await expect(page.locator(".grid mark")).toHaveCount(0)
  const matches = () => page.evaluate(() =>
    [...(CSS.highlights.get("document-index-match") ?? [])].map(range => range.toString()))
  await expect.poll(async () => (await matches()).length).toBeGreaterThan(1)
  const painted = await matches()
  expect(painted.length).toBeGreaterThan(1)
  expect(new Set(painted.map(match => match.toLowerCase()))).toEqual(new Set(["writ"]))
  await expectPackedWell(page)
})

test("typing a search is one Undo step, even as cards and matches come and go", async ({ page }) => {
  const search = page.locator("#document-index-search")
  const shown = page.locator(".grid.cards > .slot:not([hidden])")
  const all = await shown.count()
  await search.click()
  // Each step waits for the index to show it, so the index changes between
  // keys: the first key starts a search and paints its matches, the next
  // ones leave out cards, and the last ones match nothing.
  await search.press("w")
  await expect(page.locator(".count")).toBeVisible()
  await search.pressSequentially("rit")
  await expect.poll(() => shown.count()).toBeLessThan(all)
  await search.pressSequentially("zz")
  await expect(page.getByText("No documents contain “writzz”")).toBeVisible()

  await search.press("ControlOrMeta+Z")
  await expect(search).toHaveValue("")
  await expect(shown).toHaveCount(all)
})

test("clearing a search that matched nothing returns to the search field", async ({ page }) => {
  const count = await page.locator(".grid.cards > .slot:not([hidden])").count()
  await page.locator("#document-index-search").fill("zzz")
  await page.getByRole("button", { name: "Clear search" }).click()
  await expect(page.locator("#document-index-search")).toBeFocused()
  await expect(page.locator("#document-index-search")).toHaveValue("")
  await expect(page.locator(".grid.cards > .slot:not([hidden])")).toHaveCount(count)
})

test("a font that loads after startup measures every card again", async ({ page }) => {
  const heights = async () => (await boxes(page)).map(box => Math.round(box.bottom - box.top))
  const before = await heights()
  // A wider face at the front of the cards' family, as a late web font would
  // bring. Until it loads, the cards draw in the faces they were measured in.
  await page.evaluate(async () => {
    document.querySelector<HTMLElement>(".loomark-index")!.style.setProperty("--ui", `"Late Face", system-ui, sans-serif`)
    const face = new FontFace("Late Face", "url(./fonts/iAWriterQuattroS-Regular-2.000.woff2)")
    document.fonts.add(face)
    await face.load()
  })
  await expect.poll(heights).not.toEqual(before)
  await packed(page)
  await expectPackedWell(page)
})

test("arrow keys move to the nearest card on screen in their direction", async ({ page }) => {
  const all = await boxes(page)
  const box = (id: string) => all.find(each => each.id === id)!
  await page.locator(`[id="${all[0].id}"]`).focus()

  const first = all[0]
  const right = box(await pressFrom(page, first.id, "ArrowRight"))
  expect(right.left).toBeGreaterThanOrEqual(first.right - 1)
  expect(overlap(first.top, first.bottom, right.top, right.bottom)).toBe(true)


  // Down from every card reaches the nearest card below that shares its
  // column, or stays where no card lies below.
  for (const from of all) {
    const below = all.filter(card => card.top >= from.bottom - 1 &&
      overlap(from.left, from.right, card.left, card.right))
    const gap = Math.min(...below.map(card => card.top - from.bottom))
    const nearest = below.filter(card => card.top - from.bottom <= gap + 1).map(card => card.id)
    await page.locator(`[id="${from.id}"]`).focus()
    if (nearest.length === 0) {
      await page.keyboard.press("ArrowDown")
      await expect(page.locator(`[id="${from.id}"]`)).toBeFocused()
    } else {
      expect(nearest).toContain(await pressFrom(page, from.id, "ArrowDown"))
    }
  }

  await page.keyboard.press("End")
  await expect(page.locator(`[id="${all[all.length - 1].id}"]`)).toBeFocused()
  await page.keyboard.press("Home")
  await expect(page.locator(`[id="${first.id}"]`)).toBeFocused()
})

test("a New document left with text becomes the first card and takes focus", async ({ page }) => {
  const count = await page.locator(".grid.cards > .slot:not([hidden])").count()
  await page.locator(".grid.cards > .slot:not([hidden]) .card").first().focus()
  await page.keyboard.press("n")
  const editor = page.getByRole("textbox", { name: "Text", exact: true })
  await expect(editor).toBeFocused()
  await editor.pressSequentially("Fresh idea from the browser suite")
  await page.getByRole("button", { name: "Back to Notes", exact: true }).click()

  const firstCard = page.locator(".grid.cards > .slot:not([hidden]) .card").first()
  // Its card is drawn only once it is measured; focus waits for it.
  await expect(firstCard).toContainText("Fresh idea from the browser suite")
  await expect(firstCard).toBeFocused()
  await expect(page.locator(".grid.cards > .slot:not([hidden])")).toHaveCount(count + 1)
  await packed(page)
  await expectPackedWell(page)
})

test("an edited note slides to the front, highlighted, and keeps focus", async ({ page }) => {
  const original = page.locator(".grid.cards > .slot:not([hidden]) .card").nth(1)
  const id = await original.getAttribute("id")
  await original.click()
  const editor = page.getByRole("textbox", { name: "Text", exact: true })
  await expect(editor).toBeFocused()
  await editor.fill("# Reading notes, revised\n\nA new passage to keep.")
  // Back at once, before the edit is saved or its lead settles.
  await page.getByRole("button", { name: "Back to Notes", exact: true }).click()

  const card = page.locator(`[id="${id}"]`)
  await expect(card).toContainText("Reading notes, revised")
  await expect(card).toBeFocused()
  await expect(card).toHaveClass(/just-moved/)
  await expect(page.locator(".grid.cards > .slot:not([hidden]) .card").first()).toHaveId(id!)
  await expect(card).not.toHaveClass(/just-moved/, { timeout: 3_000 })
  await expectPackedWell(page)
})

test("a saved document emptied in the editor keeps an empty card and focus", async ({ page }) => {
  const cards = page.locator(".grid.cards > .slot:not([hidden]) .card")
  const count = await cards.count()
  const ids = await cards.evaluateAll(each => each.map(card => card.id))
  await page.locator(`[id="${ids[1]}"]`).click()
  const editor = page.getByRole("textbox", { name: "Text", exact: true })
  await expect(editor).toBeFocused()
  await editor.fill("")
  await expect.poll(() => savedText(page, 1)).toBe("")
  await page.getByRole("button", { name: "Back to Notes", exact: true }).click()

  const emptied = page.locator(`[id="${ids[1]}"]`)
  await expect(cards).toHaveCount(count)
  await expect(emptied).toHaveAccessibleName("Empty document")
  await expect(emptied).toHaveText("")
  await expect(emptied).toBeFocused()
  await expectPackedWell(page)
})

test("a card's trash button follows it in Tab order and deletes after confirmation", async ({ page }) => {
  const cards = page.locator(".grid.cards > .slot:not([hidden]) .card")
  const count = await cards.count()
  const ids = await cards.evaluateAll(each => each.map(card => card.id))
  const before = await boxes(page)
  const second = page.locator(`[id="${ids[1]}"]`)
  const trash = second.locator("..").locator(".card-delete")
  await second.focus()
  // The Tab stop, and the trash button with it, follows the focused card
  // once it is drawn.
  await expect(trash).toHaveAttribute("tabindex", "0")
  await page.keyboard.press("Tab")
  await expect(trash).toBeFocused()

  // Cancel keeps the card and returns to its button.
  await trash.press("Enter")
  const dialog = page.getByRole("alertdialog")
  await expect(dialog).toBeVisible()
  await dialog.getByRole("button", { name: "Cancel" }).click()
  await expect(page.locator("#loomark-delete-document")).toHaveCount(0)
  await expect(cards).toHaveCount(count)
  await expect(trash).toBeFocused()

  // Escape cancels as well, even after the confirmation was answered once.
  await trash.click()
  await expect(dialog).toBeVisible()
  await page.keyboard.press("Escape")
  await expect(page.locator("#loomark-delete-document")).toHaveCount(0)
  await expect(cards).toHaveCount(count)
  await expect(trash).toBeFocused()

  // Hold the real deletion transaction open, rather than depending on a
  // prototype timer to make the Pending deletion state observable.
  await page.evaluate(() => {
    const original = IDBObjectStore.prototype.delete
    IDBObjectStore.prototype.delete = function (key) {
      const request = original.call(this, key)
      let released = false
      const state = window as typeof window & { releaseIndexDelete?: () => void }
      state.releaseIndexDelete = () => { released = true }
      const keepAlive = () => {
        if (!released) this.get("__index_delete_keepalive__").onsuccess = keepAlive
      }
      keepAlive()
      return request
    }
  })
  await trash.click()
  await expect(dialog).toBeVisible()
  await dialog.getByRole("button", { name: "Delete document" }).click()
  await expect(second).toHaveAttribute("aria-disabled", "true")
  await expect(page.locator(".loomark-index").getByRole("status").filter({ hasText: "Deleting" })).toBeVisible()
  expect(await boxes(page)).toEqual(before)
  await second.click({ force: true })
  await expect(page.locator("#loomark-index")).toBeVisible()
  await page.evaluate(() => (window as typeof window & { releaseIndexDelete: () => void }).releaseIndexDelete())
  await expect(page.locator(`[id="${ids[1]}"]`)).toHaveCount(0)
  await expect(cards).toHaveCount(count - 1)
  await expect(page.locator(`[id="${ids[2]}"]`)).toBeFocused()
  await expect(page.locator(".loomark-index [aria-live=polite]")).toContainText("Document deleted")
  await packed(page)
  await expectPackedWell(page)
})
