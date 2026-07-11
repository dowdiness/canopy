# Editor Visual Design Spec

Design system for the projectional editor UI. Extracted from Paper canvas (3 artboards: desktop redesign, original split view, mobile).

## Design Principles

1. **The structure IS the interface** — render the AST as close to lambda calculus notation as possible, not as generic UI cards
2. **Information density** — developers prefer density over whitespace; every pixel earns its place
3. **Type-aware coloring** — different AST node types are immediately distinguishable by color
4. **Context-sensitive actions** — tools appear on selection only, not on every node
5. **Dark mode** — code editors are dark; a light consumer palette is wrong for sustained editing

## Color Palette

### Surfaces

| Token | Hex | Usage |
|-------|-----|-------|
| `--bg` | `#0f0e11` | Deep background |
| `--surface` | `#18171b` | Top bar, status bar, inspector |
| `--raised` | `#222126` | Selection info bar, hover states |
| `--border` | `rgba(255,255,255,0.06)` | Subtle dividers |
| `--border-strong` | `rgba(255,255,255,0.08)` | Interactive borders |

### Text

| Token | Hex | Usage |
|-------|-----|-------|
| `--text` | `#e4e0dc` | Primary text (warm off-white) |
| `--muted` | `#6b6670` | Secondary text, labels |
| `--dim` | `#3a3840` | Separators, inactive elements |

### AST Node Types

| Token | Hex | Node Kind | Example |
|-------|-----|-----------|---------|
| `--c-let` | `#8bc99a` | let binding | `let id = … in …` |
| `--c-lambda` | `#c4a1ff` | lambda abstraction | `(x) => …` |
| `--c-app` | `#7eb8da` | application | `App` |
| `--c-literal` | `#f2c066` | literal value | `42` |
| `--c-term` | `#e4e0dc` | variable/reference | `x` |
| `--c-error` | `#e8837c` | parse error | `Error: …` |

### Selection

| Token | Hex | Usage |
|-------|-----|-------|
| `--selected-bg` | `rgba(242,192,102,0.08)` | Selected row background |
| `--selected-border` | `#f2c066` | Selected row left accent |

### Peer Colors

| Peer | Color |
|------|-------|
| alice | `#ff8a65` (warm orange) |
| bob | `#64b5f6` (sky blue) |

## Typography

| Role | Font | Weight | Size |
|------|------|--------|------|
| Code / structure | JetBrains Mono | 400-600 | 13px (desktop), 14px (mobile) |
| UI chrome | Inter | 400-600 | 10-12px |
| Section labels | Inter | 600 | 10-11px, uppercase, 0.06em tracking |
| Top bar title | JetBrains Mono | 600 | 13px, `--c-lambda` color |

## Layout — Desktop (1440px)

```
┌─────────────────────────────────────────────────┐
│ Top Bar (44px)                                  │
│ [title]     [Structure|Text|Split]  [peers] [ok]│
├──────────────────┬────────────┬─────────────────┤
│ Structure Pane   │ Text Pane  │ Inspector       │
│ flex: 1.1        │ flex: 0.9  │ width: 320px    │
│                  │            │                 │
│ tree rows        │ textarea   │ breadcrumb      │
│ (outline style)  │ (dark bg)  │ selected node   │
│                  │            │ diagnostics     │
├──────────────────┴────────────┴─────────────────┤
│ Status Bar (28px)                               │
│ [breadcrumb]                    [peers] [version]│
└─────────────────────────────────────────────────┘
```

### Workspace Modes

- **Split**: structure + text + inspector (3 columns)
- **Tree**: structure + inspector (2 columns)
- **Text**: text + inspector (2 columns)

## Layout — Mobile (390px)

```
┌──────────────────────┐
│ Top Bar (48px)       │
│ [title]    [dots][ok]│
├──────────────────────┤
│                      │
│  Single pane view    │
│  (Structure, Text,   │
│   or Inspector)      │
│                      │
│  44px row height     │
│  for touch targets   │
│                      │
├──────────────────────┤
│ Selection Info Bar   │
│ SELECTED 42 | term   │
├──────────────────────┤
│ Bottom Tab Bar (52px)│
│ [Structure][Text][Inspector]│
└──────────────────────┘
```

### Mobile Adaptations

- Single pane visible at a time; switch via bottom tabs
- Tree rows: 44px height (vs 32px desktop) for touch
- Indent step: 24px (vs 28px desktop) to fit 390px width
- Top bar: no mode tabs (moved to bottom bar)
- Selection info bar: inline summary replaces inspector panel
- Peer dots only (no names) to save horizontal space

## Tree Row Anatomy

```
[indent padding] [accent bar 3px] [toggle 24px] [label] [badge?] [actions?]
```

- **Accent bar**: 3px wide, color matches node kind
- **Toggle**: `▼` expanded, `▶` collapsed, empty for leaf nodes
- **Label**: rendered in JetBrains Mono, colored by kind
- **Badge**: collapsed child count, shown only when collapsed, tinted by kind
- **Actions**: `Wrap function` / `Delete` buttons, shown only on selected node

### Depth Indentation (desktop)

| Depth | padding-left |
|-------|-------------|
| 0 | 16px |
| 1 | 44px |
| 2 | 72px |
| 3 | 100px |
| 4 | 128px |
| 5 | 156px |

## Inspector Panel (desktop)

Sections separated by `--border` dividers:

1. **Selected Node** — key-value pairs: Type, Label, Children
2. **Diagnostics** — error list or "No errors", togglable

## Responsive Breakpoint

At `<= 1120px`, workspace switches to vertical stacking:
- Panes stack vertically at 400px height each
- Inspector goes full width below

## Design History

- **v1** (original): Warm cream palette, frosted glass cards, marketing hero section, nested card-based tree nodes
- **v2** (current): Dark IDE palette, outline-style tree rows, color-coded AST types, inspector panel, minimal chrome
