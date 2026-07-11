///|
// Tailwind utility bundles for light-DOM peer status, no-tree note, and
// empty-state chrome. Keep semantic hooks as the first class tokens;
// Rabbita/status subscriptions own behavior and ARIA attributes.
let no_tree_note_class = "no-tree-note text-canopy-small text-canopy-muted p-canopy-lg"

///|
let peer_item_class = "peer-item flex items-center gap-canopy-sm text-canopy-small text-canopy-secondary py-canopy-xs px-0"

///|
let peer_dot_chrome_class = "w-[7px] h-[7px] rounded-full shrink-0"

///|
fn peer_dot_state_class(status : SyncStatus) -> String {
  match status {
    Connected =>
      "connected bg-canopy-string shadow-[0_0_6px_var(--canopy-string)] animate-[pulse-connected_2s_ease-in-out_infinite]"
    Connecting =>
      "connecting bg-canopy-number shadow-[0_0_4px_var(--canopy-number)] animate-[pulse-connecting_1s_ease-in-out_infinite]"
    Offline => "offline bg-canopy-muted shadow-none opacity-60"
    Error => "error bg-canopy-operator shadow-[0_0_6px_var(--canopy-operator)]"
  }
}

///|
fn peer_dot_class(status : SyncStatus) -> String {
  "peer-dot " + peer_dot_state_class(status) + " " + peer_dot_chrome_class
}

///|
let empty_state_class = "empty-state p-canopy-lg"

///|
let empty_state_text_class = "empty-state-text text-canopy-small text-canopy-dim leading-[var(--leading-relaxed)]"
