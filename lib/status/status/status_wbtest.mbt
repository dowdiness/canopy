///|
test "tone data values are stable" {
  assert_eq(Info.data_value(), "info")
  assert_eq(Success.data_value(), "success")
  assert_eq(Error.data_value(), "error")
}
