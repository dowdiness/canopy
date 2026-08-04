///|
// Tailwind utility bundles for light-DOM inspector detail chrome.
// Keep semantic hooks as the first class token; panel header/section chrome
// remains owned by `view_panel_classes.mbt`.
let inspector_detail_row_layout_class = "flex gap-canopy-sm leading-[var(--leading-normal)]"

///|
let inspector_row_class : String = "inspector-row " +
  inspector_detail_row_layout_class +
  " py-canopy-xs px-0"

///|
let inspector_key_class = "inspector-key text-canopy-small font-normal text-canopy-muted w-[76px] shrink-0 whitespace-nowrap"

///|
let inspector_value_class = "inspector-value text-canopy-small font-normal text-canopy-fg font-canopy-mono tracking-[-0.01em] tabular-nums"

///|
let source_preview_class = "source-preview bg-canopy-surface rounded-canopy-sm py-canopy-sm px-canopy-md mt-canopy-sm font-canopy-mono text-canopy-caption leading-[var(--leading-normal)] text-canopy-fg whitespace-pre overflow-x-auto max-h-[4.5em] overflow-y-auto"

///|
let token_span_row_class : String = "token-span-row " +
  inspector_detail_row_layout_class +
  " py-[2px] px-0 font-canopy-mono text-canopy-caption"

///|
let token_span_role_class = "token-span-role text-canopy-muted min-w-[52px] shrink-0"

///|
let token_span_range_class = "token-span-range text-canopy-dim min-w-[44px] shrink-0 tabular-nums"

///|
let token_span_text_class = "token-span-text text-canopy-identifier"
