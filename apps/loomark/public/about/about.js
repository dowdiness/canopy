// Loomark introduction page, imperative shell: it finds the page's elements
// once at start, measures, observes, and writes them, and leaves every
// decision to the core. Everything degrades to readable static content.

import {
  afterFocus, anchorOf, anchorScrollTop, currentLines, dotPositions, dotStyle,
  editorHidden, escapeLeavesFocus, focusAdded, focusButtonAction, inkSettled, inkTarget,
  keyDelay, navScrolled, nextInk, paneVisible, phaseAt, phaseCentres, phaseChange, phaseScrollTop,
  phoneAdded, pinnedStageTop, renderMarkdown, renderSource, rgbChannels, runMotion, runProgress,
  sheetEntry, typedPrefixes, wakeOrigin,
} from "./about-core.js"

const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)")
const finePointer = matchMedia("(hover: hover) and (pointer: fine)")

const wait = ms => new Promise(resolve => setTimeout(resolve, ms))

// Types text in prefix by prefix; reports whether it was still wanted at the end.
async function typeOut(text, { stride = 1, keys, current, show }) {
  for (const step of typedPrefixes(text, stride)) {
    if (!current()) return false
    show(step)
    await wait(keyDelay(step.last, Math.random(), keys))
  }
  return current()
}

function whenSeen(element, threshold, action) {
  const observer = new IntersectionObserver(entries => {
    if (!entries.some(entry => entry.isIntersecting)) return
    observer.disconnect()
    action()
  }, { threshold })
  observer.observe(element)
}

/* ---------- Navigation ---------- */

function mountNav(nav) {
  const update = () => nav.classList.toggle("is-scrolled", navScrolled(scrollY))
  addEventListener("scroll", update, { passive: true })
  update()
}

/* ---------- Reveal ---------- */

function observeReveal(elements) {
  const observer = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue
      entry.target.classList.add("is-in")
      observer.unobserve(entry.target)
    }
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 })
  for (const element of elements) observer.observe(element)
}

/* ---------- Hero dot grid: ink gathers where the pointer rests ---------- */

function mountDots(canvas, hero) {
  const context = canvas.getContext("2d")
  let width = 0
  let height = 0
  let ratio = 1
  let dots = []
  let pointer = null
  let frame = 0
  let color = "0,0,0"

  const readColor = () => {
    const probe = document.createElement("span")
    probe.style.color = "var(--ink)"
    hero.append(probe)
    color = rgbChannels(getComputedStyle(probe).color)
    probe.remove()
  }

  const resize = () => {
    const box = canvas.getBoundingClientRect()
    ratio = Math.min(devicePixelRatio || 1, 2)
    width = box.width
    height = box.height
    canvas.width = Math.round(width * ratio)
    canvas.height = Math.round(height * ratio)
    dots = dotPositions(width, height, 28).map(dot => ({ ...dot, ink: 0 }))
    draw(true)
  }

  const draw = settle => {
    frame = 0
    context.setTransform(ratio, 0, 0, ratio, 0, 0)
    context.clearRect(0, 0, width, height)
    let moving = false
    for (const dot of dots) {
      const target = inkTarget(pointer && Math.hypot(dot.x - pointer.x, dot.y - pointer.y))
      dot.ink = nextInk(dot.ink, target, settle)
      if (!inkSettled(dot.ink, target)) moving = true
      const { alpha, radius } = dotStyle(dot.ink)
      context.fillStyle = `rgba(${color},${alpha})`
      context.beginPath()
      context.arc(dot.x, dot.y, radius, 0, Math.PI * 2)
      context.fill()
    }
    if (moving) frame = requestAnimationFrame(() => draw(false))
  }

  const schedule = () => { if (!frame) frame = requestAnimationFrame(() => draw(false)) }

  readColor()
  resize()
  new ResizeObserver(resize).observe(canvas)
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => { readColor(); draw(true) })
  hero.addEventListener("pointermove", event => {
    if (!finePointer.matches || reducedMotion.matches) return
    const box = canvas.getBoundingClientRect()
    pointer = { x: event.clientX - box.left, y: event.clientY - box.top }
    schedule()
  })
  hero.addEventListener("pointerleave", () => { pointer = null; schedule() })
}

/* ---------- The real editor, waiting under the invitation ---------- */

