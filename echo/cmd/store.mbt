///|
struct StoredPost {
  text : String
  ts : String
} derive(Debug, ToJson, FromJson)

///|
fn posts_to_json(posts : Array[StoredPost]) -> String {
  posts.to_json().stringify()
}

///|
/// Returns empty array only for empty/missing content.
/// Returns error message for corrupt JSON (prevents silent data loss).
fn posts_from_json(json_str : String) -> (Array[StoredPost], String?) {
  if json_str.is_empty() {
    return ([], None)
  }
  try {
    let json = @json.parse(json_str)
    let posts : Array[StoredPost] = @json.from_json(json)
    (posts, None)
  } catch {
    err => ([], Some("corrupt posts.json: \{err}"))
  }
}

///|
fn get_posts_path() -> String {
  let home = get_home_dir()
  let dir = path_join(home, ".echo")
  if !@fs.path_exists(dir) {
    @fs.create_dir(dir) catch {
      _ => ()
    }
  }
  path_join(dir, "posts.json")
}

///|
/// Load posts from disk. Aborts with error if file exists but is corrupt.
fn load_posts() -> Array[StoredPost] {
  let path = get_posts_path()
  let content = @fs.read_file_to_string(path) catch { _ => "" }
  let (posts, err) = posts_from_json(content)
  match err {
    Some(msg) => {
      println("Error: \{msg}")
      println("Refusing to overwrite. Fix or delete ~/.echo/posts.json")
      @sys.exit(1)
      []
    }
    None => posts
  }
}

///|
/// Save posts to disk. Returns false on failure.
fn save_posts(posts : Array[StoredPost]) -> Bool {
  let path = get_posts_path()
  try {
    @fs.write_string_to_file(path, posts_to_json(posts))
    true
  } catch {
    _ => {
      println("Error: failed to save posts")
      false
    }
  }
}
