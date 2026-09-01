///|
/// Create the decorative icon used to toggle the document sidebar.
pub fn sidebar_panel_icon() -> Html {
  span(
    class="i-lucide-panel-left block size-4 shrink-0",
    attrs=Attrs::build().aria_hidden("true"),
    nothing,
  )
}

///|
/// Create the decorative icon used for the document collection.
pub fn sidebar_folder_icon() -> Html {
  span(
    class="i-lucide-folder block size-4 shrink-0",
    attrs=Attrs::build().aria_hidden("true"),
    nothing,
  )
}

///|
/// Create the decorative icon used to add a document.
pub fn sidebar_new_icon() -> Html {
  span(
    class="i-lucide-plus block size-4 shrink-0",
    attrs=Attrs::build().aria_hidden("true"),
    nothing,
  )
}

///|
/// Create the decorative icon used to delete a document.
pub fn sidebar_delete_icon() -> Html {
  span(
    class="i-lucide-trash-2 block size-4 shrink-0",
    attrs=Attrs::build().aria_hidden("true"),
    nothing,
  )
}
