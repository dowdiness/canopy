# 統一エコシステム長期ビジョンレポート — MoonDsp + Canopy

> 対象: 数年後を見据えた MoonDsp と Canopy の統一 MoonBit エコシステム
> 作成日: 2026-06-01
> 種別: 設計判断レポート（コンサルテーション。ここに記載する実装状態は IMPLEMENTED / ASPIRATIONAL を明示する）
> レビュー: multi-agent verify pass（~15 件の過大主張を本文に折り込み）+ Codex design-review（判定: SOUND-WITH-CAVEATS、8 findings 反映済。本文中「Codex review 反映」を参照）
> 追補（2026-06-01 ユーザレビュー反映）: §2.2.1/§2.4.1 代替案の評価軸、§5.7 外部依存の更新ポリシー、§7.8 コミュニティ戦略、§9 依存関係図+用語集
>
> 凡例: **[実装済]** = コードで検証済み / **[構想]** = ドキュメント・ロードマップ上の構想で未実装 / **[部分実装]** = 一部のみ存在

---

## 1. エグゼクティブサマリと統一エコシステム像

### 1.1 結論先出し

MoonDsp と Canopy は、**「operations-as-data の上に構築されたインクリメンタルな構造エディタ」という同一の深層構造を、音声（audio/pattern）とコード（code/AST）という2つのドメインに適用したもの**である、という見立ては **基層（substrate）のレベルで真**であり、かつ**予測力を持つ**。しかし**統合（integration）のレベルでは現時点では未実現**であり、特に「loom パーサ基盤の共有」という主張は両リポジトリで明示的に封じ込められた **[構想]** にとどまる。

この見立てを安易に「両者を1つのホットパスに融合すべき」という結論に滑らせてはならない。後述するとおり、MoonDsp の Pattern エンジン（人間の編集レート）と DSP エンジン（48kHz、no-allocation の Golden Rule）の分離は、技術的負債ではなく**それぞれの不変条件を守る load-bearing な境界**である。統合は「境界を消す」ことではなく、「共有された反応基盤の上に各ドメインの境界を残したまま、両者を同じ語彙で語れるようにする」ことを指す。

### 1.2 同一構造を1つの語彙で言い直す

両リポジトリを同じ語彙で記述すると、両者は次の同一形に還元される（finding-common-structures §1, §2）。

> **オーサリング文書 → 同一性安定な lowering → ランタイム成果物。各境界横断を incr がメモ化する。**

| 役割 | Canopy | MoonDsp |
|------|--------|---------|
| オーサリング文書 | Text CRDT (`event-graph-walker`) | `PatternDoc` / `SongDoc` (`pattern/pattern_doc.mbt`, `song/song_doc.mbt`) |
| 同一性層（安定 ID） | `NodeId` + loom `ProjectionIdentityTracker` | `PatternNodeId` / `SectionId` / `GraphNodeId` + `Revision` (`identity/identity.mbt`) |
| オーサリング→ランタイム境界型 | `ProjNode[T]` / `SourceMap` (`core/proj_node.mbt`) | `CompiledTemplate` (ADR-0010, `graph/compiled_template.mbt`) |
| ランタイム成果物 | `ViewPatch` / `ViewNode` | `CompiledDsp` / `VoicePool` |
| 開いた代数（expression problem） | `TermSym` (`pub(open)`, `loom/examples/lambda/src/ast/sym.mbt`) | `ArithSym`/`DspSym`/`FilterSym`… (`pub(open)`, `dsp/tagless.mbt`) |
| 反応基盤 | `dowdiness/incr` 0.5.2 | `dowdiness/incr` 0.6.0 |

**捨てなければならないもの（§2）**: ペイロード（コード AST vs `DspNode`/`Pat[A]`）を捨てると、両者は上記の同一形になる。捨てる必要があるのが「実装詳細」だけなら構造は本質的である — ここまでは本質的構造が成り立つ。

**構造が破れる点（§5, §6 — 反証可能な予測）**: 見立ては「loom が共有パーサ基盤になる」と予測する。これは現時点では破れている。MoonDsp の loom 利用は `specs/loom-mini-cst/`（path-dep のスパイク、publish 対象外、ADR-0012/0013 ともに Status: Proposed）に隔離され、production の mini-notation パーサは 420 行超の手書き再帰下降のままである（`mini/parser.mbt`）。loom はリポジトリ間で共有された registry 依存ですらない。

### 1.3 見立ての安全に使える範囲

- **共有が本物で収束的**: `incr` 反応基盤、`Revision`/`changed_at` 改訂スタンプによる early-cutoff のパターン、operations-as-data、安定文字列 ID の同一性規律（両者とも `[a-zA-Z0-9_\-.:]` 検証）、そして両者が独立に到達した「structure-first / text-as-projection」設計。
- **共有が構想にとどまる**: loom パーサ共有、リポジトリ間 CRDT 協調、単一 incr `Runtime` を跨いだグラフ共有。
- **見立てが過大主張になりやすい点**:
  1. **両者が同じボトルネックを共有する** という強い形は**偽**。Canopy は Eq による early-cutoff を既に持ち（`VersionedFlatProj` のスタンプ専用 Eq は **[実装済]**）、スケーリングの壁は変更検出の O(N) スキャン（1000 defs で約8.5ms、16ms バジェットに迫る）と reconciliation の O(m×n) LCS にある。一方 MoonDsp は `DspNode`/`CompiledTemplate` に **Eq がない**（NaN ポリシー未決、ADR-0010）ため early-cutoff 自体を持たない。「インクリメンタルにする」が両者で意味する作業は異なる。
  2. **operations-as-data は MoonDsp 側で部分的にしか真でない**。`PatternDoc` は変換関数（`FilterMap`/`Every`/`Jux`）を不透明なクロージャとしてノード内に保持しており、シリアライズも構造的比較も wasm 境界越えもできない。CRDT 共有の前提として、これらを enum variant へ defunctionalize する設計が必要（未着手の Phase 9 前提条件）。

### 1.4 統合は「基層ファースト、パーサラスト」で進める

見立てが本物である基層（incr + 同一性 + ops-as-data）から統合を進め、構想であるパーサ共有（loom）はクリティカルパスから外す。具体的には canopy#419/#422-424（MoonDsp graph DSL を Canopy の言語として取り込む）は、Canopy の projection/semantic contract が安定するまでブロックしたまま据え置く — これは現状のスコープ設定が正しい。

---

## 2. MoonDsp の拡張と統合 (axis: moondsp-extension)

### 2.1 ControlMap 境界は維持し、豊かにする — 融合しない

Pattern エンジンと DSP グラフは **「never share a hot path」**（Vision INTENT, `docs/salat-engine-blueprint.md`）である。Pattern は `Pat[A]`（遅延クエリクロージャ `(TimeSpan) -> Array[Event[A]]`）でクエリごとに自由にアロケートし、DSP 側は事前確保された flat な `CompiledGraph` で no-allocation の Golden Rule を守る。2つの時間ドメイン（編集レート vs 48kHz オーディオレート）と2つのアロケーション体制を持つ。`ControlMap`（`pub struct ControlMap(Map[String, Double])`、`pattern/control.mbt:3` で検証済）は「意図的に狭い橋」であり「唯一の値契約」である。

この分離は技術的負債ではなく、各側が自身の不変条件を保つための境界である（design-principle §2: 二項対立の枠組みを疑う）。正しい長期手は **融合ではなく、ControlMap の橋を豊かにし反応的にする** ことである。

### 2.2 最優先・最高レバレッジの API 変更: ControlMap タイピングの二分割

ADR-0007 の stringly-typed `ControlMap` は MoonDsp 全サブコーパスで LIMIT/RISK として再出する（綴り間違いをコンパイラが捕捉できない、値ドメイン検証なし — `control_binding.mbt:123` が文字通り「Values are passed through without domain validation.」と記す）。延期されている2つのニーズは**分離して計画すべき**である。

1. **KEY 検証** — 制御キーの**宣言済 registry / schema**（綴り検証用）。スケジューラのセマンティクスに依存せず**今すぐ実装可能**。綴り間違いによる silent no-op クラスを消す。**閉じた global enum は採らない** — 任意のバインディングキーは既存の拡張点（`pattern/control.mbt`, `graph/control_binding.mbt`）であり、閉じ enum はそれと衝突する（design-principle §2 二項対立を疑う / §7 拡張点予約。Codex review 反映）。
2. **VALUE-DOMAIN タイピング**（Hz vs MIDI note vs 正規化 [0,1]）と **EXPRESSION フィールド**（velocity/articulation/groove/nudge）— これらは未決のスケジューラ groove/rubato セマンティクスと `BlockFrame` の `whole.end_` スタブ（ADR-0006, 「future groove/rubato layers can expire voices against audio time」）に真に依存する。

`ControlMap` は newtype + アクセサ API（`get`/`set`/`merge`/`entries`/`each`）で呼び出し側をタプルフィールドから隔離しており、型付きフィールドの追加は additive である（design-principle §7: 拡張点を予約）。**near horizon で KEY 検証を出荷し、expression フィールドはスケジューラセマンティクス確定までゲートしたまま**にする。

#### 2.2.1 KEY 検証の代替案と評価軸

| 案 | 型安全 | 拡張点との両立（任意キー） | 実装コスト | 推奨 |
|----|--------|---------------------------|-----------|------|
| A. 現状維持（stringly） | ✗ 誤入力が silent no-op | ◎ 完全に開いている | ゼロ | ✗ — 既知のバグクラスを残す |
| B. 閉じた global enum | ◎ コンパイラが捕捉 | ✗ 新キーごとにライブラリ編集。既存の任意バインディングキー拡張点と衝突 | 中（全 callsite 移行） | ✗ — design-principle §2/§7 違反 |
| C. **宣言済 registry / schema** | ○ 登録キーはビルド時検証、未登録は明示エラー | ◎ 言語/拡張ごとにキー集合を宣言でき開いたまま | 小〜中（registry + lookup） | **◎ 採用** |