// The app loads quietly beneath the invitation, inert, so it is already there
// when the reader begins. It is the same origin, so what is written here is
// saved with the reader's other Loomark documents.
function mountLive({ live, invite, invitePage, nav }) {
  let frame = null
  let frameLoaded = false
  let started = false
  let pageFocus = null
  document.addEventListener("focusin", event => { if (event.target !== frame) pageFocus = event.target })

  // The app draws its text area after it loads, so it is found when needed.
  const frameTextArea = () => frame?.contentDocument?.querySelector("textarea")

  function focusEditor() {
    frame.contentWindow?.focus()
    frameTextArea()?.focus({ preventScroll: true })
  }

  function warmEditor() {
    if (frame) return
    frame = document.createElement("iframe")
    frame.src = "../"
    frame.title = "Loomark"
    frame.className = "desk live-frame"
    frame.inert = true
    frame.addEventListener("load", () => {
      frameLoaded = true
      if (started) reveal()
    }, { once: true })
    invite.before(frame)
    // The app asks for focus as it starts; until the reader begins, the page
    // keeps it, so keys still scroll the page and nothing is typed unseen.
    // The frame's window outlives its first blank document, so this listener stays.
    frame.contentWindow.addEventListener("focusin", event => {
      if (started) return
      event.target.blur()
      window.focus()
      if (pageFocus?.isConnected) pageFocus.focus({ preventScroll: true })
      else frame.blur()
    }, true)
  }

  // The invitation fades only once the app is there to show; typing can start at once.
  function reveal() {
    focusEditor()
    invite.animate({ opacity: [1, 0] }, { duration: reducedMotion.matches ? 0 : 420, easing: "ease", fill: "forwards" })
      .finished.then(() => invite.remove())
  }

  function wake(event) {
    const box = invite.getBoundingClientRect()
    const page = getComputedStyle(invitePage)
    const origin = wakeOrigin({
      pointed: event.detail > 0,
      x: event.clientX - box.left,
      y: event.clientY - box.top,
      paddingLeft: parseFloat(page.paddingLeft),
      paddingTop: parseFloat(page.paddingTop),
    })
    const ripple = document.createElement("span")
    ripple.className = "live-page paper live-wake"
    ripple.ariaHidden = "true"
    ripple.style.setProperty("--x", `${origin.x}px`)
    ripple.style.setProperty("--y", `${origin.y}px`)
    ripple.addEventListener("animationend", () => ripple.remove(), { once: true })
    live.append(ripple)
  }

  invite.addEventListener("pointerenter", warmEditor)
  invite.addEventListener("focus", warmEditor)
  invite.addEventListener("click", event => {
    warmEditor()
    started = true
    frame.inert = false
    live.classList.add("is-starting")
    if (!reducedMotion.matches) wake(event)
    const box = frame.getBoundingClientRect()
    if (editorHidden({ top: box.top, bottom: box.bottom, navHeight: nav.offsetHeight, viewportHeight: innerHeight })) {
      frame.scrollIntoView({ block: "center", behavior: reducedMotion.matches ? "instant" : "smooth" })
    }
    if (frameLoaded) reveal()
  })
  // The app shares this page's main thread. A desktop loads it once the page is
  // idle; a phone has less to spare, so it waits for the reader's first touch,
  // which usually comes well before the reader reaches for the editor.
  // Readers who save data load it only when they reach for it.
  invite.addEventListener("pointerdown", warmEditor)
  if (!navigator.connection?.saveData) {
    if (finePointer.matches) {
      addEventListener("load", () => {
        if ("requestIdleCallback" in window) requestIdleCallback(warmEditor, { timeout: 2000 })
        else setTimeout(warmEditor, 600)
      }, { once: true })
    } else {
      addEventListener("touchstart", warmEditor, { once: true, passive: true })
    }
  }

  return { readerValue: () => started ? frameTextArea()?.value ?? "" : "" }
}

/* ---------- One sheet: the hero's editor stays in view through three chapters ---------- */

const noteKeys = { key: 14, newline: 60 }
const focusKeys = { key: 42, jitter: 46, newline: 260 }
const phoneKeys = { key: 38, jitter: 40, newline: 200 }

