///|
// Tailwind utility bundles for the light-DOM action overlay/name prompt.
// Keep each semantic selector as the first class token: Playwright tests and
// integration code use those names as stable hooks while Tailwind owns the
// visual declarations for this migration slice.
let action_overlay_scrim_class = "action-overlay-scrim fixed inset-0 z-[50] bg-[rgba(0,0,0,0.3)]"

///|
let action_overlay_panel_class = "action-overlay-panel fixed z-[51] min-w-[200px] max-w-[280px] max-h-[360px] overflow-y-auto bg-canopy-panel border border-solid border-canopy-accent rounded-canopy-lg py-canopy-xs shadow-[0_8px_32px_rgba(0,0,0,0.4),0_0_0_1px_rgba(130,80,223,0.15)] animate-canopy-overlay-enter max-[768px]:min-w-[240px] max-[768px]:max-w-[min(320px,90vw)]"

///|
let action_overlay_list_class = "action-overlay-list flex flex-col"

///|
let action_group_label_class = "action-group-label text-canopy-label font-semibold text-canopy-dim tracking-[0.1em] uppercase pt-canopy-sm px-canopy-lg pb-canopy-xs border-t border-solid border-canopy-border mt-canopy-xs"

///|
let action_overlay_item_base_class = "action-overlay-item flex items-center gap-canopy-sm py-canopy-sm px-canopy-lg cursor-pointer text-canopy-small text-canopy-fg transition-colors duration-(--duration-fast) ease-canopy-out max-[768px]:min-h-[44px] max-[768px]:py-canopy-md max-[768px]:px-canopy-lg"

///|
let action_overlay_item_normal_state_class = "hover:bg-[rgba(130,80,223,0.15)] data-[active=true]:bg-[rgba(130,80,223,0.15)]"

///|
let action_overlay_item_danger_state_class = "danger text-canopy-error-text hover:bg-canopy-error-bg data-[active=true]:bg-canopy-error-bg"

///|
let action_overlay_item_class : String = action_overlay_item_base_class +
  " " +
  action_overlay_item_normal_state_class

///|
let action_overlay_item_danger_class : String = action_overlay_item_base_class +
  " " +
  action_overlay_item_danger_state_class

///|
let action_mnemonic_class = "action-mnemonic inline-flex items-center justify-center w-[22px] h-[22px] font-canopy-mono text-canopy-label font-semibold text-canopy-accent bg-[rgba(130,80,223,0.2)] rounded-canopy-sm shrink-0 uppercase"

///|
let action_label_text_class = "action-label-text font-canopy-ui text-canopy-small whitespace-nowrap"

///|
let name_prompt_container_class = "name-prompt-container py-canopy-md px-canopy-lg flex flex-col gap-canopy-sm"

///|
let name_prompt_label_class = "name-prompt-label text-canopy-small font-medium text-canopy-secondary"

///|
let name_prompt_input_row_class = "name-prompt-input-row flex"

///|
let name_prompt_input_class = "name-prompt-input flex-1 font-canopy-mono text-canopy-small py-canopy-sm px-canopy-md bg-canopy-surface border border-solid border-canopy-border rounded-canopy-md text-canopy-fg outline-none transition-colors duration-(--duration-fast) ease-canopy-out focus:border-canopy-accent focus:shadow-[0_0_0_2px_rgba(130,80,223,0.2)] placeholder:text-canopy-dim max-[768px]:min-h-[44px] max-[768px]:text-canopy-body"

///|
let action_overlay_error_class = "action-overlay-error text-canopy-label text-canopy-error-text py-canopy-sm px-canopy-lg"
