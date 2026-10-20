// Loomark introduction page, functional core: the copy, the Markdown likeness,
// and every decision the page makes, as calculations over plain values.
// Nothing here reads the DOM, the clock, or a random source.

/* ---------- Copy ---------- */

export const documents = {
  views: "# Saturday\n\nA slow morning. Coffee on the balcony, then the market.\n\n## To buy\n\n- Bread\n- **Tomatoes**, the good ones\n- Flowers for the table\n\n## Notes\n\nThe bakery opens at *eight*, not nine.\n\nCall home about lunch on Sunday.",
  anchor: "A slow morning",
  // Added on the phone in 03, after the note it picked up.
  phone: "\n\nLunch at one. Bring the flowers.",
  readerPhone: "\n\nAdded on the phone.",
  // Written in 02, while the rest of the note fades.
  focus: "\n\nMaybe a walk by the river after.\n\nAsk Mia if she wants to come.",
  readerFocus: "\n\nWritten in Focus Mode.",
}

/* ---------- Markdown, just enough for these pages ---------- */

const escapeHtml = text => text.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c])

function inline(text) {
  return escapeHtml(text)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\*([^*]+)\*/g, "<em>$1</em>")
}

export function renderMarkdown(source, anchor) {
  const html = []
  for (const block of source.split(/\n{2,}/)) {
    const lines = block.split("\n").filter(Boolean)
    if (lines.length === 0) continue
    if (lines.every(line => line.startsWith("- "))) {
      html.push(`<ul>${lines.map(line => `<li>${inline(line.slice(2))}</li>`).join("")}</ul>`)
      continue
    }
    const heading = /^(#{1,6}) (.*)$/.exec(block)
    if (heading) {
      const level = Math.min(heading[1].length, 2)
      html.push(`<h${level}>${inline(heading[2])}</h${level}>`)
      continue
    }
    const marked = anchor && block.startsWith(anchor) ? ' class="anchor-mark" data-anchor' : ""
    html.push(`<p${marked}>${inline(lines.join(" "))}</p>`)
  }
  return html.join("")
}

// Text mode shows the source exactly as typed; only the anchor paragraph is marked.
export function renderSource(source, anchor) {
  return source.split("\n").map(line => {
    const marked = anchor && line.startsWith(anchor) ? " anchor-mark" : ""
    const attrs = marked ? ` class="line${marked}" data-anchor` : ' class="line"'
    return `<div${attrs}>${escapeHtml(line)}</div>`
  }).join("")
}

/* ---------- Typing ---------- */

// How long a typed character stays before the next, given a roll in [0, 1).
export const keyDelay = (char, roll, { key, jitter = 0, newline }) =>
  char === "\n" ? newline : key + roll * jitter

// The prefixes a typist shows, every `stride` characters, ending on the whole text.
export function typedPrefixes(text, stride = 1) {
  const counts = []
  for (let count = stride; count < text.length; count += stride) counts.push(count)
  counts.push(text.length)
  return counts.map(count => ({ shown: text.slice(0, count), rest: text.slice(count), last: text[count - 1] }))
}

/* ---------- The page ---------- */

export const navScrolled = scrollY => scrollY > 8

// The stage pins centred in the room below the navigation.
export const pinnedStageTop = ({ navHeight, viewportHeight, stageHeight }) =>
  Math.max(navHeight + 12, navHeight + (viewportHeight - navHeight - stageHeight) / 2)

// A started editor scrolls into view only when part of it is hidden.
export const editorHidden = ({ top, bottom, navHeight, viewportHeight }) =>
  top < navHeight || bottom > viewportHeight

// A keyboard press has no point of contact, so the wave starts at the caret.
export const wakeOrigin = ({ pointed, x, y, paddingLeft, paddingTop }) =>
  pointed ? { x, y } : { x: paddingLeft, y: paddingTop + 15 }

/* ---------- Hero dot grid: ink gathers where the pointer rests ---------- */

export function dotPositions(width, height, spacing) {
  const dots = []
  const offsetX = (width % spacing) / 2
  for (let y = spacing / 2; y < height; y += spacing) {
    for (let x = offsetX; x <= width; x += spacing) dots.push({ x, y })
  }
  return dots
}

export const inkTarget = distance => distance === null ? 0 : Math.max(0, 1 - distance / 190) ** 2
export const nextInk = (ink, target, settle) => settle ? target : ink + (target - ink) * 0.12
export const inkSettled = (ink, target) => Math.abs(target - ink) <= 0.004
export const dotStyle = ink => ({ alpha: 0.13 + ink * 0.4, radius: 0.95 + ink * 0.75 })
export const rgbChannels = color => (color.match(/[\d.]+/g) ?? [0, 0, 0]).slice(0, 3).join(",")

/* ---------- One sheet: the hero's editor stays in view through three chapters ---------- */

// Where each phase begins, as a share of the run's scroll distance.
const phaseStarts = [["hero", 0], ["text", 0.06], ["split", 0.19], ["preview", 0.31], ["focus", 0.43], ["sync", 0.7]]
// Where choosing a phase scrolls, well inside it; chapter links land there too.
export const phaseCentres = { text: 0.12, split: 0.25, preview: 0.37, focus: 0.5, sync: 0.78 }
const views = ["text", "split", "preview"]

export const chapterOf = phase => views.includes(phase) ? "views" : phase
export const modeOf = phase => views.includes(phase) && phase !== "text" ? phase : "text"
export const stepOf = phase => views.includes(phase) ? phase : "text"
export const paneVisible = (mode, pane) => mode === "split" || pane === mode

export const runDistance = ({ runHeight, stageHeight }) => runHeight - stageHeight

export const runProgress = ({ scrollY, runTop, stageTop, runHeight, stageHeight }) =>
  Math.min(1, Math.max(0, (scrollY - (runTop - stageTop)) / runDistance({ runHeight, stageHeight })))

export function phaseAt(progress) {
  let phase = phaseStarts[0][0]
  for (const [name, start] of phaseStarts) if (progress >= start) phase = name
  return phase
}

// How far each move between chapters has gone at a point of the run, so the
// chapters follow the scroll as one motion. Each caption leaves just before its
// chapter ends and the next arrives just after, so the two never overlap; the
// phase switches at the boundary, when neither is visible. With `snap`, every
// move jumps at its boundary instead.
const handover = 0.03
const smooth = t => t * t * (3 - 2 * t)

export function runMotion(progress, snap = false) {
  const move = (from, to, at) =>
    snap ? Number(progress >= at) : smooth(Math.min(1, Math.max(0, (progress - from) / (to - from))))
  const { text: views, focus, sync } = Object.fromEntries(phaseStarts)
  // A caption's shift: 1 still to come, 0 in place, -1 gone.
  const caption = (start, end) => {
    const arrived = move(start, start + handover, start)
    const left = end > 1 ? 0 : move(end - handover, end, end)
    const shift = (1 - arrived) - left
    return { shift, show: 1 - Math.abs(shift) }
  }
  return {
    // The live editor gives way to the sheet as the run begins.
    sheet: move(views, views + 0.05, views),
    // The laptop steps aside, and the phone follows a moment behind.
    laptop: move(sync, sync + 0.06, sync),
    phone: move(sync + 0.015, sync + 0.075, sync),
    captions: { views: caption(views, focus), focus: caption(focus, sync), sync: caption(sync, 2) },
  }
}

// Choosing scrolls to where the page shows the choice, so scrolling and choosing agree.
export const phaseScrollTop = (phase, { runTop, stageTop, runHeight, stageHeight }) =>
  runTop - stageTop + runDistance({ runHeight, stageHeight }) * phaseCentres[phase]

// What changes when the run moves from one phase to the next. Every change
// ends the scene playing on the sheet; these say what follows.
export function phaseChange(previous, next) {
  const chapter = chapterOf(next)
  const before = previous === null ? "hero" : chapterOf(previous)
  return {
    chapter,
    enterSheet: before === "hero" && chapter !== "hero",
    // 02 and 03 add to the note; leaving them puts the note back as it was.
    restore: (before === "focus" || before === "sync") && chapter !== before,
    mode: modeOf(next),
    step: stepOf(next),
    play: chapter === "focus" || chapter === "sync" ? chapter : null,
  }
}

// What the reader wrote in the editor above becomes the note; otherwise a
// Saturday note writes itself in, when the sheet opens on 01.
export function sheetEntry(readerValue, shownText, chapter) {
  const text = readerValue?.trim() ? readerValue : documents.views
  if (text === shownText) return { keep: true }
  return text === documents.views && chapter === "views" ? { write: text } : { fill: text }
}

export const anchorOf = text => text === documents.views ? documents.anchor : null

// The anchor paragraph sits a little above the middle of its pane.
export const anchorScrollTop = ({ anchorTop, paneHeight }) => Math.max(0, anchorTop - paneHeight * 0.44)

/* 02: Focus Mode, then a new paragraph written while the rest of the note fades. */

export const focusAdded = base => base === documents.views ? documents.focus : documents.readerFocus
export const afterFocus = base => base + focusAdded(base)

// The paragraph being written, and the blank lines where the next one begins.
export function currentLines(lines) {
  const current = lines.map(() => false)
  let index = lines.length - 1
  while (index >= 0 && lines[index] === "") current[index--] = true
  while (index >= 0 && lines[index] !== "") current[index--] = true
  return current
}

// The corner button turns Focus Mode on or off in 02, and leads to 02 elsewhere.
export const focusButtonAction = ({ phase, focused }) =>
  phase === "focus" ? { focused: !focused } : { scrollTo: "focus" }

export const escapeLeavesFocus = ({ key, phase, focused, composing }) =>
  key === "Escape" && phase === "focus" && focused && !composing

/* 03: the phone opens the same note, adds a line, and the laptop catches up. */

export const phoneAdded = base => base === documents.views ? documents.phone : documents.readerPhone
