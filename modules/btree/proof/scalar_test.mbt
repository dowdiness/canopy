///|
test "splice cardinality model" {
  inspect(splice_leaf_delta(2, 5, 4), content="1")
  inspect(splice_new_count(8, 2, 5, 4), content="9")
}

///|
test "grouping model covers terminal, balanced split, and max chunk" {
  inspect(planned_group_size(4, 2), content="4")
  inspect(planned_group_size(5, 2), content="2")
  inspect(planned_group_size(8, 2), content="4")
  inspect(planned_group_total(5, 2), content="5")
  inspect(planned_group_total(70, 3), content="70")
  inspect(advance_group_sum(5, 0, 5, 2), content="2")
  inspect(advance_group_sum(5, 2, 3, 2), content="5")
}

///|
test "repair model preserves merge and steal totals" {
  inspect(repaired_node_count(1, 1, 2, 2), content="2")
  inspect(repaired_node_count(1, 1, 4, 4), content="2")
  inspect(repaired_node_count(2, 2, 4, 4), content="4")
  inspect(repaired_node_count(1, 4, 2, 3), content="3")
  inspect(repair_total_with_unaffected(7, 1, 1, 4, 4), content="9")
  inspect(repair_total_with_unaffected(7, 1, 4, 2, 3), content="12")
}

///|
test "checked-add and root lifecycle boundaries" {
  inspect(span_add_accepted(2147483646, 1), content="true")
  inspect(span_add_accepted(2147483647, 1), content="false")
  inspect(span_add_accepted(-1, 1), content="false")
  inspect(project_root_present(0), content="false")
  inspect(project_root_present(1), content="true")
}
