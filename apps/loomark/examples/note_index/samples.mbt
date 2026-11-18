///|
/// Sample Loomark documents, most recently changed first.
let sample_texts : Array[String] = [
  (
    #|# 週末の買い物リスト
    #|
    #|- 玄米 5kg
    #|- オリーブオイル
    #|- 洗濯洗剤（詰め替え）
    #|- 来週の弁当用に冷凍ブロッコリー
  ),
  (
    #|- [ ] Reply to Mika about the venue
    #|- [x] Book train tickets for Friday
    #|- [ ] Draft the agenda for Monday's sync
  ),
  (
    #|> The best way to have a good idea is to have lots of ideas.
    #|
    #|Linus Pauling, quoted in a talk I watched on Tuesday. Pairs well with the "write badly first" advice from the writing workshop.
  ),
  (
    #|```ts
    #|export function debounce<T extends unknown[]>(fn: (...args: T) => void, ms: number) {
    #|  let timer: ReturnType<typeof setTimeout> | undefined
    #|  return (...args: T) => {
    #|    clearTimeout(timer)
    #|    timer = setTimeout(() => fn(...args), ms)
    #|  }
    #|}
    #|```
    #|
    #|Used in the autosave path. Remember that trailing calls win.
  ),
  (
    #|朝のジャーナル
    #|
    #|よく眠れた。窓を開けたら金木犀の匂いがして、もう秋なんだと気づいた。今日は午前中に原稿を一本仕上げて、午後は散歩に出る予定。
    #|最近、書く前に十分だけ何も考えずに手を動かすのが効いている気がする。
  ),
  (
    #|# Reading notes: *A Pattern Language*
    #|
    #|Each pattern describes a problem which occurs over and over again in our environment, and then describes the core of the solution to that problem.
    #|
    #|- 159 Light on two sides of every room
    #|- 180 Window place
    #|- 251 Different chairs
  ),
  (
    #|## Meeting — Design review
    #|
    #|Attendees: Ken, Sora, me
    #|Decision: keep the sidebar as one continuous list; revisit grouping after the index prototype.
  ),
  (
    #|Idea: a note index that packs cards like a skyline, so short notes don't waste space and long ones still get room to breathe.
  ),
  (
    #|1. Preheat oven to 200°C
    #|2. Toss squash with oil, salt, cumin
    #|3. Roast 25 minutes, flip once
    #|4. Finish with yogurt and chili crisp
  ),
  (
    #|# Trip to Kanazawa
    #|
    #|Day 1: Omicho market → Kenroku-en → 21st Century Museum
    #|Day 2: Higashi Chaya district, gold leaf ice cream
    #|Day 3: Train back, buy kaga-bo hojicha at the station
  ),
  (
    #|> 書くことは、考えることの一番遅い形だ。だからこそ、考えが追いつく。
  ),
  (
    #|- [ ] 確定申告の書類を集める
    #|- [ ] 住民税の通知を確認
    #|- [x] 口座の明細をダウンロード
  ),
  (
    #|Loose thoughts after the call
    #|
    #|The sync conflict story is still the most confusing part for new users. Recovery documents need a clearer explanation, maybe a one-line note at the top of the forked document.
  ),
  (
    #|# Books to read
    #|
    #|- *The Overstory* — Richard Powers
    #|- *Piranesi* — Susanna Clarke
    #|- 『百年の孤独』ガルシア＝マルケス
    #|- *Four Thousand Weeks* — Oliver Burkeman
  ),
  (
    #|```sh
    #|cd apps/loomark
    #|npm ci
    #|npm run build:styles
    #|```
  ),
  (
    #|Short one.
  ),
  (
    #|## 引っ越しの段取り
    #|
    #|1. 不動産屋に退去連絡（1ヶ月前まで）
    #|2. 電気・ガス・水道の停止と開始
    #|3. 郵便の転送届
    #|4. 粗大ゴミの予約
  ),
  (
    #|Gift ideas for Dad: a good fountain pen, the new edition of his favourite atlas, or a day trip to the coast.
  ),
  (
    #|# Weekly review
    #|
    #|What went well: shipped the export fix, kept mornings for writing.
    #|What didn't: too many context switches on Wednesday.
    #|Next week: protect two deep-work blocks, finish the essay draft.
  ),
  (
    #|> Simplicity is prerequisite for reliability. — Edsger W. Dijkstra
  ),
  (
    #|- [ ] Water the plants
    #|- [ ] Call the dentist
  ),
  (
    #|Notes from the pottery class
    #|
    #|Centre the clay before anything else. If the walls wobble, it's almost always because the centring was rushed. Wedge for longer than feels necessary.
  ),
  (
    #|# 2026 goals
    #|
    #|- Write 12 essays
    #|- Run a half marathon
    #|- Learn enough Japanese calligraphy to write a New Year card
  ),
]
