///|
const READING_FACE_IDLE_TIMEOUT_MS : Int = 2000

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

///|
priv suberror ReadingFaceSubscription {
  Load(String)
}

///|
/// Preview is hidden while Text is shown, so its reading face would load only
/// when Preview opens and draw the system font first. Load the faces that the
/// settled text needs while the page is idle, including at startup; text
/// without Japanese characters loads none. They wait for the faces already
/// loading, so a first visit downloads Text's face without sharing bandwidth.
fn reading_face_subscription(
  window : @dom.Window,
  faces : @browser.FontFaceSet,
  text : String,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.reading-face",
    @sub.Scope::Local,
    ReadingFaceSubscription::Load(text),
    (payload, _) => {
      guard payload is ReadingFaceSubscription::Load(text) else { return None }
      let mut active = true
      let mut loaded = text
      fn load_when_idle(text : String) -> Unit {
        @browser.when_font_faces_ready(faces, () => {
          @browser.request_idle(window, READING_FACE_IDLE_TIMEOUT_MS, () => {
            guard active else { return }
            let characters = @fonts.distinct_characters(text)
            for font in @fonts.reading_faces() {
              @browser.load_font_faces(faces, font, characters)
            }
          })
        })
      }

      load_when_idle(text)
      Some({
        unload: _ => active = false,
        update_tagger: payload => {
          guard payload is ReadingFaceSubscription::Load(next) &&
            !physical_equal(next, loaded) else {
            return
          }
          loaded = next
          load_when_idle(next)
        },
      })
    },
  )
}
