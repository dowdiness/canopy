# Echo CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a one-shot CLI for posting memos and querying similar posts, persisting to `~/.echo/posts.json`.

**Architecture:** Three layers: JS FFI stubs (file I/O, args, timestamps), JSON persistence (pure MoonBit, testable), and CLI main (arg parsing + command dispatch). The `echo/` library stays untouched — all I/O lives in `echo/cmd/`.

**Tech Stack:** MoonBit (JS target), Node.js FFI for file I/O, `derive(ToJson, FromJson)` for persistence

**Spec:** [docs/plans/2026-04-04-echo-cli-design.md](2026-04-04-echo-cli-design.md)

---

### File Structure

**Create:**

| File | Purpose |
|------|---------|
| `echo/cmd/moon.pkg` | Package config: is-main, imports echo/ and echo/tokenizer/ |
| `echo/cmd/ffi.mbt` | JS FFI: read/write file, get args, home dir, mkdir, timestamp |
| `echo/cmd/store.mbt` | `StoredPost`, JSON serialization, load/save |
| `echo/cmd/store_wbtest.mbt` | JSON round-trip tests (pure, no FFI) |
| `echo/cmd/main.mbt` | `fn main`, arg parsing, command dispatch, output formatting |

---

### Task 1: Package Scaffold + JS FFI

**Files:**
- Create: `echo/cmd/moon.pkg`
- Create: `echo/cmd/ffi.mbt`

- [ ] **Step 1: Create package config**

```
// echo/cmd/moon.pkg
import {
  "dowdiness/canopy/echo" @echo,
  "dowdiness/canopy/echo/tokenizer" @tokenizer,
}

options(
  is_main: true,
)
```

- [ ] **Step 2: Create JS FFI stubs**

```moonbit
// echo/cmd/ffi.mbt

///| Read a file as UTF-8 string. Returns empty string if file doesn't exist.
extern "js" fn read_file(path : String) -> String =
  #|(path) => { try { return require('node:fs').readFileSync(path, 'utf8'); } catch(e) { return ''; } }

///| Write a string to a file (overwrites).
extern "js" fn write_file(path : String, content : String) -> Unit =
  #|(path, content) => { require('node:fs').writeFileSync(path, content, 'utf8'); }

///| Create directory recursively (like mkdir -p).
extern "js" fn mkdir_p(path : String) -> Unit =
  #|(path) => { require('node:fs').mkdirSync(path, { recursive: true }); }

///| Get command-line arguments (everything after the script path).
extern "js" fn get_args() -> Array[String] =
  #|() => globalThis.process ? globalThis.process.argv.slice(2) : []

///| Get user's home directory.
extern "js" fn get_home_dir() -> String =
  #|() => require('node:os').homedir()

///| Get current ISO 8601 timestamp.
extern "js" fn now_iso() -> String =
  #|() => new Date().toISOString()

///| Join path segments with OS separator.
extern "js" fn path_join(a : String, b : String) -> String =
  #|(a, b) => require('node:path').join(a, b)
```

- [ ] **Step 3: Add a minimal main to verify compilation**

```moonbit
// echo/cmd/main.mbt

///|
fn main {
  println("echo CLI")
}
```

- [ ] **Step 4: Verify compilation**

Run: `moon check`
Expected: PASS

Run: `moon run echo/cmd --target js`
Expected: Prints "echo CLI"

Note: If `moon run` syntax differs, try `moon run -p echo/cmd --target js` or check `moon run --help`.

- [ ] **Step 5: Commit**

```bash
git add echo/cmd/
git commit -m "feat(echo-cli): scaffold package with JS FFI stubs"
```

---

### Task 2: JSON Persistence Layer