評価軸: 型安全 / 拡張点（任意キー）両立 / 実装コスト。案 C は「綴り検証」と「拡張性」の二項対立（design-principle §2）を解く — registry がキー集合を*宣言*し、宣言の追加は additive。

### 2.3 単一の根本修正: position-based → identity-based ノード照合

ホットスワップとトポロジ編集の状態整合性には、振る舞いの異なる2つのギャップがある（finding-common-structures §4: 効果を原因に遡る）。

- **直接ホットスワップ** (`graph/graph_hotswap.mbt:25,34`): 内部ノード状態を移行しない。置換グラフは新規コンパイル状態から開始 → オシレータ位相・フィルタ履歴・ディレイバッファがリセットされ、クロスフェード境界で可聴な不連続が生じる。
- **トポロジ編集** (`graph/graph_topology_controller.mbt:366-394`): 状態を保存するが (authoring index, node kind) で照合する **position-based**。既存位置で kind が変わると状態を silently discard し、ディレイ状態は「バッファ容量が一致する場合のみ」コピー（:394 で検証済）。

両方の修正は**1つの欠けた能力に収束する**: 新旧テンプレート間の **identity-based ノード照合**。下地となる型は既に存在する — `GraphTemplateDoc`（`Array[@identity.GraphNodeId]` を保持）と `GraphIndexMap` は `graph/graph_identity.mbt` で実装・テスト済（`graph_identity_test.mbt`）。

> **訂正済の正確な状態**（verifier 指摘）: 当初の「`GraphNodeId` をどの authoring パッケージも消費していない」は誤り。`graph/graph_identity.mbt` が `GraphNodeId` を広範に消費している。未配線なのは **`GraphTemplateDoc` の `CompiledDspTopologyController` への統合**であり、トポロジコントローラは `CompiledGraph.index_map`（`FixedArray[Int]`、authoring-position ベース）を使い、`GraphNodeId` ベースの同一性を使っていない。

### 2.4 graph-template の incremental memoization を解錠する単一の延期: `DspNode`/`CompiledTemplate` への Eq

`graph/graph_node.mbt:111` の `pub struct DspNode {` には derive 句がない（一方 enum `DspNodeKind`/`GraphParamSlot`/`GraphControlKind` はすべて `derive(Eq)`、検証済）。`CompiledTemplate` にも Eq がない。これは MoonDsp Graph/Voice/Identity/Vision の全コーパスで「Phase 6+ の incr early-cutoff のブロッカー」と同一名で呼ばれる。**ただし正確には、これがゲートするのは graph-template（`CompiledTemplate`）の incremental memoization であって Phase 6 全体ではない** — Phase 6 のインクリメンタル playback 設計（moondsp `docs/superpowers/specs/2026-05-12-phase6-incremental-playback-design.md`）は audio hot path より上の段に明示的にステージされる（Codex review 反映）。周辺機構はすべて整って待機している: `Revision` の `combine`/`max`（`identity/identity.mbt:42-56`）、純関数の `CompiledTemplate::analyze`（ADR-0010 が「incr Memo cell の入力に適する」と明記）。

ゲートは**単一の設計判断 — NaN 等価ポリシー**（構造的 `NaN == NaN` vs IEEE `NaN != NaN`）である。これがコーパス中で最も明快な「拡張点予約」成功例であり、NaN コールが決まれば全てが additive になる。**これは見立ての「共有基層」半分が依存する前提条件**でもある。

#### 2.4.1 NaN 等価ポリシーの代替案と評価軸

`DspNode`/`CompiledTemplate` の Eq を早期カットオフに使うには、パラメータに混入しうる NaN（除算・log・未初期化）の等価をどう定義するかを決める必要がある。

| 案 | early-cutoff 健全性 | IEEE 準拠 | パラメータ起源の NaN への頑健性 | 実装コスト |
|----|--------------------|-----------|-------------------------------|-----------|
| A. 構造的 `NaN == NaN`（bit 比較） | ◎ 同一テンプレートは必ず等価判定 → 再 analyze をスキップ可 | ✗ IEEE と乖離 | ◎ NaN を持つテンプレートも安定に dedup | 小（`Double::reinterpret_as_uint` で bit 比較） |
| B. IEEE `NaN != NaN` をそのまま | — | ◎ | ✗ NaN を含むと常に「変化した」と誤判定 → early-cutoff が無効化 | ゼロ（derive 既定） |
| C. 正規化（NaN→canonical bits）後に Eq | ◎ | △ 正規化境界で IEEE と乖離 | ◎ | 中（正規化パス追加） |

評価軸: early-cutoff 健全性 / IEEE 準拠 / NaN 頑健性 / 実装コスト。incr のメモ化は「等しければ再計算しない」を健全性の前提とするため、**案 A（または C）が early-cutoff の要請に整合**し、案 B は NaN 混入時に黙って early-cutoff を殺す。最終判断は MoonDsp 側の設計レビューで確定すること（本レポートは選択肢と軸の提示にとどめる）。

### 2.5 スケーラブル realtime: 満たされた部分と構造的に欠けた部分

| ニーズ | 状態 | 根拠 |
|--------|------|------|
| ポリフォニー | **[実装済]** 良好 | 32スロット `VoicePool`（`max_voices?` 既定32、設定可）、generation-tagged ハンドル（ABA安全。ただし「lock-free」はコード上の主張ではなく単一スレッド AudioWorklet 内の推論）、3層スティーリング。8 voices 28.54µs vs 2.67ms バジェット。制約: O(max_voices) 線形スティール走査、voice ごとに新規 `CompiledDsp` コンパイル |
| マルチトラック | **[構想]** 欠落・重大ギャップ | 「single PatternScheduler + BoundVoicePool で1トラック。共有トランスポートなし、クロストラック同期なし」。ブラウザのドラムスケジューラは per-pool pair で回避しているがスケールしない |
| 長時間セッション | **[部分実装]** リスク | `active_notes` は無制限の plain Array、ブロックごとに O(active) 走査（ただし swap-remove は O(1)）。`Song::query` は呼び出しごとに結果 Array を新規アロケート（wasm-gc GC 圧）。`sample_counter` の Int64 オーバーフローは ~600万年で実質無関係 |
| オフライン/非リアルタイムレンダ | **[構想]** 欠落 | `voice/scheduler/song/` に offline 参照なし。ただし block-processing アーキテクチャ上ほぼ無償（§2.6） |
| 遅延ロード | **[構想]** 欠落 | 全 `SectionOccurrence` body が Song 構築時に完全マテリアライズ |
| サブブロックタイミング | **[構想]** 延期 (ADR-0006) | 速いテンポで可聴 |

コンパイル済グラフ + voice-pool のコアは realtime に堅牢である。ギャップはすべてその上のオーケストレーション層（transport, song materialization, render mode）にあり、それらが配置されるべき正しい場所である。

### 2.6 オフラインレンダはほぼ無償

オフラインパスは存在しないが、設計は最小の新規サーフェスでそれを支える構造をすでに持つ（§6: 構造に予測させる）。オーディオエンジンは離散ブロック処理として組まれている: `PatternScheduler::process_block` / `process_song_block` は1呼び出しで ~128サンプルブロックをレンダし、`PerformanceTime`/`BlockFrame` が論理 Rational 時間と絶対サンプル位置を分離する（ADR-0006）。オフラインレンダは「同じ `process_*_block` 呼び出しを、realtime クロックなしのタイトループで成長するバッファに書き込む」だけである。

**構造が立てる予測**: オフラインモードは realtime と**同じブロック量子化アーティファクト**を露呈する。ADR-0006 に触れずに sample-accurate を謳う将来のオフラインレンダラがあれば、その主張は誤りである。よって sample-accuracy が必要ならサブブロック延期の解除とセットにすること。

### 2.7 競合差別化 — モートは未証明の persistence であり、エディタモデルではない

MoonDsp は Strudel/TidalCycles を明示的なインスピレーション源とする（`Pat[A]` は「時間アークに対する遅延クエリとしてのパターン」洞察そのもの）。差別化は構造的に本物: (a) 1つのコードベースが browser-wasm と（計画段階の）native CLAP プラグインへコンパイル、(b) 型付きオーサリング→ランタイム境界（`CompiledTemplate`）を伴う zero-allocation オーディオスレッド。ただし CLAP（Phase 8）は MoonBit C/LLVM バックエンドの成熟にハードブロックされ、offline-render エントリポイントも存在しないため、native モートは **[構想]** である。

---

## 3. データ永続化と協調編集 (axis: persistence-collab)

### 3.1 コーパス前提の訂正: Canopy は「メモリのみ」ではない

旗艦 Ideal エディタは CRDT スナップショットを localStorage に永続化している。`examples/ideal/web/src/main.ts:117-118,131-132` が `crdt.export_all_json(handle)` を呼び、エクスポートした op-log 全体を room キー（`STORAGE_KEY_PREFIX='canopy-doc-'`）で localStorage に書き、:339-349 でロード時に復元、reset 時にキー削除する。`export_all_json` は実 FFI export（`ffi/lambda/moon.pkg`, `.mbti` 行50で `pub fn export_all_json(Int) -> String`）である。

ただし以下の caveat が根底のギャップを大部分残す:
- `export_all_json` FFI export は **`ffi/lambda` のみ**。json と markdown バンドルには存在しない。
- localStorage 永続化は **`examples/ideal/web` のみ**。
- 保存ごとの**全スナップショット書き換え**であり、増分 op append ではない → 無制限 op-log 成長を継承し、毎回直列化ログ全体を書き直す。
- relay Durable Object はドキュメント状態を保持しない（メンバシップ/ルーティングのみ）。
- ローカル開発 relay には **SQLite-backed op store**（`examples/ideal/web/server/store.ts`, better-sqlite3, `MAX_OPS = 10_000` + `evictOldOps`）が存在する。

