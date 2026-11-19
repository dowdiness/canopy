import { expect, test, type Page } from "@playwright/test"

// The note index prototype (apps/loomark/examples/note_index). Cards are
// packed from heights the browser measured, so these checks compare the
// packed slots with the cards the browser actually draws.

type Box = { id: string, left: number, top: number, right: number, bottom: number }

const errors = new WeakMap<Page, string[]>()

test.beforeEach(async ({ page }) => {
  const seen: string[] = []
  errors.set(page, seen)
  page.on("pageerror", error => seen.push(error.message))
  await page.setViewportSize({ width: 1280, height: 720 })
  // Slots slide to new places; without motion, their boxes are final at once.
  await page.emulateMedia({ reducedMotion: "reduce" })
  await page.goto("/#/")
  await packed(page)
})

test.afterEach(async ({ page }) => {
  expect(errors.get(page)).toEqual([])
})

/** Wait until the grid shows every card, all measured. */
async function packed(page: Page) {
  await expect(page.locator(".grid.cards > .slot").first()).toBeVisible()
  await expect(page.locator("#card-measure")).toHaveCount(0)
}

/** Every packed slot's box, in reading order. */
function boxes(page: Page): Promise<Box[]> {
  return page.locator(".grid.cards > .slot").evaluateAll(slots => slots.map(slot => {
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
    const slots = [...grid.querySelectorAll<HTMLElement>(":scope > .slot")]
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

test("a search marks its matches in any case and keeps cards at their measured heights", async ({ page }) => {
  await page.locator("#search").fill("WRIT")
  await expect(page.locator(".count")).toHaveText(/^\d+ of \d+$/)
  const marks = await page.locator(".grid mark").allTextContents()
  expect(marks.length).toBeGreaterThan(1)
  expect(new Set(marks.map(mark => mark.toLowerCase()))).toEqual(new Set(["writ"]))
  await expectPackedWell(page)
})

test("clearing a search that matched nothing returns to the search field", async ({ page }) => {
  const count = await page.locator(".grid.cards > .slot").count()
  await page.locator("#search").fill("zzz")
  await page.getByRole("button", { name: "Clear search" }).click()
  await expect(page.locator("#search")).toBeFocused()
  await expect(page.locator("#search")).toHaveValue("")
  await expect(page.locator(".grid.cards > .slot")).toHaveCount(count)
})

test("a font that loads after startup measures every card again", async ({ page }) => {
  const heights = async () => (await boxes(page)).map(box => Math.round(box.bottom - box.top))
  const before = await heights()
  // A wider face under the cards' family, as a late web font would bring.
  await page.evaluate(async () => {
    const face = new FontFace("iA Writer Quattro", "url(./fonts/IBMPlexSansJP-Regular-1.004.woff2)")
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
  await page.locator(`#${all[0].id}`).focus()

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
    await page.locator(`#${from.id}`).focus()
    if (nearest.length === 0) {
      await page.keyboard.press("ArrowDown")
      await expect(page.locator(`#${from.id}`)).toBeFocused()
    } else {
      expect(nearest).toContain(await pressFrom(page, from.id, "ArrowDown"))
    }
  }

  await page.keyboard.press("End")
  await expect(page.locator(`#${all[all.length - 1].id}`)).toBeFocused()
  await page.keyboard.press("Home")
  await expect(page.locator(`#${first.id}`)).toBeFocused()
})

test("a New document left with text becomes the first card and takes focus", async ({ page }) => {
  const count = await page.locator(".grid.cards > .slot").count()
  await page.locator(".grid.cards > .slot .card").first().focus()
  await page.keyboard.press("n")
  const editor = page.getByRole("textbox", { name: "Document text" })
  await expect(editor).toBeFocused()
  await editor.pressSequentially("Fresh idea from the browser suite")
  await editor.press("Escape")

  const firstCard = page.locator(".grid.cards > .slot .card").first()
  // Its card is drawn only once it is measured; focus waits for it.
  await expect(firstCard).toContainText("Fresh idea from the browser suite")
  await expect(firstCard).toBeFocused()
  await expect(page.locator(".grid.cards > .slot")).toHaveCount(count + 1)
  await packed(page)
  await expectPackedWell(page)
})

test("an edited note slides to the front, highlighted, and keeps focus", async ({ page }) => {
  const third = page.locator(".grid.cards > .slot .card").nth(2)
  const id = await third.getAttribute("id")
  await third.click()
  const editor = page.getByRole("textbox", { name: "Document text" })
  await expect(editor).toBeFocused()
  await editor.press("ControlOrMeta+End")
  await editor.pressSequentially(" Revised.")
  await editor.press("Escape")

  const card = page.locator(`#${id}`)
  await expect(card).toBeFocused()
  await expect(card).toHaveClass(/just-moved/)
  await expect(page.locator(".grid.cards > .slot .card").first()).toHaveId(id!)
  await expect(card).not.toHaveClass(/just-moved/, { timeout: 3_000 })
  await expectPackedWell(page)
})

test("a note emptied in the editor is removed and focus moves to its place", async ({ page }) => {
  const cards = page.locator(".grid.cards > .slot .card")
  const count = await cards.count()
  const ids = await cards.evaluateAll(each => each.map(card => card.id))
  await page.locator(`#${ids[1]}`).click()
  const editor = page.getByRole("textbox", { name: "Document text" })
  await expect(editor).toBeFocused()
  await editor.fill("")
  await editor.press("Escape")

  await expect(page.locator(`#${ids[1]}`)).toHaveCount(0)
  await expect(cards).toHaveCount(count - 1)
  await expect(page.locator(`#${ids[2]}`)).toBeFocused()
  await expect(page.locator("[aria-live=polite]")).toHaveText("Removed empty document")
})