**Files:**
- Create: `echo/cmd/store.mbt`
- Create: `echo/cmd/store_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
// echo/cmd/store_wbtest.mbt

test "StoredPost JSON round-trip" {
  let posts : Array[StoredPost] = [
    { text: "CRDTのmerge操作でバグ", ts: "2026-04-04T10:00:00Z" },
    { text: "カレーを作った", ts: "2026-04-04T11:30:00Z" },
  ]
  let json = posts_to_json(posts)
  let parsed = posts_from_json(json)
  inspect(parsed.length(), content="2")
  inspect(parsed[0].text, content="CRDTのmerge操作でバグ")
  inspect(parsed[0].ts, content="2026-04-04T10:00:00Z")
  inspect(parsed[1].text, content="カレーを作った")
}

test "posts_from_json - empty string returns empty" {
  inspect(posts_from_json(""), content="[]")
}

test "posts_from_json - invalid JSON returns empty" {
  inspect(posts_from_json("not json"), content="[]")
}

test "posts_from_json - empty array" {
  inspect(posts_from_json("[]"), content="[]")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --package dowdiness/canopy/echo/cmd`
Expected: FAIL — `StoredPost`, `posts_to_json`, `posts_from_json` not defined

- [ ] **Step 3: Implement StoredPost and JSON serialization**

```moonbit
// echo/cmd/store.mbt

///|
struct StoredPost {
  text : String
  ts : String
} derive(Show, ToJson, FromJson)

///| Serialize posts to JSON string.
fn posts_to_json(posts : Array[StoredPost]) -> String {
  posts.to_json().stringify()
}

///| Deserialize posts from JSON string. Returns empty array on any error.
fn posts_from_json(json_str : String) -> Array[StoredPost] {
  if json_str.is_empty() {
    return []
  }
  try {
    let json = @json.parse!(json_str)
    let posts : Array[StoredPost] = FromJson::from_json!(json)
    posts
  } catch {
    _ => []
  }
}

///| Get the posts file path: ~/.echo/posts.json
fn get_posts_path() -> String {
  let home = get_home_dir()
  let dir = path_join(home, ".echo")
  mkdir_p(dir)
  path_join(dir, "posts.json")
}

///| Load posts from disk.
fn load_posts() -> Array[StoredPost] {
  let path = get_posts_path()
  let content = read_file(path)
  posts_from_json(content)
}

///| Save posts to disk.
fn save_posts(posts : Array[StoredPost]) -> Unit {
  let path = get_posts_path()
  write_file(path, posts_to_json(posts))
}
```

Note: The exact `@json.parse` and `FromJson::from_json` APIs may differ. If `@json.parse!` doesn't exist, try `@json.parse?` or `@json.parse(str)` returning `Result`. If `FromJson::from_json!` doesn't work, try `@json.from_json!(json)`. Adjust based on compiler feedback.

- [ ] **Step 4: Run tests**

Run: `moon test --package dowdiness/canopy/echo/cmd`
Expected: PASS (the JSON round-trip tests use only pure MoonBit, no FFI)

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add echo/cmd/store.mbt echo/cmd/store_wbtest.mbt
git commit -m "feat(echo-cli): JSON persistence layer with round-trip tests"
```

---

### Task 3: CLI Main — Command Dispatch

**Files:**
- Modify: `echo/cmd/main.mbt` (replace placeholder)

- [ ] **Step 1: Implement the full CLI**

Replace `echo/cmd/main.mbt` with:

```moonbit
// echo/cmd/main.mbt

///|
fn print_usage() -> Unit {
  println("Usage:")
  println("  echo post <text>       — Post a memo, show similar posts")
  println("  echo similar <text>    — Find posts similar to text")
  println("  echo similar-to <id>   — Find posts similar to post #id")
  println("  echo list              — List all posts")
}

///| Build a corpus from stored posts, using blended tokenizer.
fn build_corpus(posts : Array[StoredPost]) -> @echo.Corpus {
  let corpus = @echo.Corpus::new(tokenize=@tokenizer.blended)
  for post in posts {
    let _ = corpus.add_post(post.text)
  }
  corpus
}

///| Format and print similarity results.
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
    // Truncate long posts for display
    let display = if text.length() > 60 {
      text.substring(start=0, end=60) + "..."
    } else {
      text
    }
    let score_str = ((score * 100.0 + 0.5).to_int().to_double() / 100.0).to_string()
    println("  #\{id} (\{score_str}) \{display}")
  }
}