> **正確な言明**: Cloudflare 本番デプロイ（relay-server Durable Object）は durable persistence なし。ローカル開発 relay は SQLite による永続化を持つ（capped 10,000 ops, eviction 付き）。client-side CRDT スナップショット/compaction が真のギャップ。

### 3.2 op-log ポータビリティは両エコシステムで強く対称的

- **Canopy**（責務マップ — 「SyncMessage」は層ごとに別物なので区別する）: **egw テキスト/コンテナ層**は per-layer エクスポートを RLE 圧縮 `OpRun` 配列 + frontier heads として**人間可読 JSON**で直列化（`event-graph-walker/text/sync.mbt`）し、`RawVersion={agent,seq}` がポータブル同一性。container は tree op を text op より先に replay する（`event-graph-walker/container/document.mbt`、ブロックがテキストの前に存在）。**editor 転送層**（`editor/sync_protocol.mbt`）はこれと別物で、**binary フレーム version `0x02`・7 variant**（§4.5 訂正参照）。delta sync は `export_since(peer_version)` を `VersionVector` 上で（`editor/sync_editor.mbt`）。当初の「Container SyncMessage が tree_ops/text_ops を型レベルで二分する」記述は §4.5 で発明と判明したため撤回する（Codex review 反映）。
- **MoonDsp**: `identity/` が検証済文字列 ID newtype + `Revision`（単調カウンタ + 多項式フィンガープリント）を提供。

1語彙で言い直すと、両者は「ソースに安定ポータブル同一性を登録し、因果/改訂順で operations を replay する」。Canopy は Lamport + 因果グラフ親、MoonDsp は vector-clock/content-address 形の `Revision` トークン。構造は本物だが、MoonDsp 側は **[構想]**: `Revision` は incr セルに配線されていない（`pattern_doc.mbt`/`song_doc.mbt` のドキュメント改訂追跡には使うが early-cutoff には未配線）、CRDT operation 設計（Phase 9）は未着手。

> 訂正: 「MoonDsp に incr 消費者がない」は不正確。`mini/incr_authoring.mbt`（`MiniAuthoringPipeline`）が `@incr.Scope`/`Signal`/`Memo` を能動的に使う。incr 自体は使われている — `Revision` と incr が**接続されていない**だけ。

### 3.3 再現性は各システム内で成り立つが、Canopy の op-log replay 安全性に文書化済のハザード

- **(1) Recovery バッファ上限**: `RecoveryContext` は最大32の遅延メッセージをバッファし古いものをドロップ。`editor/recovery.mbt:5` `max_deferred = 32`、:51-54 が「dropping messages can break convergence if the dropped message contains causal history needed by later messages」と明記。recovery ウィンドウ中にフラッディングするピアはそのピアの収束を**恒久的に破壊**しうる。
- **(2) カウンタオーバーフロー**: `VersionVector`/`CausalGraph` は wasm-gc 上で32ビット Int（`internal/causal_graph/graph.mbt:13` `priv mut next_lv : Int`、オーバーフローガードなし）。~21億 ops/agent で silently オーバーフロー。
- **(3) BFT/auth なし**: protocol flags バイトが恒久的に `0x00`（`editor/sync_protocol.mbt:64` `// flags: no BFT`）。任意のピアが任意の `CrdtOps` を注入でき、適用される。

数年規模の個人ナレッジベース op-log は、まさに32ビットカウンタと無制限 tombstone 成長が噛む領域である。

### 3.4 op-log 成長は無制限で compaction/GC なし — 両システムで巨大文書の支配的スケール限界

- **Canopy**: tombstone（削除済 `FugueTree` item）は決して除去されない（`internal/fugue/item.mbt:85` 「Items are never removed」）。OpLog RLE 配列は成長のみ。Container `TextBlock` は sparse 配列で global LV が per-block 配列を index する（`container/text_block.mbt:3-6`、LV 50,000 から始まるブロックは 50,001 スロット確保）。tree op undo-do-redo は remote op ごとに O(k)。reconciliation は same_kind 上の O(m×n) LCS。
- **MoonDsp**: `active_notes` は無制限 plain Array、`Song::query` は呼び出しごとアロケート。
- **共有基層**: incr の `InternTable` も grow-only（Phase 4E GC 延期）— 反応層でも同じ無制限成長形。

両システムが延期する同一の基層ニーズ: **snapshot/compaction**。

### 3.5 serverless vs central-server — 両者とも Cloudflare static+DO で serverless-first

- **Canopy**: relay は Cloudflare Worker + Durable Object。全 room ロジックは MoonBit `relay/relay_room.mbt`（`RelayRoom` は live peer の send callback のみ保持、設計上ステートレス）。JS グルー（`examples/relay-server/src/index.ts`）は86行。DO はドキュメント状態を保持しない。
- **MoonDsp**: `wrangler.jsonc` の `moondsp` worker には Worker スクリプトがない（Vite バンドルの純静的アセット配信）。COOP/COEP ヘッダなし → SharedArrayBuffer + Atomics を使えない。

**軸の結論**: 両者に central-server profile を提供するために欠けているピースは同一 — 同じ `SyncMessage`/op-log ワイヤ形式を broadcast-only（P2P/serverless）にも DO storage への append（central）にもできる、ステートレス-relay-OR-ステートフル-DO トグル。Canopy の `pub(open) trait SyncTransport`（`editor/sync_protocol.mbt:2`）が正しい seam。MoonDsp にはまだ等価なトランスポート抽象がない。

### 3.6 diff/merge — Canopy は自動 conflict-free merge、MoonDsp はクロージャが構造 diff を阻む

- **Canopy**: テキスト merge は FugueMax の maximal-non-interleaving（arXiv:2305.00583）。tree merge は決定論的 cycle-Skip + (timestamp, agent) LWW。composable-not-merged 設計（1つの `CausalGraph` 下の分離した tree/text op-log）が map/register CRDT 追加の拡張 seam。ephemeral/awareness 層は意図的に CRDT でない（`ephemeral/ephemeral.mbt` の LWW、カーソル/プレゼンス用には正しい）。
- **MoonDsp のブロッキング構造制約**: `PatternDoc` が変換関数（`FilterMap`/`Every`/`Jux`）を**不透明クロージャ**として保持。シリアライズ・構造比較・wasm 越え不可。これが `lower()` が一方向である構造的理由。

**見立てへの帰結**: Canopy の operations-as-data は真に diffable/mergeable（`ProjectionEdit`/`TreeMoveOp`/`TextInsertOp` は具体値型）。MoonDsp のパターン operations は一級関数値を埋め込むため **operations-as-data が部分的にしか真でない**。Canopy の CRDT merge エンジンを共有するには、MoonDsp はまずクロージャ持ちパターンノードを enum variant へ **defunctionalize** する必要がある（未設計の Phase 9 前提）。

---

## 4. 言語・DSL 拡張と互換性 (axis: lang-dsl-interop)

### 4.1 ViewMode は構想 — 見立てが仮定する dispatch 層は存在しない

`ViewMode`（Structure/Formatted/Debug/Source）は `docs/architecture/multi-representation-system.md` 行99-102 にのみ存在し、production `.mbt` に first-party のヒットゼロ。Printable trait family は**実在**する（`loom/pretty/traits.mbt`: `trait Source { fn to_source }`, `trait Pretty { fn to_layout(Self) -> Layout[SyntaxCategory] }`, `Printable = Show+Debug+Source+Pretty`）。だが「protocol 層が representation family 間を dispatch する」統一 enum は vapor。今日 `Layout` を消費するレンダラは `layout_to_view_tree`（`protocol/formatted_view.mbt`）のみで、`render_html`/`render_ansi`/`render_latex` はすべて **[構想]**。

**中心的問いへの判定**: family は既存の `Layout[SyntaxCategory]` 軸に沿って新しい**テキスト**表現を trait 変更なしで吸収できるが、それらを統一された言語ごとサーフェスへ吸収する dispatch 背骨は実装されておらず、構築する必要がある（`ViewMode` enum + `category_to_role` 風 dispatcher）。

### 4.2 新表現は2クラスに分かれ、無償なのは片方だけ

- **(a) テキスト形式の投影**（`render_html`/`render_ansi`/ANSI 着色型付き記法）: `Pretty::to_layout` を消費する `render_*` 関数を追加するだけ。**新 trait 不要**。
- **(b) 構造形式 / semantic オーバーレイ投影**（doc アノテーション, type-at-cursor, scope グラフ, グラフビュー）: 既存 Printable family では運べない。`Layout` は閉じた `SyntaxCategory` enum（`Keyword`/`Identifier`/`Number`/`StringLit`/`Operator`/`Punctuation`/`Comment`/`Error`/`EvalAnnotation`/`EvalError`）でのみ注釈された flat トークンストリーム。クラス (b) は別機構で供される: `NodeId` side table（`Map[NodeId,V]` を `@incr.Derived` セルとして）+ `ViewNode` 上の `ViewAnnotation`（`protocol/view_node.mbt:25-47`、実装済）。

正直な答え: テキスト表現は新 trait 不要。semantic/構造表現も side-table 経由なら不要だが、(1) アノテーション種が4+ 言語で ~10 を超えたら capability-trait スキーム（`HasSourceMap`/`HasEvalResults` — `extensible-asts.md` で「Premature now」と延期）が必要になり、(2) `SyntaxCategory` を閉じたままにすると各 `TypeAnnotation`/`ScopeRef`/`WarningMarker` がライブラリ編集と `category_to_role` 呼び出し点へのカスケードを強いる。

