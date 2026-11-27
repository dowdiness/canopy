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
/// Every entry must be checkable against the exact text it came from.
fn assert_sources(
  documents : Array[@resume_entries.ResumeDocument[String]],
) -> Unit raise {
  for document in documents {
    for entry in entries_of(document) {
      assert_eq(document.source[entry.start:entry.end].to_owned(), entry.text)
    }
  }
}

///|
test "R01: resume-a and resume-b yield the expected candidates with sources" {
  let documents = @resume_entries.extract([
    ("resume-a", resume_a),
    ("resume-b", resume_b),
  ])
  assert_eq(documents.map(document => document.key), ["resume-a", "resume-b"])
  let entries = all_entries(documents)
  let loomark = Some("Loomark")
  let production = Some("制作")
  assert_eq(count(entries, loomark, Observation), 2)
  assert_eq(count(entries, loomark, Decision), 2)
  assert_eq(count(entries, loomark, NextStep), 2)
  assert_eq(count(entries, production, Observation), 0)
  assert_eq(count(entries, production, Decision), 0)
  assert_eq(count(entries, production, NextStep), 1)
  assert_eq(entries.length(), 7)
  assert_sources(documents)
  assert_eq(
    entries_of(documents[0])[3].text,
    "- 保持機構を比較する。",
  )
}

///|
test "R02: both Loomark decisions are kept in document order" {
  let documents = @resume_entries.extract([
    ("resume-a", resume_a),
    ("resume-b", resume_b),
  ])
  let decisions = all_entries(documents).filter(entry => entry.kind == Decision)
  assert_eq(decisions.map(entry => entry.text), [
    "- 抽出規則はリストの範囲から始める。", "- 先に出典の往復を試す。",
  ])
}

///|
test "R03: quotes and code are excluded and projects are not merged" {
  let documents = @resume_entries.extract([("resume-edge", resume_edge)])
  let entries = all_entries(documents)
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].project, Some("Loomark（別実験）"))
  assert_eq(entries[0].kind, NextStep)
  assert_eq(entries[0].text, "- 試験用記録を確認する。")
  assert_eq(count(entries, Some("Loomark"), NextStep), 0)
  // The trailing h1 ends the project; the later candidate is unclassified.
  assert_eq(entries[1].project, None)
  assert_eq(entries[1].kind, NextStep)
  assert_eq(entries[1].text, "- 未分類の候補。")
  assert_sources(documents)
}

///|
test "R04: no date, project, or free text is invented as an entry" {
  let source =
    #|自由文だけの段落。
    #|
    #|### 判断
    #|- 所属のない判断。
    #|
    #|## 制作
    #|見出しの下の自由文。
    #|
    #|- 種別の見出しがない項目。
    #|### メモ
    #|- 対象外の小見出しの項目。
    #|
  let documents = @resume_entries.extract([("free", source)])
  let entries = all_entries(documents)
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].project, None)
  assert_eq(entries[0].kind, Decision)
  assert_eq(entries[0].text, "- 所属のない判断。")
  assert_sources(documents)
}

///|
test "R05: a duplicated key is used once" {
  let documents = @resume_entries.extract([
    ("resume-a", resume_a),
    ("resume-a", resume_a),
  ])
  assert_eq(documents.length(), 1)
  assert_eq(all_entries(documents).length(), 4)
}

///|
test "R09: an empty selection yields no documents" {
  let documents : Array[@resume_entries.ResumeDocument[String]] = @resume_entries.extract([],
  )
  assert_eq(documents.length(), 0)
}

///|
test "a document without entries is parsed, not failed" {
  let documents = @resume_entries.extract([("plain", "# 見出しだけ\n")])
  assert_eq(entries_of(documents[0]).length(), 0)
}

///|
test "ranges are UTF-16 offsets with Japanese, emoji, and CRLF" {
  let source = "## 📦制作\r\n### 次にやること\r\n- 箱🎁を作る\r\n- 次\r\n"
  let documents = @resume_entries.extract([("crlf", source)])
  let entries = entries_of(documents[0])
  assert_eq(entries.map(entry => entry.text), ["- 箱🎁を作る", "- 次"])
  assert_eq(entries[0].project, Some("📦制作"))
  // "## 📦制作\r\n" is 9 UTF-16 code units and "### 次にやること\r\n" is 12.
  assert_eq(entries[0].start, 21)
  assert_eq(entries[0].end, 21 + 8)
  assert_eq(entries[1].start, 21 + 8 + 2)
  assert_sources(documents)
}

///|
test "nested list content stays inside its top-level entry" {
  let source = "## P\n### 判断\n- 親\n  - 子\n"
  let entries = all_entries(@resume_entries.extract([("nested", source)]))
  assert_eq(entries.map(entry => entry.text), ["- 親\n  - 子"])
}

///|
test "R06: an entry is current only for the same key and exact text" {
  let document = @resume_entries.extract([("resume-a", resume_a)])[0]
  assert_true(document.is_current("resume-a", resume_a))
  assert_false(document.is_current("resume-a", resume_a + "\n- 追記\n"))
  assert_false(document.is_current("resume-b", resume_a))
  // After an edit, re-extraction yields entries for the new text only.
  let edited = resume_a.replace(old="既存IR", new="現行IR")
  let fresh = @resume_entries.extract([("resume-a", edited)])[0]
  assert_false(document.is_current("resume-a", edited))
  assert_true(fresh.is_current("resume-a", edited))
  assert_eq(entries_of(fresh)[2].text, "- 現行IRを確認する。")
}

///|
test "heading and list forms keep the same context rules" {
  let source = "P\n-\n### 判断 ##\r- [ ] 一\r1. 二\r\n\r\n段落\r\n\r\n- 三\r#### 詳細\r- 対象外\r"
  let documents = @resume_entries.extract([("forms", source)])
  let entries = entries_of(documents[0])
  assert_eq(entries.map(entry => entry.text), ["- [ ] 一", "1. 二", "- 三"])
  assert_true(
    entries.all(entry => entry.project == Some("P") && entry.kind == Decision),
  )
  assert_sources(documents)
}
