///|
test "CSS measurements preserve subpixels and do not turn keywords into zero" {
  assert_eq(@browser.parse_css_number("31.25px"), 31.25)
  assert_eq(@browser.parse_css_number("0"), 0.0)
  assert_true(@browser.parse_css_number("normal").is_nan())
}