function mountRun(parts, { readerValue }) {
  const {
    root, nav, live, run, stage, desk, source, rendered, textScroll, panes, modeButtons,
    steps, stepNote, focusButton, focusSteps, focusNote, phone, phonePage, viewsChapter, captions,
  } = parts
  const state = { phase: null, chapter: null, mode: null, shownText: null, writing: false, focused: false, focusOff: false, stageTop: 0 }
  // One scene plays on the sheet at a time: the note writing itself, 02, or 03.
  // Each holds the scene it began in and stops once another begins.
  let scene = 0
  let anchors = []

  function beginScene() {
    const token = ++scene
    return () => token === scene
  }

  // Ends the playing scene; reports whether it left a note half written.
  function endScene() {
    scene++
    focusButton.classList.remove("is-pressing")
    phone.classList.remove("is-syncing")
    desk.classList.remove("is-syncing")
    const interrupted = state.writing
    state.writing = false
    return interrupted
  }

  function fillViews(text) {
    state.shownText = text
    source.innerHTML = renderSource(text, anchorOf(text))
    rendered.innerHTML = renderMarkdown(text, anchorOf(text))
    // The anchors are found once the panes are drawn.
    anchors = panes.map(({ pane }) => pane.querySelector("[data-anchor]"))
    textScroll.scrollTop = 0
    alignAnchors()
  }

  function alignAnchors() {
    // Focus Mode and sync follow the end of the note instead.
    if (state.chapter !== "views") return
    panes.forEach(({ name, scroller }, index) => {
      const anchor = anchors[index]
      if (!anchor || !paneVisible(state.mode, name)) return
      scroller.scrollTop = anchorScrollTop({ anchorTop: anchor.offsetTop, paneHeight: scroller.clientHeight })
    })
  }

  function setDeskMode(mode) {
    state.mode = mode
    desk.dataset.mode = mode
    for (const { button, name } of modeButtons) button.setAttribute("aria-pressed", String(name === mode))
    for (const { pane, name } of panes) pane.inert = !paneVisible(mode, name)
    alignAnchors()
  }

  async function writeNote(text) {
    const current = beginScene()
    state.shownText = text
    if (reducedMotion.matches) { fillViews(text); return }
    state.writing = true
    const done = await typeOut(text, {
      stride: 2,
      keys: noteKeys,
      current,
      show: ({ shown }) => { source.innerHTML = renderSource(shown, null) + '<span class="caret"></span>' },
    })
    if (!done) return
    state.writing = false
    fillViews(text)
  }

  function enterSheet(chapter) {
    const entry = sheetEntry(readerValue(), state.shownText, chapter)
    if (entry.fill) fillViews(entry.fill)
    if (entry.write) writeNote(entry.write)
  }

  function markStep(name) {
    for (const step of steps) {
      const active = step.name === name
      step.item.classList.toggle("is-active", active)
      step.button.setAttribute("aria-pressed", String(active))
      if (active) stepNote.innerHTML = step.note
    }
  }

  /* 02: the corner button turns Focus Mode on, then a new paragraph is written
     while the rest of the note fades. */
  function setFocused(on) {
    state.focused = on
    run.classList.toggle("is-focused", on)
    root.classList.toggle("is-focus-reading", on)
    focusButton.setAttribute("aria-pressed", String(on))
  }

  function markFocusStep(name) {
    for (const step of focusSteps) {
      const active = step.name === name
      step.item.classList.toggle("is-active", active)
      if (active) focusNote.textContent = step.note
    }
  }

  // Lines are updated in place, so a paragraph left behind fades instead of blinking.
  function showFocusText(text, caret) {
    const lines = text.split("\n")
    const rows = source.children
    while (rows.length > lines.length) rows[rows.length - 1].remove()
    lines.forEach((line, index) => {
      if (!rows[index]) source.append(Object.assign(document.createElement("div"), { className: "line" }))
      if (rows[index].textContent !== line) rows[index].textContent = line
    })
    if (caret) rows[rows.length - 1].append(caret)
    currentLines(lines).forEach((current, index) => rows[index].classList.toggle("is-current", current))
    textScroll.scrollTop = textScroll.scrollHeight
  }

  async function playFocus() {
    const current = beginScene()
    const base = state.shownText
    const added = focusAdded(base)
    if (reducedMotion.matches) {
      showFocusText(base + added, null)
      markFocusStep("write")
      setFocused(!state.focusOff)
      return
    }
    const caret = Object.assign(document.createElement("span"), { className: "sync-caret" })
    showFocusText(base, null)
    markFocusStep("on")
    await wait(900)
    if (!current()) return
    focusButton.classList.add("is-pressing")
    await wait(240)
    if (!current()) return
    if (!state.focusOff) setFocused(true)
    showFocusText(base, caret)
    await wait(900)
    focusButton.classList.remove("is-pressing")
    if (!current()) return
    markFocusStep("write")
    const done = await typeOut(added, { keys: focusKeys, current, show: ({ shown }) => showFocusText(base + shown, caret) })
    if (!done) return
    await wait(1400)
    if (current()) markFocusStep("off")
  }

  /* 03: the phone opens the same note, adds a line, and the laptop catches up. */
  function showPhone(text, caret) {
    phonePage.innerHTML = renderSource(text) + (caret ? '<span class="sync-caret"></span>' : "")
    phonePage.scrollTop = phonePage.scrollHeight
  }

  function showLaptop(text) {
    source.innerHTML = renderSource(text, anchorOf(state.shownText))
    textScroll.scrollTop = textScroll.scrollHeight
  }

  async function playSync() {
    const current = beginScene()
    const base = afterFocus(state.shownText)
    const added = phoneAdded(state.shownText)
    showPhone(base, false)
    showLaptop(base)
    if (!reducedMotion.matches) {
      await wait(1100)
      const done = await typeOut(added, { keys: phoneKeys, current, show: ({ shown }) => showPhone(base + shown, true) })
      if (!done) return
      await wait(400)
      if (!current()) return
      phone.classList.add("is-syncing")
      await wait(700)
      phone.classList.remove("is-syncing")
      if (!current()) return
    }
    desk.classList.add("is-syncing")
    showPhone(base + added, false)
    showLaptop(base + added)
    await wait(reducedMotion.matches ? 0 : 700)
    desk.classList.remove("is-syncing")
  }

  function setPhase(next) {
    if (next === state.phase) return
    const change = phaseChange(state.phase, next)
    state.phase = next
    state.chapter = change.chapter
    run.dataset.chapter = change.chapter
    // Only the sheet in view takes input; captions out of view take none.
    desk.inert = change.chapter === "hero"
    live.inert = change.chapter !== "hero"
    viewsChapter.inert = change.chapter !== "views"
    // A note cut off mid-sentence, or one 02 and 03 added to, is shown whole again.
    if (endScene() || change.restore) fillViews(state.shownText)
    if (change.enterSheet) enterSheet(change.chapter)
    setFocused(false)
    if (state.mode !== change.mode) setDeskMode(change.mode)
    markStep(change.step)
    if (change.play === "focus") {
      state.focusOff = false
      playFocus()
    }
    if (change.play === "sync") playSync()
  }

  const measure = () => ({
    scrollY,
    runTop: run.offsetTop,
    stageTop: state.stageTop,
    runHeight: run.offsetHeight,
    stageHeight: stage.offsetHeight,
  })

  function placeStage() {
    state.stageTop = pinnedStageTop({ navHeight: nav.offsetHeight, viewportHeight: innerHeight, stageHeight: stage.offsetHeight })
    run.style.setProperty("--stage-top", `${state.stageTop}px`)
  }

  // The moves between chapters follow the scroll; only the phase switches.
  function moveRun(motion) {
    const set = (element, name, value) => element.style.setProperty(name, value.toFixed(4))
    set(run, "--sheet", motion.sheet)
    set(run, "--laptop", motion.laptop)
    set(run, "--phone", motion.phone)
    for (const { element, name } of captions) {
      set(element, "--shift", motion.captions[name].shift)
      set(element, "--show", motion.captions[name].show)
    }
  }

  function followRun() {
    const progress = runProgress(measure())
    setPhase(phaseAt(progress))
    moveRun(runMotion(progress, reducedMotion.matches))
  }

  const scrollToPhase = phase =>
    scrollTo({ top: phaseScrollTop(phase, measure()), behavior: reducedMotion.matches ? "instant" : "smooth" })

  new ResizeObserver(() => alignAnchors()).observe(desk)
  for (const { button, name } of [...modeButtons, ...steps]) button.addEventListener("click", () => scrollToPhase(name))
  focusButton.addEventListener("click", () => {
    const action = focusButtonAction({ phase: state.phase, focused: state.focused })
    if (action.scrollTo) { scrollToPhase(action.scrollTo); return }
    state.focusOff = !action.focused
    setFocused(action.focused)
  })
  addEventListener("keydown", event => {
    if (!escapeLeavesFocus({ key: event.key, phase: state.phase, focused: state.focused, composing: event.isComposing })) return
    state.focusOff = true
    setFocused(false)
  })
  setDeskMode("text")

  return { placeStage, followRun }
}