///|
fn main {
  let args = get_args()
  match args {
    ["post", text, ..] => cmd_post(text)
    ["similar", text, ..] => cmd_similar(text)
    ["similar-to", id_str, ..] => cmd_similar_to(id_str)
    ["list", ..] => cmd_list()
    _ => print_usage()
  }
}

///|
fn cmd_post(text : String) -> Unit {
  if text.is_empty() {
    println("Error: text cannot be empty")
    return
  }
  let mut posts = load_posts()
  let id = posts.length()
  posts.push({ text, ts: now_iso() })
  save_posts(posts)
  println("Added post #\{id}")
  // Show similar posts
  let corpus = build_corpus(posts)
  let results = corpus.query_similar(id, top_n=5)
  if not(results.is_empty()) {
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
  let id = try { @strconv.parse_int!(id_str) } catch { _ => -1 }
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
  for i, post in posts {
    let display = if post.text.length() > 60 {
      post.text.substring(start=0, end=60) + "..."
    } else {
      post.text
    }
    println("#\{i} \{post.ts} \{display}")
  }
}
```

Note: `@strconv.parse_int` may need a different import or API. If it doesn't exist, try `Int::from_string(id_str)` or parse manually. The `text.substring(start=, end=)` may need `text[0:60].to_string()` based on current MoonBit API (see bigram.mbt pattern). Array pattern matching `["post", text, ..]` should work per the refactoring skill guide. Adjust based on compiler feedback.

- [ ] **Step 2: Verify compilation**

Run: `moon check`
Expected: PASS

- [ ] **Step 3: Manual test — empty state**

Run: `rm -f ~/.echo/posts.json && moon run echo/cmd --target js`
Expected: Prints usage help (no args)

Run: `moon run echo/cmd --target js -- list`
Expected: "No posts yet"

Note: The exact `moon run` syntax for passing args may need adjustment. Try:
- `moon run echo/cmd --target js -- list`
- `moon run echo/cmd --target js list`
- Build first with `moon build --target js`, then `node _build/js/debug/build/echo/cmd/cmd.js list`

Use whichever works and document it.

- [ ] **Step 4: Manual test — post and query**

```bash
moon run echo/cmd --target js -- post "CRDTのmerge操作でバグを見つけた"
# → Added post #0

moon run echo/cmd --target js -- post "共同編集にはCRDTかOTが必要"
# → Added post #1
# → Similar:
# →   #0 (0.xx) CRDTのmerge操作でバグを見つけた

moon run echo/cmd --target js -- similar "CRDT"
# → Shows posts with CRDT

moon run echo/cmd --target js -- list
# → Shows all posts with timestamps

moon run echo/cmd --target js -- similar-to 0
# → Shows posts similar to post #0
```

Verify `~/.echo/posts.json` exists and contains the posts.

- [ ] **Step 5: Run moon check, moon info, moon fmt**

Run: `moon check && moon info && moon fmt`

- [ ] **Step 6: Commit**

```bash
git add echo/cmd/
git commit -m "feat(echo-cli): post, similar, similar-to, list commands with JSON persistence"
```

---

### API Notes for Implementer

MoonBit APIs that may need adjustment during implementation:

| Planned API | Alternative if it doesn't exist |
|------------|-------------------------------|
| `@json.parse!(str)` | `@json.parse?(str)`, `@json.parse(str)` returning Result |
| `FromJson::from_json!(json)` | `@json.from_json!(json)`, manual JSON destructuring |
| `@strconv.parse_int!(str)` | `Int::from_string(str)`, manual digit parsing |
| `text.substring(start=0, end=60)` | `text[0:60].to_string()` (see bigram.mbt) |
| `text.is_empty()` | `text.length() == 0` |
| Array pattern `["post", text, ..]` | `match args { [cmd, arg, ..] if cmd == "post" => ...` |
| `for i, post in posts` | `for i in 0..<posts.length() { let post = posts[i]; ... }` |

The TDD cycle and `moon check` will catch which APIs need adjustment.