### 4.3 新言語追加は実装済・汎用だが、型付き記法/doc アノテーション言語は閉じ enum と 7-location の壁に当たる

新言語パスは genuinely **[実装済]** で最小: AST に `TreeNode`+`Renderable` を実装（`ProjNode[T]` は完全汎用、`core/proj_node.mbt`、T は2 trait のみで束縛）→ `proj_node.mbt` + `populate_token_spans` + 3-memo builder + edit-op dispatcher + FFI を追加。3言語（Lambda/JSON/Markdown）が証明し、reconciliation（same_kind 上 LCS）が安定 NodeId を無償提供する。これが MoonDsp graph DSL を Canopy 言語として構文レベルで吸収する（canopy#422-424 + `docs/development/audio-dsl-reactive-foundation.md` がドラフト済・未構築のパス）。

ただし2つの実装済弱点が露呈:
1. **7-location の壁**: Lambda の tagless `TermSym` は新 variant ごとに2リポジトリ跨ぎ7箇所（`sym.mbt` ×3, `proj_traits_mechanical` ×3, `proj_node` rebuild_kind）の編集を要する（codegen の `loomgen` は **[構想]**）。型付き記法 = 多数の新 variant = この壁。**注**: canopy 側の 7-location は `loom/examples/lambda` 内（`TermSym` は loom サブモジュール内）。
2. **閉じた enum 拒否**: doc アノテーションは新 semantic カテゴリを欲するが `SyntaxCategory` が拒む。
3. **Markdown の不整合**: Markdown は `TreeNode`+`Renderable` のみで **Printable（Source/Pretty）を実装していない**。formatted-view パイプラインが既存3言語間で既に不整合。

### 4.4 MoonBit↔Rust interop は皆無・未計画。TS/JS が唯一の実 interop で stringly-JSON

タスクは「MoonBit↔Rust/TS の長期相互運用と FFI 層再設計の計画」を求める。地表真実: **MoonBit↔Rust interop はどこにも存在せず計画もない**（first-party に `native_stub.c` も `extern "C"` もなし。incr ドキュメントは Salsa を inspiration として挙げるが Rust interop は計画なし）。唯一の interop は `extern "js"`: 3つの言語別 JS バンドルが flat な C 形式関数（Int handle → JSON String）を export し、TS 側の `CrdtModule` インターフェースが境界越えの静的チェックなしで手動ミラーする。

再設計対象の3戦線:
1. **cross-language coordinator**: 3バンドルが各々 module-scope `@incr.Runtime` を持ち、ESM 隔離が共有ヒープを禁ずる。3つのスケッチ（merged bundle / globalThis-coalesced / opaque-handle）はすべて Phase 2 へ延期。
2. **wasm ターゲット延期**（Canopy TODO §1）— MoonDsp 全体が wasm-gc なので Canopy↔MoonDsp 共有グラフは JS-バンドルと wasm-gc 世界を跨ぐ。
3. **文字列マーシャリング税**: MoonDsp のブラウザ ABI は UTF-16 code unit を char ごとループ（非 BMP 破損リスク、moji で Canopy が戦った Unicode 落とし穴）。

**一貫した長期 FFI 計画は、統一基層が「共有 wasm-gc ヒープ」か「直列化 op-protocol」かを排他的に選ばねばならない — 両方を答えにできない。**

### 4.5 後方互換性のための拡張点インベントリ（不均一）

**強い・将来安全な点**（design-principle §7）:
- `UserIntent.StructuralEdit{op:String, params:Map[String,String]}` — 新 op に protocol enum 変更不要
- `SourceMap` の token role（自由形式 `Map[NodeId, Map[String, Range]]` キー）
- `NodeId` side table / `ViewAnnotation`
- `SyncTransport` `pub(open)`（新トランスポート型に開いている）
- MoonDsp `GraphNodeId`（authoring wrapper `GraphTemplateDoc` で消費済 — ただし `CompiledDspTopologyController` の state migration へは未配線。§2.3 と整合させ「予約・未消費」から訂正）と `Revision.combine/max`（incr early-cutoff 予約）

**弱い・BC 敵対的な点**:
- **open 文字列 dispatch**（`StructuralEdit` op + token role）は型安全を放棄。誤入力 role は silently `None`。op 文字列はどの schema/registry にもない。`Drop` は2 NodeId、`InsertChild` は再帰 Term を要するため `Map[String,String]` は `Map[String,Json]` へ拡幅が必要（受諾済だが**未出荷**）。
- **閉じた enum で拡張ストーリーなし**: `SyntaxCategory`, `GenericTreeOp`。
- ワイヤ形式は人間可読 JSON で legacy `'ops'` キーデコーダが既に存在（de-facto バージョニング seam）だが projection/`ViewPatch` JSON に明示的 schema-version フィールドがない。

> **訂正済**（verifier 指摘、folded in）: `SyncMessage` の「tree_ops/text_ops 二分」は production source に存在しない発明であった — 実際の `SyncMessage` は `CrdtOps(Bytes)` / `EphemeralUpdate` / `SyncRequest` / `SyncResponse` / `PeerJoined` / `PeerLeft` / `RelayedCrdtOps` の7 variant（binary 符号化、version `0x02`）。また `EphemeralNamespace` は `pub(open)` ではなく**閉じた `pub(all)` enum**（4 variant: Cursor/EditMode/Drag/Presence）で、新チャネル追加はライブラリ編集を要する弱い拡張点である。

**推奨 BC ポリシー**: (1) `StructuralEdit` params を `Map[String,Json]` へ拡幅（LLM/構造編集の前に出荷）、(2) 言語ごとの宣言済 op/role registry でビルド時に誤入力を捕捉、(3) `ViewPatch`/`ProjNodeJson` に schema-version フィールド（sync protocol の version バイトを鏡映）、(4) open 文字列 dispatch は型付き schema が真に時期尚早な箇所のみに限定。

---

## 5. エコシステムと周辺コンポーネント (axis: ecosystem-external)

### 5.1 外部コンポーネントの3リスククラス

| コンポーネント | クラス | 状態と判断 |
|---------------|--------|-----------|
| Graphviz / SVG-DSL | 低リスク first-party | `lib/visualizer` の `VisualGraph` 背後に既に抽象化。維持・無対応。Sugiyama レイアウト品質の C Graphviz 差は品質リスク（保守リスクではない） |
| Rabbita | 最高長寿リスク | un-upstream フォーク（`heads/patch/diff-subs-update-tagger` ブランチ pin、release tag でない）、JS-only、Canopy-only（MoonDsp は CM6+Lezer TS で MoonBit UI フレームワーク不使用）。editor-adapter seam 背後に封じ込め、パッチ upstream か恒久保守かを決定 |
| ProseMirror+CodeMirror | 成熟 upstream・深い境界負債 | 両プロダクトで共有（MoonDsp は canopy CM6Adapter を vendoring）。リスクは upstream 放棄でなく型チェックなしの MoonBit↔TS↔PM seam。patch protocol 硬化（`Map[String,Json]` 拡幅、`SetCursor` 座標系曖昧性解消）が共有投資 |

> **vendoring SHA ドリフト**（verifier 指摘）: MoonDsp の canopy アダプタは少なくとも2スナップショットから vendoring されている — `types.ts` は canopy `9df029d`、`cm6-adapter.ts` は `6f1d5c2`。永続データ寿命主張のスナップショット規律リスク。

### 5.2 incr バージョンスキューは共有 Runtime の必要条件（ただし十分条件ではない）

検証済:
- canopy root `moon.mod.json:24`: `dowdiness/incr` **0.5.2**
- `lib/cognition/moon.mod`: incr **0.6.0**
- MoonDsp `moon.mod`: incr **0.6.0**

つまり canopy のメインワークスペースは自身の cognition ライブラリと MoonDsp の両方から1マイナー遅れ、かつ **canopy 内部でもスキュー**している。0.6.0 は target-facade コンストラクタ（`Input`/`Derived`/`ReachableDerived`/`DerivedMap`）を追加し `Derived` read シグネチャを変更、互換ハンドル（`Signal`/`Memo`/`HybridMemo`/`MemoMap`）は**削除日なし・deprecation 属性なし**で残存。

単一の判断（バージョン調整機構の不在）が3つの失敗を同時に生む（finding-common-structures §4）: (a) クロスリポジトリ共有 Runtime が整列まで不可能、(b) 将来の incr 1.0 が互換ハンドルを削除すると両者が同時移行を強いられステージング余地なし、(c) 内部 cognition/main スキュー。Single-Runtime 制約（cross-runtime read は abort）により、共有グラフを試みるには両 consumer が同じ incr ビルドである必要がある。**ただしスキュー解消は共有 Runtime の必要条件であって十分条件ではない**: §4.4 が示すとおり3つの言語別 JS バンドルが各々 module-scope の `@incr.Runtime` を持ち ESM 隔離が共有ヒープを禁ずるため、スキューを揃えても heap-isolation のブロッカーが別途残る。スキューは「ルート原因ではなく1つのブロッカー」として扱う（Codex review 反映）。

> **訂正済**: 当初言及した `scripts/migrate-to-target-facades.py` は canopy root の `scripts/` に**存在しない**。実体は `canopy/loom/incr/scripts/migrate-to-target-facades.py` および standalone `incr/scripts/` にある。バージョンギャップ自体の証拠は確かだが、codemod の所在は訂正する。

### 5.3 loom のロードマップ影響は非対称

loom は Canopy では production path-dep（全3言語が `LanguageSpec[T,K]` 経由でインクリメンタル parse/CST/recovery/subtree-reuse を取得）。MoonDsp では `specs/loom-mini-cst/` 下の path-dep スパイクのみ（ADR-0012/0013 Status: Proposed、publish モジュールから除外）。MoonDsp が loom を production 昇格するには (a) loom+seam の mooncakes publish、(b) loom をグラフに含む完全な moondsp wasm-gc/AudioWorklet ビルドの証明（ADR-0012: loom は isolation でのみ wasm-gc を通過）が必要。loom#150（standalone build の EGW reference）は未解決。

