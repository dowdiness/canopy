///|
/// Reduce a page base URI to its origin (`scheme://host[:port]`).
///
/// `Context::get_base_uri` returns `document.baseURI`, which keeps the path of
/// the current page. Loomark builds API URLs as `origin + "/api/..."`, so it
/// must drop that path first. This is the same reduction Rabbita's own HTTP
/// command applies to absolute-path requests; an empty base URI stays empty.
#warnings("-alert_experimental")
pub fn origin_of_base_uri(base_uri : String) -> String {
  base_uri.split("/").take(3).join("/")
}
