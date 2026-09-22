///|
fn icon(icon_class : String, class : String) -> Html {
  span(
    class="\{icon_class} \{class}",
    attrs=Attrs::build().aria_hidden("true"),
    nothing,
  )
}

///|
/// Create the decorative icon used to toggle the document sidebar.
pub fn panel_icon(class : String) -> Html {
  icon("i-lucide-panel-left", class)
}

///|
/// Create the decorative icon used for the document collection.
pub fn folder_icon(class : String) -> Html {
  icon("i-lucide-folder", class)
}

///|
/// Create the decorative icon used to create a document.
pub fn square_pen_icon(class : String) -> Html {
  icon("i-lucide-square-pen", class)
}

///|
/// Create the decorative icon used to delete a document.
pub fn trash_icon(class : String) -> Html {
  icon("i-lucide-trash-2", class)
}

///|
/// Create the decorative icon used for Text mode.
pub fn text_mode_icon(class : String) -> Html {
  icon("i-lucide-align-left", class)
}

///|
/// Create the decorative icon used for Preview mode.
pub fn preview_mode_icon(class : String) -> Html {
  icon("i-lucide-eye", class)
}

///|
/// Create the decorative icon used for Split mode.
pub fn split_mode_icon(class : String) -> Html {
  icon("i-lucide-columns-2", class)
}

///|
/// Create the decorative icon used to import a document.
pub fn upload_icon(class : String) -> Html {
  icon("i-lucide-upload", class)
}

///|
/// Create the decorative icon used to export a document.
pub fn download_icon(class : String) -> Html {
  icon("i-lucide-download", class)
}