### 5.4 サブモジュール sprawl と二重 vendoring

`.gitmodules` 検証: canopy は8直接サブモジュール宣言、loom 自身が4ネストサブモジュール（incr, egraph, egglog, event-graph-walker）を宣言。**event-graph-walker は `canopy/event-graph-walker` と `canopy/loom/event-graph-walker` の両レベルに出現**。各層が独立した merge gate（メモリ `feedback_verify_submodule_nesting` が既にフラグ: 「nesting = +1 PR-merge gate per layer」）。未解決の loom#150 はこの二重 vendoring の症状。

### 5.5 Cloudflare デプロイは薄く非対称、SharedArrayBuffer ギャップが両者の低遅延をブロック

両者とも COOP/COEP ヘッダを設定せず SharedArrayBuffer+Atomics を使えない。MoonDsp ではメインスレッド↔AudioWorklet パラメータ更新が postMessage のみ（非決定的遅延、live-coding で可聴）。Canopy では本番に durable persistence なし。**COOP/COEP を Cloudflare 層で有効化することは共有解錠** — MoonDsp に lock-free オーディオ制御、Canopy に OPFS/SQLite-WASM 永続化の前提となる cross-origin isolation を与える。1つのインフラ変更が両プロダクトにレバレッジを持つ。

### 5.6 CLAP/native と CRDT 共有

- **CLAP**（MoonDsp Phase 8）: 最も明快な外部統合機会だが MoonBit C/LLVM バックエンド成熟にハードブロック。lock-free 制御チャネルも必要。Canopy には native パスなし → 見立ての「出力ターゲット」軸を弱く反証。
- **event-graph-walker（CRDT 共有）**: 見立てが**最も強く、最も well-grounded** な点。Canopy の egw（FugueMax テキスト CRDT + movable-tree CRDT + container CRDT）は production load-bearing。MoonDsp Phase 9 が「FugueMax/eg-walker CRDT」を明示的に命名し、前提条件の identity 層（`identity/`、ADR-0009）を既に構築済。両者が独立に「structure-first canonical document, text as projection」へ収束。egw を**指定された共有協調基層**として publish し、persistence/op-log-compaction ギャップを一度閉じれば MoonDsp Phase 9 が再発明せず消費できる。

### 5.7 外部依存の更新ポリシー（明文化）

各依存を「保守クラス × 同期戦略」で固定し、将来のリスク判断を機械的にする。各クラスは §6.4 の shared-substrate ADR で版管理する。

| 依存 | 種別 | 保守クラス | 同期戦略 | upstream 追従の SLA / トリガ |
|------|------|-----------|----------|------------------------------|
| `incr` | shared substrate（両者消費） | **version-pinned, coordinated** | §7.3 のバージョンロック + CI クロスチェック。canopy/moondsp 同一マイナーを強制 | upstream マイナー公開時に shared-substrate ADR を立て、両 consumer を同時 bump。互換ハンドル削除は ADR で削除日を予告 |
| `loom` + `seam` | shared substrate（Canopy production / MoonDsp 評価） | **registry-pinned**（公開後） | 4g 完了まで Canopy は path-dep、MoonDsp は spike 隔離 | wasm-gc ビルド証明（ADR-0012）が通り次第 registry 公開し両者を pin |
| `rabbita`（vendored fork） | 周辺（Canopy のみ、JS） | **contain-or-upstream** | editor-adapter seam 背後に封じ込め。`patch/diff-subs-update-tagger` ブランチ pin | パッチを upstream に PR するか、恒久 fork を宣言。release tag が出たら pin を tag へ昇格 |
| ProseMirror / CodeMirror(6) | 周辺（両者、TS、成熟 upstream） | **track-stable, boundary-hardened** | semver minor は随時追従。リスクは upstream でなく MoonBit↔TS↔PM seam | patch protocol 硬化（`Map[String,Json]` 拡幅、座標系曖昧性解消）を共有投資として優先 |
| Graphviz / `svg-dsl` | first-party / 周辺 | **abstracted, low-risk** | `lib/visualizer` の `VisualGraph` 抽象背後。差し替え可能 | レイアウト品質要件が上がった時のみ再評価。保守トリガなし |
| vendored canopy adapter（MoonDsp 側） | snapshot コピー | **snapshot-disciplined** | 単一 SHA から vendoring し SHA を記録（現状 `types.ts` 9df029d / `cm6-adapter.ts` 6f1d5c2 とドリフト） | コピー時に元 SHA を明記。ドリフトを CI でフラグ |

ポリシー原則: **shared-substrate（incr/loom）は coordinated bump、周辺は contain-behind-seam**。後者は seam があるため遅延追従が許容され、前者はバージョン整合が共有 Runtime の前提（§5.2）。

---

## 6. 設計・実装ドキュメント整備 (axis: doc-methodology)

### 6.1 状態評価

- **MoonDsp**: `docs/decisions/` に13の連番 ADR（0001-0013）+ README が成熟した一貫実践を成文化（1判断1ファイル、`NNNN-kebab.md`、Status ∈ {Proposed, Accepted, Superseded by ADR-NNNN, Rejected}、Source リンク、superseded 時のみ更新）。これが de-facto テンプレート。`scripts/check-public-boundary.sh` で不変条件を CI 強制。
- **Canopy**: 形式的 ADR は1つ（`docs/decisions/2026-03-29-framework-genericity-contract.md`、日付プレフィックス）。判断記録は `docs/research/*.md` と `docs/design/` に分散。連番・索引・status 追跡された decision ledger の等価物がない。

> **訂正済**（verifier 指摘、folded in）:
> - Canopy `docs/research/` の6ファイルのうち「Decision Record」形は3つのみ（patch-protocol, runtime-safety, workspace-identity）。残り3つは research/prototype investigation・design draft・call-flow grounding draft の別アーティファクト型。
> - Fact/Interpretation/Speculation ラベルは `2026-05-22-spec-aware-workspace.md` 固有（43出現）。patch-protocol probe には出現しない。
> - **incr と loom は既に decisions/ ledger を運用している**（loom: 19の日付プレフィックス決定ファイル、incr: 8-10）。「shared-substrate 決定に住処がない」は誤り。真の問題は (a) ledger が日付プレフィックスで連番でないため consumer の ADR `Related` フィールドからの相互参照が不便、(b) incr↔loom↔canopy↔moondsp 依存連鎖を跨ぐ決定の所有規約がない。

### 6.2 統一テンプレート（コピー&ペースト可能なアーティファクト）

MoonDsp の ADR システムをベースに、Canopy の research probe が必要だと証明した2セクション（Alternatives Considered + Evaluation Axes）を加える。

```markdown
# ADR-NNNN: <kebab-case-title>

- **Status**: Proposed | Accepted | Superseded by ADR-NNNN | Rejected | Deferred
- **Date**: YYYY-MM-DD
- **Source**: <originating plan/spec/PR/research-probe link>
- **Related**: ADR-NNNN, <repo>#NNNN, <other-repo ADR-NNNN for shared-substrate>
- **Binds**: <which repo(s) this decision binds — this-repo | canopy+moondsp | incr-substrate>

## コンテキスト
<決定を今迫る状況。status quo の帰結を番号付きで列挙する。>
1. ...
2. ...
<cross-repo 決定の場合、どのリポジトリを束縛するか明記する。>

## 決定
<決定内容をタイトに記す。シグネチャ/API 移行は表で示す。>

| 旧 | 新 | 理由 |
|----|----|------|
|    |    |      |

## 検討した代替案
<各オプションと、それが守る/破る設計原則を1つずつ明記する
（global CLAUDE.md の「2 options + principle each」報告形式に対応）。>

- **案 A**: <内容> — 守る原則: §N <名前> / 破る原則: §M <名前>
- **案 B**: <内容> — 守る原則: §N <名前> / 破る原則: §M <名前>

## 評価軸
<決定が判定された基準。Status: Proposed の場合これは forcing-functions /
promotion-gates を兼ねる。証拠が不完全な箇所には Fact / Interpretation /
Speculation ラベルを付す。>

- [軸1] <基準> — 現状: <Fact|Interpretation|Speculation> <内容>
- [軸2] ...
- (Proposed のみ) Forcing functions: <昇格を正当化する条件のチェックリスト>

## 影響・結果
- **Positive**: ...
- **Negative**: ...
- **Deferred (unblock condition)**: <延期項目と、それを解錠する条件>
  ※ 延期は TODO ではなく拡張点予約（design-principle §7）として記す。

## ステータス & 強制
- 現 status: <...>
- supersession ポインタ: <あれば ADR-NNNN>
- 不変条件を保つガード: <CI/test スクリプト名、例 scripts/check-public-boundary.sh>
```

### 6.3 ワークド例（既存決定を統一形式でレンダ）

