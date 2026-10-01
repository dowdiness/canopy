///|
test "focus traversal handles empty, missing, and boundary positions" {
  assert_eq(sidebar_focus_index(0, -1, false), None)
  assert_eq(sidebar_focus_index(0, -1, true), None)
  for count in [1, 2, 5] {
    assert_eq(sidebar_focus_index(count, -1, false), Some(0))
    assert_eq(sidebar_focus_index(count, -1, true), Some(count - 1))
    assert_eq(sidebar_focus_index(count, 0, true), Some(count - 1))
    assert_eq(sidebar_focus_index(count, count - 1, false), Some(0))
    for index in 0..<count {
      let next = sidebar_focus_index(count, index, false).unwrap()
      assert_true(next >= 0 && next < count)
      assert_eq(sidebar_focus_index(count, next, true), Some(index))
    }
  }
}
