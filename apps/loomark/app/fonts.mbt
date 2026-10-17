///|
/// Loads Text's Japanese face as the app starts, so Japanese text draws in it
/// from its first frame. A cached file is ready before the document opens;
/// otherwise the download starts once the app script has run, without
/// competing with it. A browser that asks to save data loads the face only
/// when Japanese text appears.
fn load_writing_face(
  window : @dom.Window,
  faces : @browser.FontFaceSet,
) -> Unit {
  guard !@browser.save_data_requested(window) else { return }
  @browser.load_font_faces(faces, @fonts.WRITING_FACE, @fonts.JAPANESE_SAMPLE)
}