```markdown
# ADR-0010: compiled-template-runtime-boundary

- **Status**: Accepted
- **Date**: 2026-05-xx
- **Source**: docs/salat-engine-blueprint.md §5 Phase 2 / PR #xx
- **Related**: ADR-0003 (topology artifact), ADR-0009 (stable identity)
- **Binds**: moondsp (将来 incr-substrate ADR から参照される候補)

## コンテキスト
1. Array[DspNode] が authoring 交換型、CompiledDsp が runtime 実行型として
   混在し、最適化パスがどこで何回走るか不明瞭だった。
2. optimize_graph が複数箇所から呼ばれうると、no-allocation 不変条件の
   検証点が散らばる。

## 決定
Array[DspNode] を authoring 交換型、CompiledTemplate を runtime 交換型と定める。
唯一の境界横断 CompiledTemplate::analyze が optimize_graph を厳密に1回走らせる。
public 関数は runtime 目的で bare Array[DspNode] を決して受け取らない。

| 旧 | 新 | 理由 |
|----|----|------|
| public fn(Array[DspNode]) | public fn(CompiledTemplate) | 境界の一意化 |

## 検討した代替案
- **案 A: 境界型を導入せず Array[DspNode] を直接渡す** — 守る原則: なし（最小変更）/
  破る原則: §3 責務マップ（最適化責務が呼び出し点に漏れる）, §6 排他性
- **案 B (採用): CompiledTemplate 境界型** — 守る原則: §7 拡張点予約
  (incr Memo cell 入力に適する純関数形), §3 責務マップ / 破る原則: なし

## 評価軸
- [incr 適合性] CompiledTemplate::analyze は純関数（DspContext 不要）—
  Fact: incr Memo cell 入力に適する。
- [early-cutoff] CompiledTemplate に Eq があれば再 analyze 時に early-cutoff —
  Speculation: NaN ポリシー未決のため未検証。

## 影響・結果
- **Positive**: 検証が安価で mono/stereo 非依存。最適化が1回保証。
- **Negative**: compile が Self? を返し Result でない（呼び出し側が
  feedback-cycle 拒否と missing-Output 拒否を区別できない）。
- **Deferred (unblock condition)**:
  - CompiledTemplate/DspNode への Eq — unblock: NaN 等価ポリシーの決定
    （構造的 NaN==NaN vs IEEE）。Phase 6+ early-cutoff の前提。
  - compile の Self? → Result[Self, GraphCompileError] 移行。

## ステータス & 強制
- 現 status: Accepted
- supersession: なし
- ガード: scripts/check-public-boundary.sh（.mbti を監査し境界不変条件を強制）
```

### 6.4 クロスリポジトリ番号付けと所有

- 1リポジトリのみを束縛する決定は当該リポジトリの `docs/decisions/` に repo-local 番号で。
- **shared-substrate を束縛する決定**（incr バージョン調整、互換ハンドル削除タイムライン、loom 昇格、Single-Runtime 結合）は substrate リポジトリ（loom/incr）の ledger に記し、両 consumer の `Related` フィールドから ADR 番号で参照。incr/loom の日付プレフィックスを連番に揃えるか、または「shared-substrate ADR」という命名規約を導入して相互参照を実用化する。

---

## 7. ロードマップとリスク評価 (axis: roadmap-risk)

### 7.1 多年ロードマップ（依存順 4 バンド）

各項目に **[内部作業]** / **[外部ゲート]** を付し、開始可能かどうかを明示する。

#### BAND 1 — 基盤（最初に行う。他すべてを解錠する）

| 項目 | 内容 | ゲート | 相対工数 |
|------|------|--------|---------|
| 1a. incr バージョン収束 | codemod（`canopy/loom/incr/scripts/migrate-to-target-facades.py`）で canopy root を 0.5.2→0.6.0 へ整列。cognition/main 内部スキューも解消 | **[内部作業]** | 中 |
| 1b. クロスリポジトリ調整機構の設計・standup | §7.3 参照。Single-Runtime 制約と互換ハンドル削除に両者が依存 | **[内部作業]** | 小〜中 |
| 1c. submodule ネスト平坦化 + 依存衛生 | event-graph-walker 二重 vendoring 解消、loom#150 クローズ。**パーサ採用とは独立した依存衛生作業**として行う（loom の mooncakes publish と MoonDsp 採用は §1.4「パーサラスト」に従い 4g へ分離。Codex review 反映） | **[内部作業]** | 中 |

#### BAND 2 — インクリメンタル・スケーリング（並列可能、別々の壁）

| 項目 | 内容 | ゲート | 相対工数 |
|------|------|--------|---------|
| 2a. MoonDsp: Eq + NaN ポリシー定義 | `DspNode`/`CompiledTemplate` に Eq。既存 `Revision` early-cutoff を活性化 | **[内部作業]**（NaN 設計判断が前提） | 中 |
| 2b. Canopy: O(N) 変更検出 + O(m×n) LCS reconciliation の置換 | 1000 defs で約8.5ms を下げる | **[内部作業]**（microbenchmark でボトルネック再現が前提） | 大 |

> これらは **revision-stamp パターンのみを共有し、修正は共有しない**。1つのマイルストーンに混同しないこと。

#### BAND 3 — 真の共有 north-star

| 項目 | 内容 | ゲート | 相対工数 |
|------|------|--------|---------|
| 3a. MoonDsp パターン operations の defunctionalize | `PatternDoc` の不透明クロージャ（`FilterMap`/`Every`/`Jux`、moondsp `pattern/pattern_doc.mbt`）を enum variant 化。これなしに MoonDsp operations は diff/merge/wasm 越え不可。**CRDT/op-log 共有・pattern-as-Canopy 統合（4f）すべての前提**（§3.6）。Codex review でロードマップ欠落として追加 | **[内部作業]** | 大 |
| 3b. identity-based 構造照合（標語は同じ、機構は別の2ワークストリーム） | **(i) MoonDsp**: runtime ノード状態移行を `GraphNodeId` で（authoring-position ベースを置換）。**(ii) Canopy**: 永続/修飾された semantic identity（現状の per-document same-kind LCS NodeId 再利用を超える）。両者を「同時解決」と束ねず別ワークストリームとして追跡。structure-first CRDT 協調の前提で、Canopy の出荷済 egw movable-tree CRDT が共有候補基層（Codex review 反映） | **[内部作業]**（BAND 1/2 で解錠） | 大 |

#### BAND 4 — 延期（外部ゲート）

| 項目 | 内容 | ゲート |
|------|------|--------|
| 4a. Durable persistence | OPFS/IndexedDB + op-log compaction（client-side） | **[内部作業]** だが 4d に依存 |
| 4b. native/CLAP バックエンド | MoonDsp Phase 8 | **[外部ゲート: MoonBit C/LLVM 成熟]** |
| 4c. 低遅延トランスポート | SharedArrayBuffer / COOP-COEP | **[外部ゲート: Cloudflare config]** |
| 4d. COOP/COEP 有効化 | 両プロダクトの共有解錠（4a と 4c の前提） | **[外部ゲート: Cloudflare config]** |
| 4e. rabbita フォーク upstream | 封じ込め済低重要度負債 | **[内部作業、opportunistic]** |
| 4f. MoonDsp graph DSL as Canopy 言語 | canopy#419/#422-424。見立ての決定的検証者 | **[内部ゲート: Canopy semantic-contract 安定 + BAND 3 (3a defunctionalize + 3b identity)]** |
| 4g. loom mooncakes publish + MoonDsp 採用 | loom+seam を registry 公開し MoonDsp の production mini-notation パーサへ昇格（ADR-0012/0013 ゲート）。§1.4「パーサラスト」に従い BAND 1 から分離（Codex review 反映） | **[外部ゲート: mooncakes publish + wasm-gc ビルド証明]** |

### 7.2 統合リスクレジスタ

| リスク | 出所（repo/file） | 影響 | クラス | 担当バンド | 軽減策 |
|--------|-------------------|------|--------|-----------|--------|
| incr バージョンスキュー（0.5.2 vs 0.6.0 + cognition 内部スキュー） | canopy `moon.mod.json:24`, `lib/cognition/moon.mod`, moondsp `moon.mod` | 高 | maintenance/correctness | 1a/1b | codemod 整列 + 調整機構 |
| 互換ハンドル削除タイムラインなし | incr CHANGELOG | 高 | maintenance | 1b | 削除前に target-facade へ移行 + バージョンロック |
| recovery バッファ32上限が収束を恒久破壊 | `editor/recovery.mbt:5,51-54` | 高 | correctness | durable rollout 前 | 上限引き上げ or バックプレッシャ |
| 32ビット seq/LV オーバーフロー（ガードなし、両リポジトリ） | `internal/causal_graph/graph.mbt:13` | 中 | correctness | durable rollout 前 | Int64 へ移行 |
| MoonDsp Int64 rational オーバーフロー（fast/slow チェーン） | `rational.mbt:90` | 中 | correctness | BAND 2 | オーバーフローガード |
| op-log/tombstone 無制限成長（compaction なし） | `internal/fugue/item.mbt:85`, `internal/oplog/oplog.mbt`; incr `InternTable` grow-only | 高 | perf/maintenance | 4a | snapshot/compaction（client-side） |
| 単一スレッド WASM ABI use-after-free | moondsp `browser/browser.mbt:24-26` | 中 | correctness | 4c/4d | atomics/同期、または契約強制 |
| no-BFT / no-auth による状態破損 | `editor/sync_protocol.mbt:64` | 中（共有文書で高） | security | §7.4 | 認証層 + op 整合性検証 |
| loom wasm-gc AudioWorklet ビルド未証明 | moondsp ADR-0012 | 中 | build | 1c | CI ゲート化（§7.5） |
| rabbita un-upstream フォーク | `rabbita` submodule（patch ブランチ pin） | 低 | maintenance | 4e | upstream or 恒久保守決定 |
| single-pending snapshot の silent drop | moondsp `scheduler/scheduler.mbt:527-533` | 低 | correctness | BAND 2/3 | versioned queue |
| position-based 状態 discard（トポロジ編集の kind 変更） | moondsp `graph/graph_topology_controller.mbt:366-394` | 中 | correctness | 3b(i) | identity-based 照合 |
| TextBlock sparse-array メモリ増幅 | `container/text_block.mbt:3-6` | 低 | perf | 4a | dense-ItemId refactor |
| vendoring SHA ドリフト（types.ts 9df029d vs cm6-adapter.ts 6f1d5c2） | moondsp `web/live/src/canopy/` | 低 | maintenance | 5.1 | スナップショット規律 |

