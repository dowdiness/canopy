///|
// Tailwind utility bundle for the light-DOM outline resize handle chrome.
// Keep semantic hooks as the first class tokens; Rabbita @resizable owns
// behavior and ARIA attributes.
let outline_resize_handle_layout_class : String = "absolute inset-y-0 right-0 z-[2] " +
  "w-[8px] border-0 bg-transparent " +
  "[@media(max-width:768px)]:hidden"

///|
let outline_resize_handle_line_class : String = "after:content-[''] after:absolute after:inset-y-0 " +
  "after:left-[3px] after:w-px after:bg-canopy-border after:opacity-0 " +
  "after:transition-[opacity,background,box-shadow] " +
  "after:duration-(--duration-fast) after:ease-canopy-out"

///|
let outline_resize_handle_state_class : String = "hover:after:opacity-100 hover:after:bg-canopy-accent " +
  "hover:after:shadow-[0_0_12px_rgba(130,80,223,0.45)] " +
  "focus-visible:after:opacity-100 focus-visible:after:bg-canopy-accent " +
  "focus-visible:after:shadow-[0_0_12px_rgba(130,80,223,0.45)] " +
  "focus-visible:outline-2 focus-visible:outline-solid " +
  "focus-visible:outline-canopy-focus-ring focus-visible:outline-offset-[-2px]"

///|
let outline_resize_handle_class : String = "panel-resize-handle outline-resize-handle " +
  outline_resize_handle_layout_class +
  " " +
  outline_resize_handle_line_class +
  " " +
  outline_resize_handle_state_class
