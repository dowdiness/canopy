///|
/// Parse a non-negative integer from string. Returns -1 on invalid input.
fn parse_uint(s : String) -> Int {
  if s.length() == 0 {
    return -1
  }
  for i = 0, acc = 0; i < s.length(); {
    let c = s[i]
    if c >= '0' && c <= '9' {
      continue i + 1, acc * 10 + (c.to_int() - '0'.to_int())
    } else {
      break -1
    }
  } nobreak {
    acc
  }
}

///|
fn truncate(text : String, max_len : Int) -> String {
  if text.length() > max_len {
    text[0:max_len].to_string() + "..."
  } else {
    text
  }
}

///|
/// Build a corpus from stored posts, using blended tokenizer.
fn build_corpus(posts : Array[StoredPost]) -> @echo.Corpus {
  let corpus = @echo.Corpus::new(tokenize=@tokenizer.blended)
  for post in posts {
    let _ = corpus.add_post(post.text)
  }
  corpus
}

///|
fn print_results(
  results : Array[(Int, Double)],
  posts : Array[StoredPost],
) -> Unit {
  if results.is_empty() {
    println("  (no similar posts found)")
    return
  }
  for result in results {
    let id = result.0
    let score = result.1
    let text = if id < posts.length() { posts[id].text } else { "???" }
    let display = truncate(text, 60)
    let score_pct = (score * 100.0 + 0.5).to_int()
    let score_str = if score_pct >= 100 {
      "1.00"
    } else if score_pct < 10 {
      "0.0\{score_pct}"
    } else {
      "0.\{score_pct}"
    }
    println("  #\{id} (\{score_str}) \{display}")
  }
}

///|
fn make_cli() -> @argparse.Command {
  @argparse.Command(
    "echo",
    about="Post memos and find related posts via TF-IDF similarity",
    subcommand_required=true,
    subcommands=[
      @argparse.Command("post", about="Post a memo and show similar posts", positionals=[
        @argparse.PositionArg("text", about="The memo text"),
      ]),
      @argparse.Command("similar", about="Find posts similar to text", positionals=[
        @argparse.PositionArg("text", about="Query text"),
      ]),
      @argparse.Command(
        "similar-to",
        about="Find posts similar to a stored post",
        positionals=[@argparse.PositionArg("id", about="Post ID (integer)")],
      ),
      @argparse.Command("list", about="List all posts"),
    ],
  )
}

///|
fn main {
  let cli = make_cli()
  let matches = cli.parse(argv=@sys.get_cli_args()[1:]) catch {
    err => {
      println(err)
      return
    }
  }
  match matches.subcommand {
    Some(("post", sub)) =>
      match sub.values.get("text") {
        Some([text, ..]) => cmd_post(text)
        _ => println("Error: text cannot be empty")
      }
    Some(("similar", sub)) =>
      match sub.values.get("text") {
        Some([text, ..]) => cmd_similar(text)
        _ => println("Error: text required")
      }
    Some(("similar-to", sub)) =>
      match sub.values.get("id") {
        Some([id_str, ..]) => cmd_similar_to(id_str)
        _ => println("Error: id required")
      }
    Some(("list", _)) => cmd_list()
    _ => println(cli.render_help())
  }
}

///|
fn cmd_post(text : String) -> Unit {
  let posts = load_posts()
  let id = posts.length()
  posts.push({ text, ts: now_iso() })
  if !save_posts(posts) {
    return
  }
  println("Added post #\{id}")
  let corpus = build_corpus(posts)
  let results = corpus.query_similar(id, top_n=5)
  if !results.is_empty() {
    println("Similar:")
    print_results(results, posts)
  }
}

///|
fn cmd_similar(text : String) -> Unit {
  let posts = load_posts()
  if posts.is_empty() {
    println("No posts yet")
    return
  }
  let corpus = build_corpus(posts)
  let results = corpus.query_text(text, top_n=5)
  print_results(results, posts)
}

///|
fn cmd_similar_to(id_str : String) -> Unit {
  let posts = load_posts()
  if posts.is_empty() {
    println("No posts yet")
    return
  }
  let id = parse_uint(id_str)
  if id < 0 || id >= posts.length() {
    println("Post not found: \{id_str}")
    return
  }
  let corpus = build_corpus(posts)
  let results = corpus.query_similar(id, top_n=5)
  print_results(results, posts)
}

///|
fn cmd_list() -> Unit {
  let posts = load_posts()
  if posts.is_empty() {
    println("No posts yet")
    return
  }
  for i in 0..<posts.length() {
    let post = posts[i]
    println("#\{i} \{post.ts} \{truncate(post.text, 60)}")
  }
}
