# Zen and focus-mode icon conventions

**Date / source access:** 2026-09-28

**Status:** Historical research — Loomark's Focus mode was subsequently removed.
The recommendations below describe the design considered at the time, not a
current product requirement.

## Question and evidence boundary

Is Loomark's Lucide `scan` icon understandable for a mode that hides chrome and
exits with `Esc`, and what do comparable editor and writing products actually
use? “Icon verified” below means a first-party source names the glyph or a
first-party capture visibly establishes it. A documented command, menu item, or
shortcut does **not** establish toolbar iconography.

## Primary evidence

| Product | Documented mode and invocation | Verified actual iconography | Observation / uncertainty | Primary source |
|---|---|---|---|---|
| Visual Studio Code | **Zen Mode**: View → Appearance → Zen Mode; command **View: Toggle Zen Mode**; `Ctrl+K Z`; double-press `Esc` to exit. | **Verified:** VS Code's first-party source registers the Zen Mode layout item with `Codicon.target`—a target/bullseye glyph. | This is the strongest direct precedent for a compact “focus target” symbol. The source places it in Customize Layout; it does not prove a persistent editor-toolbar button. | [UI docs](https://code.visualstudio.com/docs/editing/getting-started/userinterface#_zen-mode); [first-party source, icon registration](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/browser/actions/layoutActions.ts#L60-L62); [layout item using that icon](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/browser/actions/layoutActions.ts#L1398-L1401) |
| JetBrains IDEs | **Distraction-free mode** hides UI and centers code; **Zen mode** combines it with full screen. Enter/exit through Quick Switch Scheme (`Ctrl+Backtick`, or `Control+Backtick` on macOS) → View Mode. | **Not verifiable from the cited first-party guide.** It documents menu/keyboard access and shows the resulting mode, but does not identify a toolbar glyph. | Strong naming/behavior precedent for chrome-hiding, but no evidence for an icon shape. | [JetBrains Guide: Make Your Work Environment Distraction Free](https://www.jetbrains.com/guide/tips/distraction-free/) |
| Craft | **Toggle Focus Mode**: `Cmd+.` on macOS, `Ctrl+.` on Windows. | **Not verifiable from the cited first-party shortcut reference.** | Direct writing-app precedent for a chrome-focused mode and a toggle shortcut; the official page does not establish a toolbar button or glyph. | [Craft Help: Keyboard Shortcuts](https://support.craft.do/en/introduction/shortcuts#navigation) |
| iA Writer | **Focus Mode** emphasizes the current sentence/paragraph or enables typewriter behavior. On Mac: Focus → Enable Focus Mode, `Cmd+D`, or a **Title Bar button**; Windows documents Focus → Paragraph/Sentence and `Ctrl+Shift+D` for sentence mode. | **Button existence verified; shape not verifiable.** The HTML/text names a title-bar button but does not reliably expose its drawn glyph. | This “Focus” means selective text emphasis, not primarily hidden chrome. Do not infer an icon from the generic product copy or the page's dropdown indicator. | [iA Writer: Focus Mode](https://ia.net/writer/support/editor/focus-mode); [Windows variant](https://ia.net/writer/support/editor/focus-mode/focus-mode-windows) |
| Typora | **Focus Mode** fades all but the current line/block; **Typewriter Mode** keeps the caret fixed. Both toggle from the View menu. | **No toolbar icon verified.** The first-party page's captures compare mode output, while its instructions specify the View menu only. | Like iA Writer, “Focus Mode” refers to text dimming rather than hiding application chrome. | [Typora Support: Focus Mode and Typewriter Mode](https://support.typora.io/Focus-and-Typewriter-Mode/) |
| Ulysses | Distraction reduction is composed from **Enter Full Screen**, `Cmd+3` to hide library/sheet list, **Hide Interface**, **Hide Toolbar**, Highlight, and Fixed Scrolling. | **No focus/Zen toolbar icon verified.** The official guide names menu/settings controls but does not identify a dedicated focus glyph. | Ulysses uses explicit view controls rather than one documented “Focus” icon. Its mobile guide mentions unrelated `+`, `−`, and sun icons; those are not evidence for focus mode. | [Ulysses Help: Customize the Editor — Focus on Your Writing](https://help.ulysses.app/en_US/dive-into-editing/editor-customization-guide#focus-on-your-writing) |

## Finding for Loomark

There is **no demonstrated cross-product toolbar-icon convention** in this
sample. First-party documentation consistently makes these modes discoverable
through explicit labels in View/Appearance/Focus menus and keyboard commands;
most sources do not establish any dedicated toolbar icon. The one source-level
glyph verified here is VS Code's target/bullseye, which supports the broad idea
of a focus reticle but not Lucide `scan` specifically.

Loomark's four-corner `scan` glyph is therefore *plausible but not
self-explanatory*. It can read as framing/focus or expansion, but also as a
scanner/camera/QR action. That ambiguity matters because “Focus Mode” itself
means two different things in the evidence: hiding chrome (VS Code, JetBrains,
Craft, and Loomark) versus emphasizing current prose (iA Writer and Typora).
Keep an accessible name/tooltip such as **Focus mode**, expose a labelled menu
or command in addition to the icon, and make the `Esc` exit route discoverable
through the exit tooltip. Loomark currently handles `Esc` but its tooltip does
not mention the shortcut; there is no permanent visible `Esc` cue.
If visual convention is the deciding factor, a target/bullseye has stronger
verified product precedent than `scan`; the evidence is too thin to call either
shape universally understood.
