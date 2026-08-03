///|
// Tailwind utility bundles for the light-DOM toolbar shell.
// Button chrome lives in `main/ui/button.mbt`; this file owns only the
// toolbar-specific layout hooks.
let toolbar_class = "toolbar flex items-center px-canopy-lg h-[48px] bg-canopy-header border-b border-solid border-canopy-border shadow-[0_1px_0_var(--canopy-glow)] gap-canopy-sm shrink-0 max-[768px]:pl-[max(var(--space-sm),env(safe-area-inset-left))] max-[768px]:pr-[max(var(--space-sm),env(safe-area-inset-right))] max-[768px]:gap-canopy-xs max-[768px]:overflow-x-auto max-[768px]:[-webkit-overflow-scrolling:touch] max-[768px]:[scrollbar-width:none] max-[768px]:[&::-webkit-scrollbar]:hidden max-[768px]:landscape:h-[40px]"

///|
let toolbar_title_class = "toolbar-title text-canopy-body font-medium text-canopy-secondary tracking-[-0.01em] mr-canopy-sm max-[768px]:text-canopy-small max-[480px]:hidden"

///|
let toolbar_spacer_class = "toolbar-spacer flex-1 max-[768px]:flex-[0_0_var(--space-xs)]"
