///|
/// Parse resolved line-height/padding values, not arbitrary CSS expressions.
/// Nonnumeric keywords such as `normal` keep the existing NaN behavior.
pub fn parse_css_number(value : String) -> Double {
  let view = value.view()
  @string.parse_double(view.strip_suffix("px").unwrap_or(view)) catch {
    _ => @double.not_a_number
  }
}