/* ---------- Closing: the last line writes itself ---------- */

function mountClosing({ line, source, typed, rest }) {
  const text = source.textContent
  typed.textContent = ""
  rest.textContent = text
  // The whole line is laid out from the start; typing only inks it, so nothing shifts.
  const show = step => {
    typed.textContent = step.shown
    rest.textContent = step.rest
  }
  whenSeen(line, 0.6, () => {
    if (reducedMotion.matches) show({ shown: text, rest: "" })
    else typeOut(text, { keys: { key: 40, jitter: 50, newline: 40 }, current: () => true, show })
  })
}

/* ---------- Start: the page's elements are found here, once ---------- */

const root = document.documentElement
const nav = document.querySelector("[data-nav]")
const live = document.querySelector("[data-live]")
const run = document.querySelector("[data-run]")
const desk = run.querySelector("[data-views-desk]")
const closingLine = document.querySelector(".closing-typed")
// Each chapter link lands where choosing that phase scrolls.
for (const mark of run.querySelectorAll(".run-mark")) mark.style.setProperty("--at", phaseCentres[mark.dataset.phase])

mountNav(nav)
observeReveal(document.querySelectorAll("[data-reveal]"))
mountDots(document.querySelector("[data-dots]"), document.querySelector(".hero"))
const editor = mountLive({ live, invite: live.querySelector("[data-live-start]"), invitePage: live.querySelector(".live-invite .live-page"), nav })
const sheet = mountRun({
  root,
  nav,
  live,
  run,
  stage: run.querySelector(".run-stage"),
  desk,
  source: desk.querySelector("[data-views-source]"),
  rendered: desk.querySelector("[data-views-rendered]"),
  textScroll: desk.querySelector(".pane-text .pane-scroll"),
  panes: [...desk.querySelectorAll("[data-pane]")].map(pane => ({ pane, name: pane.dataset.pane, scroller: pane.querySelector(".pane-scroll") })),
  modeButtons: [...desk.querySelectorAll("[data-mode-button]")].map(button => ({ button, name: button.dataset.modeButton })),
  steps: [...run.querySelectorAll("[data-step]")].map(item => ({
    item,
    name: item.dataset.step,
    button: item.querySelector("[data-step-trigger]"),
    note: item.querySelector(".step-note").innerHTML,
  })),
  stepNote: run.querySelector("[data-run-note]"),
  focusButton: run.querySelector("[data-run-focus]"),
  focusSteps: [...run.querySelectorAll("[data-focus-step]")].map(item => ({
    item,
    name: item.dataset.focusStep,
    note: item.querySelector(".step-note").textContent,
  })),
  focusNote: run.querySelector("[data-focus-note]"),
  phone: run.querySelector(".run-phone"),
  phonePage: run.querySelector("[data-run-phone]"),
  viewsChapter: run.querySelector('.run-chapter[data-chapter="views"]'),
  captions: [...run.querySelectorAll(".run-chapter")].map(element => ({ element, name: element.dataset.chapter })),
}, editor)
mountClosing({
  line: closingLine,
  source: document.querySelector("[data-closing-source]"),
  typed: closingLine.querySelector("[data-closing-typed]"),
  rest: closingLine.querySelector("[data-closing-rest]"),
})
const opening = document.querySelectorAll(".hero [data-reveal], .run-sheet [data-reveal]")

let ticking = false
addEventListener("scroll", () => {
  if (ticking) return
  ticking = true
  requestAnimationFrame(() => {
    ticking = false
    sheet.followRun()
  })
}, { passive: true })
addEventListener("resize", () => { sheet.placeStage(); sheet.followRun() })

sheet.placeStage()
sheet.followRun()
requestAnimationFrame(() => { for (const element of opening) element.classList.add("is-in") })
