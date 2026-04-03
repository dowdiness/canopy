test "term_freq - counts tokens" {
  let tf = term_freq(["ab", "cd", "ab", "ef", "ab"])
  inspect(tf.total, content="5")
  inspect(tf.counts.get("ab"), content="Some(3)")
  inspect(tf.counts.get("cd"), content="Some(1)")
  inspect(tf.counts.get("ef"), content="Some(1)")
  inspect(tf.counts.get("zz"), content="None")
}

test "term_freq - empty tokens" {
  let tf = term_freq([])
  inspect(tf.total, content="0")
  inspect(tf.counts.length(), content="0")
}

test "term_freq - single token" {
  let tf = term_freq(["xy"])
  inspect(tf.total, content="1")
  inspect(tf.counts.get("xy"), content="Some(1)")
}