> **訂正済の正の事実**（過大主張を繰り返さないため）: relay op-log は `MAX_OPS=10_000` + `evictOldOps` で**有界**（`examples/ideal/web/server/ws-server.ts`）。ローカル SQLite store は存在する。真のギャップは client-side CRDT compaction。

### 7.3 クロスリポジトリ調整機構（具体設計）

「機構を追加する」をプレースホルダにせず、BAND 1 の設計済デリバラブルとする。3案から推奨:

- **推奨: 共有 incr バージョンロックファイル + CI クロスチェック**。canopy と moondsp の `moon.mod(.json)` から incr pin を抽出し、両者が同一マイナーであることを CI で検証する軽量チェックを両リポジトリに置く。理由: 2リポジトリ moon.work ワークスペースは submodule ネストと publish 制約で重く、公開 incr 互換性マトリクスは過剰。バージョンロック + CI チェックが最小コストで incr-skew と互換ハンドル削除タイムラインの両依存を解く。
- 補完: incr/loom の substrate ledger に「incr バージョン調整」「互換ハンドル削除タイムライン」の shared-substrate ADR を立て、両 consumer の `Related` から参照（§6.4）。

### 7.4 セキュリティ・信頼モデル（横断的関心事）

数年規模の協調ビジョンでは一級リスク。Canopy の protocol は `// flags: no BFT`（`editor/sync_protocol.mbt:64`）、flags バイト恒久 `0x00`、認証なし、relay はメンバシップ dedup のみ検証 → 任意の接続クライアントが状態を破損できる。durable persistence ピボット（4a）は脅威モデルを変える（永続ストアが攻撃面になる）。central-server-authority profile（§3.5）導入時に: authn/authz、op 整合性検証、relay/DO 信頼境界を設計すること。現状はどれも未着手。

### 7.5 テスト・検証・CI 戦略（横断的関心事）

既存カバレッジ: PBT laws（`Canonical` trait）、Printable roundtrip PBT アンカー、ベンチマークスイート、moondsp `scripts/check-public-boundary.sh`。

ロードマップが含意する共有 CI ゲート:
1. **wasm-gc ビルド証明ゲート** — 両プロダクトで昇格される共有ライブラリにハード CI 義務化（loom-in-MoonDsp の繰り返し命名されるブロッカー。JS(Canopy)/wasm-gc(MoonDsp) ターゲット分岐を跨ぐ前提）。
2. **incr バージョンロックチェック**（§7.3）。
3. **境界チェック**（`check-public-boundary.sh` を Canopy 側へも展開検討）。
4. canopy の submodule fan-out（`.github/workflows/ci.yml` が正典）と moondsp CI の調整。ネストサブモジュール = +1 PR-merge gate/layer に注意。

### 7.6 パフォーマンス・スケーリングクリフ表

| ホットパス | 出所 | コスト | 噛む入力規模 | 計測/推定 | 修正バンド |
|-----------|------|--------|-------------|-----------|-----------|
| Canopy O(N) 変更検出スキャン（`physical_equal` on CstNode） | `docs/performance/2026-04-06-pipeline-decomposition.md:65,89-94` | ~8.5ms@1000 defs（~60% of per-keystroke） | 1000 defs（16ms バジェット迫る） | 計測済 | 2b |
| Canopy O(m×n) LCS reconciliation | `core/reconcile.mbt:39-48` | 二次 | 深い木の大きな兄弟リスト | 推定 | 2b |
| Container sparse-array メモリ増幅 | `container/text_block.mbt:3-6` | 線形 | block create 間の global op 多数 | 推定 | 4a |
| tree undo-do-redo O(k)/remote op | `internal/movable_tree/conflict.mbt:292-307` | 末尾 undo+redo | 高スループット並行 move | 推定 | — |
| MoonDsp `Song::query` per-block アロケート | `song/song.mbt:617` | block ごと GC 圧 | 高 voice/section 数（wasm-gc） | 推定 | 4a |
| MoonDsp voice スティーリング O(max_voices) | `voice/voice.mbt:464-494` | 線形走査 | max_voices スケール | 推定 | — |
| MoonDsp `active_notes` 線形走査 | `scheduler/scheduler.mbt:690` | O(active)/block（swap-remove は O(1)） | 長セッション/密パターン | 推定 | — |
| loom `SyntaxNode::children()` O(n) アロケート | loom `ROADMAP.md:182` | フレッシュ Array/呼び出し | lambda callers projection | 推定 | — |

> プロジェクト規約「最適化前に microbenchmark でボトルネック再現」に従い、計測済（Canopy 変更検出のみ）と推定を区別した。BAND 2/3 着手前に各 cliff を isolation で再現すること。

### 7.7 見立ての反証可能な検証（thesis validation）

MoonDsp-graph-DSL-as-Canopy-language（canopy#419/#422-424）は唯一の未検証統合ケースであり、見立ての決定的検証者。共有構造の仮説が立てる**具体的に誤りうる予測**:

> MoonDsp の `DspNode` AST が `TreeNode`+`Renderable`（必要なら `Canonical`）を実装すれば、LCS NodeId reconciliation と 3-memo インクリメンタル projection を **`core/` への新フレームワークコードなしで**獲得するはずである。そして**最初に破れる場所はフレームワーク境界ではなく、2リポジトリ跨ぎ7箇所の手動 variant 同期（§4.3）**であるはずだ。

この予測が成り立てば見立ては本物。フレームワーク境界が先に破れたら、見立ては retrospective rationalization である。これは記述を予測へ転換し、期待される失敗点を命名する。

### 7.8 コミュニティ・コントリビューション戦略（横断的関心事）

数年規模のエコシステムは外部ユーザ/コントリビュータのフィードバック機構なしには維持できない。現状（検証済 2026-06-01）: 両リポジトリとも `.github/ISSUE_TEMPLATE/` を持たず RFC プロセスもない。Canopy は `PULL_REQUEST_TEMPLATE.md` + `dependabot.yml` を持つが、MoonDsp は `workflows/` のみ。最小の枠組みを提案する:

- **意思決定の入口を ADR に一本化**: 設計提案は §6.2 テンプレートの「Proposed」ADR として受け、議論はその ADR 上で。これにより外部提案も内部判断と同じ台帳に乗る。
- **issue テンプレート**: (1) bug（再現手順 + ターゲット target）、(2) design proposal（→ Proposed ADR へ昇格）、(3) shared-substrate change（incr/loom に触れるものは §6.4 の所有規約に従い substrate 側 ADR を要求）。
- **本レポートを基礎資料に**: 新規 issue/設計文書は本ビジョンレポートの該当 §を引用し、どの BAND・どの拡張点に属するかを明記する規約にする。これで提案がロードマップ上の位置を持つ。
- **live-coding ドメインの強み**: MoonDsp は Strudel/TidalCycles コミュニティと隣接する。共有可能な成果物（pattern スニペット、DSP パッチ）は早期の外部巻き込みに向く — ただし §3.6 の defunctionalize（3a）が済むまでパターンの可搬な共有形式は持てない点に注意。

> 注: 本節の提案は未実装。上記の `.github/` 現状は 2026-06-01 に確認済。

---

## 8. 付録: 両リポジトリ現状マップ

凡例: **[実装済]** / **[構想]** / **[部分実装]**

### 8.1 MoonDsp

| 領域 | 状態 | 要約 |
|------|------|------|
| DSP プリミティブ (`dsp/`) | **[実装済]** | Oscillator/Noise/Adsr/Biquad/DelayLine/Gain/Mix/Clip/Pan/ParamSmoother。process() で zero-allocation |
| Finally Tagless 代数 (`dsp/tagless.mbt`) | **[実装済]** | 6 `pub(open)` trait。GraphBuilder が全実装 |
| Compiled graph runtime (`graph/`) | **[実装済]** | hot-swap、トポロジ編集、constant-folding、z⁻¹ feedback |
| `DspNode`/`CompiledTemplate` Eq | **[構想]** | NaN ポリシー未決（ADR-0010）。Phase 6 early-cutoff のブロッカー |
| Hot-swap 状態移行 | **[構想]** | `graph_hotswap.mbt:25,34` 移行しない。トポロジ編集は position-based 照合 |
| `GraphTemplateDoc`/`GraphIndexMap` | **[実装済]** | `graph/graph_identity.mbt`。ただし `CompiledDspTopologyController` へ未配線 |
| VoicePool (`voice/`) | **[実装済]** | 32スロット、generation-tagged、3層スティーリング |
| Pattern エンジン (`pattern/`) | **[実装済]** | `Pat[A]` 遅延クロージャ。変換は不透明クロージャ（シリアライズ不可） |
| mini-notation パーサ (`mini/`) | **[実装済]** | 420行超手書き再帰下降。`MiniAuthoringPipeline` は incr-backed |
| Song 層 (`song/`) | **[実装済]** | Section/Occurrence/Song。`TimeScope` は rate のみ |
| マルチトラック transport | **[構想]** | 共有トランスポートなし。重大ギャップ |
| オフライン/非リアルタイムレンダ | **[構想]** | エントリポイントなし（block アーキで近接無償） |
| identity 層 (`identity/`) | **[実装済]** | 5 検証済 ID newtype + `Revision`。dependency-free |
| `Revision` の incr 配線 | **[構想]** | combine/max あるが early-cutoff へ未配線 |
| ブラウザ ABI (`browser/`) | **[実装済]** | 71関数 flat WASM。単一スレッド、use-after-free 文書化リスク。char-by-char UTF-16 マーシャリング |
| ControlMap タイピング | **[部分実装]** | stringly-typed（ADR-0007）。KEY 検証/value-domain/expression 延期 |
| loom mini-CST | **[構想]** | `specs/loom-mini-cst/` スパイクのみ。ADR-0012/0013 Proposed |
| CLAP/native | **[構想]** | Phase 8。MoonBit C/LLVM 成熟にブロック |
| 構造エディタ / CRDT 協調 | **[構想]** | Phase 9。FugueMax/eg-walker 命名。設計ドラフトのみ |
| Cloudflare デプロイ | **[実装済]** | 静的アセットのみ。COOP/COEP なし |

