///|
struct StoredPost {
  text : String
  ts : String
} derive(Show, ToJson, FromJson)

///|
fn posts_to_json(posts : Array[StoredPost]) -> String {
  posts.to_json().stringify()
}

///|
/// Returns empty array on any error (missing file, invalid JSON).
fn posts_from_json(json_str : String) -> Array[StoredPost] {
  if json_str.is_empty() {
    return []
  }
  try {
    let json = @json.parse(json_str)
    let posts : Array[StoredPost] = @json.from_json(json)
    posts
  } catch {
    _ => []
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
fn load_posts() -> Array[StoredPost] {
  let path = get_posts_path()
  let content = @fs.read_file_to_string(path) catch { _ => "" }
  posts_from_json(content)
}

///|
fn save_posts(posts : Array[StoredPost]) -> Unit {
  let path = get_posts_path()
  @fs.write_string_to_file(path, posts_to_json(posts)) catch {
    _ => println("Error: failed to save posts")
  }
}
