///|
/// Fixtures are copied verbatim from the Loomark agent kit v0.2
/// (`fixtures/resume-a.md`, `resume-b.md`, `resume-edge.md`).
let resume_a : String =
  #|# 2026-11-25
  #|## Loomark
  #|### 試したこと
  #|- Markdownの見出しを使って分類を試した。
  #|### 判断
  #|- 抽出規則はリストの範囲から始める。
  #|### 次にやること
  #|- 既存IRを確認する。
  #|
  #|## 制作
  #|### 次にやること
  #|- 保持機構を比較する。
  #|

///|
let resume_b : String =
  #|# 2026-11-27
  #|## Loomark
  #|### 試したこと
  #|- 前回の記録を読み直した。
  #|### 判断
  #|- 先に出典の往復を試す。
  #|### 次にやること
  #|- 抽出テストを作る。
  #|

///|
let resume_edge : String =
  #|# 2026-11-28
  #|## Loomark（別実験）
  #|### 次にやること
  #|- 試験用記録を確認する。
  #|
  #|> ### 次にやること
  #|> - 引用内の例を実行する。
  #|
  #|```markdown
  #|## Loomark
  #|### 次にやること
  #|- コード内の例を実行する。
  #|```
  #|
  #|# 所属を明示していない記録
  #|### 次にやること
  #|- 未分類の候補。
  #|

///|
fn entries_of(
  document : @resume_entries.ResumeDocument[String],
) -> Array[@resume_entries.ResumeEntry] raise {
  guard document.entries is Some(entries) else {
    fail("expected a parsed document")
  }
  entries
}

///|
fn all_entries(
  documents : Array[@resume_entries.ResumeDocument[String]],
) -> Array[@resume_entries.ResumeEntry] raise {
  documents.map(entries_of).flatten()
}

///|
/// The source text each entry's range selects, in document order.
fn texts(
  documents : Array[@resume_entries.ResumeDocument[String]],
) -> Array[String] raise {
  documents
  .map(document => {
    entries_of(document).map(entry => {
      document.source[entry.start:entry.end].to_owned()
    })
  })
  .flatten()
}

///|
fn count(
  entries : Array[@resume_entries.ResumeEntry],
  project : String?,
  kind : @resume_entries.EntryKind,
) -> Int {
  entries
  .filter(entry => entry.project == project && entry.kind == kind)
  .length()
}

///|
test "R01/R02: resume-a and resume-b keep every candidate in order" {
  let documents = @resume_entries.extract([
    ("resume-a", resume_a),
    ("resume-b", resume_b),
  ])
  let entries = all_entries(documents)
  let loomark = Some("Loomark")
  let production = Some("制作")
  assert_eq(count(entries, loomark, Observation), 2)
  assert_eq(count(entries, loomark, Decision), 2)
  assert_eq(count(entries, loomark, NextStep), 2)
  assert_eq(count(entries, production, NextStep), 1)
  assert_eq(entries.length(), 7)
  // R02: the later decision does not replace the earlier one.
  assert_eq(texts(documents), [
    "- Markdownの見出しを使って分類を試した。", "- 抽出規則はリストの範囲から始める。",
    "- 既存IRを確認する。", "- 保持機構を比較する。", "- 前回の記録を読み直した。",
    "- 先に出典の往復を試す。", "- 抽出テストを作る。",
  ])
}

///|
test "R03: quotes and code are excluded and projects are not merged" {
  let documents = @resume_entries.extract([("resume-edge", resume_edge)])
  let entries = all_entries(documents)
  assert_eq(texts(documents), [
    "- 試験用記録を確認する。", "- 未分類の候補。",
  ])
  assert_eq(entries.map(entry => entry.kind), [NextStep, NextStep])
  // The trailing h1 ends the project; the later candidate is unclassified.
  assert_eq(entries.map(entry => entry.project), [
    Some("Loomark（別実験）"),
    None,
  ])
}

///|
/// R04 and the context rules: free text, an unknown title, and a kind-less list
/// are not entries; a kind without a project is unclassified; a kind persists
/// across a paragraph and ends at a deeper heading; titles are Japanese or
/// English.
test "R04: headings decide which lists are entries" {
  let source =
    #|Free text.
    #|
    #|### 判断
    #|- unclassified
    #|
    #|## P
    #|- no kind
    #|### Notes
    #|- unknown title
    #|### Next steps
    #|1. ordered
    #|
    #|Paragraph.
    #|
    #|- after paragraph
    #|#### Detail
    #|- deeper heading
    #|### Observations
    #|- english
    #|
  let documents = @resume_entries.extract([("rules", source)])
  let entries = all_entries(documents)
  assert_eq(texts(documents), [
    "- unclassified", "1. ordered", "- after paragraph", "- english",
  ])
  assert_eq(entries.map(entry => entry.project), [
    None,
    Some("P"),
    Some("P"),
    Some("P"),
  ])
  assert_eq(entries.map(entry => entry.kind), [
    Decision,
    NextStep,
    NextStep,
    Observation,
  ])
}

///|
test "R05/R09: a duplicated key is used once and an empty selection is empty" {
  let documents = @resume_entries.extract([("a", resume_a), ("a", resume_a)])
  assert_eq(documents.map(document => document.key), ["a"])
  let empty : Array[(String, String)] = []
  assert_eq(@resume_entries.extract(empty).length(), 0)
}

///|
/// Offsets count UTF-16 code units: the surrogate pair, the combining mark,
/// and the CRLF line ending each change them differently from code points. A
/// nested list stays inside its item, which ends at its last character.
test "ranges are UTF-16 offsets over whole top-level items" {
  let header = "## P\r\n### Decisions\r\n"
  let first = "- 𠮷e\u{0301}\r\n  - nested"
  let source = header + first + "\r\n- next\r\n"
  let entries = entries_of(@resume_entries.extract([("utf16", source)])[0])
  assert_eq(header.length(), 21)
  assert_eq(first.length(), 18)
  assert_eq(entries.map(entry => (entry.start, entry.end)), [(21, 39), (41, 47)])
}

///|
test "R06: a document is current only for the same key and exact text" {
  let document = @resume_entries.extract([("resume-a", resume_a)])[0]
  let edited = resume_a.replace(old="既存IR", new="現行IR")
  assert_true(document.is_current("resume-a", resume_a))
  assert_false(document.is_current("resume-a", edited))
  assert_false(document.is_current("resume-b", resume_a))
}