### 8.2 Canopy

| 領域 | 状態 | 要約 |
|------|------|------|
| Text CRDT (`event-graph-walker`) | **[実装済]** | FugueMax + OpLog + CausalGraph。durable な主表現 |
| Tree CRDT (movable-tree) | **[実装済]** | Kleppmann undo-do-redo、cycle-Skip、LWW |
| Container CRDT | **[実装済]** | MovableTree + per-block FugueTree。sparse 配列 |
| op-log ポータビリティ | **[実装済]** | `SyncMessage` JSON。delta sync via `export_since`/`VersionVector` |
| Sync protocol | **[実装済]** | binary frame, version `0x02`, 7 variant。no BFT |
| Relay (Cloudflare Worker+DO) | **[実装済]** | ステートレス message router。DO はドキュメント状態保持せず |
| Ephemeral 層 | **[実装済]** | LWW（CRDT でない）。`EphemeralNamespace` は閉じた `pub(all)` enum |
| Durable persistence | **[部分実装]** | Ideal localStorage 全スナップショット（lambda のみ）+ ローカル SQLite relay store。client-side compaction なし |
| `ProjNode[T]` + 3言語統合 | **[実装済]** | Lambda/JSON/Markdown。`ProjNode[T]` 完全汎用 |
| Printable family | **[部分実装]** | `loom/pretty/traits.mbt` 実装。Lambda/JSON 実装、**Markdown 未実装** |
| `TermSym` tagless | **[実装済]** | `pub(open)`、Lambda 専用。新 variant は 7-location 手動同期 |
| `ViewMode` dispatch | **[構想]** | architecture doc のみ。production にゼロヒット |
| `render_html`/`ansi`/`latex` | **[構想]** | `layout_to_view_tree` のみ実装 |
| `SyntaxCategory` | **[実装済]** だが閉じている | 拡張に library 編集要 |
| `StructuralEdit` params 拡幅 | **[構想]** | `Map[String,String]`→`Map[String,Json]` 受諾済・未出荷 |
| Reconciliation (LCS) | **[実装済]** | same_kind 上 O(m×n)。安定 NodeId |
| 3-memo インクリメンタルパイプライン | **[実装済]** | `@incr.Derived`。変更検出が支配的コスト |
| `loomgen` codegen | **[構想]** | 7-location 手動同期を消す。未構築 |
| MoonBit↔Rust interop | **[構想]** | 皆無・未計画 |
| MoonBit↔TS/JS FFI | **[実装済]** | 3言語別 JS バンドル、stringly-JSON、cross-bundle 共有は Phase 2 延期 |
| Rabbita (TEA) | **[実装済]** | un-upstream フォーク（patch ブランチ pin）、JS-only |
| Graphviz/SVG-DSL/visualizer | **[実装済]** | first-party、`VisualGraph` 抽象済 |
| cognition lib | **[実装済]** | インクリメンタル AI context graph。provider boundary（mock）。incr 0.6.0 使用 |
| llm (Gemini) | **[実装済]** | JS-only、async FFI |
| 構造エディタ / AST-as-source promotion | **[構想]** | text-first が ground truth。positional 同一性脆弱性 |
| MoonDsp graph DSL as Canopy 言語 | **[構想]** | canopy#419/#422-424。#419 で blocked |

### 8.3 共有基層

| 領域 | 状態 | 要約 |
|------|------|------|
| `dowdiness/incr` | **[実装済]** だがスキュー | canopy 0.5.2 / moondsp・cognition 0.6.0。pull/push/Datalog 3モード。互換ハンドル削除日なし |
| loom パーサフレームワーク | **[実装済]** (Canopy) / **[構想]** (MoonDsp) | `LanguageSpec[T,K]`。Canopy production、MoonDsp スパイク隔離 |
| seam (CST primitives) | **[実装済]** | `CstNode`/`SyntaxNode` 2木モデル + projection helper |
| projection identity 層 | **[実装済]** | `ProjectionIdentityTracker` 等。loom Unreleased |
| クロスリポジトリ調整機構 | **[構想]** | バージョンロック/ワークスペースなし。BAND 1 のデリバラブル |
| submodule ネスト | **[実装済]** だが負債 | event-graph-walker 二重 vendoring。loom#150 未解決 |
| incr 形式検証 / Expr API / parallel | **[構想]** | docs/todo.md・roadmap Phase 5 |

---

## 9. 付録: 依存関係図と用語集

### 9.1 サブシステム依存関係図

オーサリング → 同一性安定 lowering → ランタイム成果物（§1.2）の同一形と、共有基層（incr / loom）への依存を図示する。実線 = 実装済の依存、破線 = 構想（未配線）の依存・統合。

```mermaid
flowchart TB
  subgraph SUB["共有基層 (shared substrate)"]
    incr["incr 反応基盤<br/>(canopy 0.5.2 / moondsp 0.6.0 ※skew)"]
    loom["loom + seam パーサ/CST"]
  end

  subgraph CN["Canopy (code / AST)"]
    egw["event-graph-walker<br/>Text/Tree/Container CRDT"]
    core["core: ProjNode[T] / SourceMap / NodeId"]
    proj["projection + lang/{lambda,json,markdown}"]
    edt["editor: SyncEditor / sync_protocol(0x02)"]
    egw --> edt
    core --> proj
    edt --> core
  end

  subgraph MD["MoonDsp (audio / pattern)"]
    pat["pattern: Pat[A] / PatternDoc<br/>(変換は不透明クロージャ)"]
    mini["mini: text → Pat[ControlMap]"]
    sched["scheduler: PatternScheduler"]
    graph["graph: CompiledTemplate / hot-swap"]
    voice["voice: VoicePool (priority stealing)"]
    ident["identity: GraphNodeId / Revision"]
    mini --> pat
    pat -->|ControlMap| sched
    sched --> voice
    graph --> voice
    ident -.->|未配線| graph
  end

  incr --> core
  incr --> proj
  incr --> mini
  loom --> proj
  loom -. "ADR-0012/0013 評価中(4g)" .-> mini

  egw -. "Phase 9: CRDT 共有" .-> pat
  core -. "4f: graph DSL as Canopy 言語" .-> graph
  pat -. "3a: defunctionalize 前提" .-> egw
```

> 図の読み方: MoonDsp と Canopy は別々の実装だが、`incr`（実線で両者へ）が唯一の現役共有依存。`loom` の MoonDsp 側（破線）と、egw CRDT 共有・graph-DSL 取り込み（破線）はすべて構想。`identity → graph` の破線が §2.3 の「未配線」を表す。

### 9.2 用語集（略語・キー概念）

| 用語 | 所属 | 意味 |
|------|------|------|
| **operations-as-data** | 設計原則 | 操作を関数呼び出しでなく値（enum/record）として表現。undo/log/協調マージを可能にする（design-principle §5） |
| **incr** | 共有基層 | `dowdiness/incr` 反応的インクリメンタル計算ライブラリ。Input/Derived/ReachableDerived、Watch/Observer、MemoMap、Datalog |
| **early-cutoff** | incr | 入力が等価なら下流の再計算をスキップする最適化。Eq に依存する |
| **loom / seam** | 共有基層 | loom = インクリメンタルパーサフレームワーク（`LanguageSpec[T,K]`）。seam = その CST プリミティブ（`CstNode`/`SyntaxNode`） |
| **ProjNode[T]** | Canopy/core | 言語非依存の投影ノード。新言語は `TreeNode`+`Renderable` を実装して接続 |
| **SourceMap / NodeId** | Canopy/core | トークンスパンと安定ノード同一性。LCS reconciliation が NodeId を再利用 |
| **eg-walker / FugueMax** | Canopy/egw | イベントグラフ走査 CRDT（arXiv:2409.14252）と非干渉テキストマージ（arXiv:2305.00583） |
| **ViewMode / Printable** | Canopy | Printable = Show+Debug+Source+Pretty（実装済）。ViewMode dispatch 層は **[構想]** |
| **Pat[A]** | MoonDsp/pattern | 時間アークに対する遅延クエリ `(TimeSpan) -> Array[Event[A]]`。Strudel 由来 |
| **ControlMap** | MoonDsp | `Map[String, Double]`。pattern と DSP graph を繋ぐ「唯一の値契約」「意図的に狭い橋」 |
| **CompiledTemplate** | MoonDsp/graph | DSP グラフの runtime 交換型。`analyze` が唯一の境界横断（ADR-0010） |
| **DspNode** | MoonDsp/graph | グラフ authoring の交換型（`Array[DspNode]`）。Eq 未実装（§2.4） |
| **GraphNodeId / Revision** | MoonDsp/identity | 安定 ID と改訂トークン。authoring wrapper で消費、topology controller へ未配線 |
| **voice stealing** | MoonDsp/voice | ポリフォニー上限時のスロット再利用（idle > oldest releasing > oldest active） |
| **defunctionalize** | 設計手法 | クロージャを enum variant に変換。MoonDsp パターン操作の CRDT 共有前提（3a / §3.6） |
| **hot-swap** | MoonDsp/graph | グラフの等電力クロスフェード差し替え。現状ノード内部状態を移行しない（§2.3） |
| **CLAP** | 外部 | CLever Audio Plugin 規格。native プラグイン化（Phase 8、MoonBit C/LLVM 待ち） |
| **ADR** | ドキュメント | Architecture Decision Record。MoonDsp は 0001–0013 連番運用、Canopy は §6 で導入提案 |
| **BAND 1–4** | 本レポート | §7.1 ロードマップの段階（基盤 / スケーリング / 共有 north-star / 延期） |
