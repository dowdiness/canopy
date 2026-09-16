# Loomark 複数端末編集 — 次セッションへの一時引き継ぎ

作成日: 2026-09-16

**一時的な会話引き継ぎ。実装済み報告・採用済みADR・正式な実装計画・backlogではない。** 次セッションで必要事項を正式なIssue/計画/契約へ移した後、このファイルは削除してよい。

## 次の目標

「スマホで文書を書く → 同期先への保存を確認 → スマホを閉じる → 初めて使うPCで同じアカウントにログイン → 同じ文書を開いて続きを書く」という、実際に動く経路を作る。

ユーザーは実現方法・性能・実装可能性を繰り返し確認した。最後の依頼は別セッションで継続するための一時文書の保存。このセッションでは同期機能の実装には着手していない。

## ユーザーが明示した方向

- スマホと複数端末で楽に使えることが必須。PCでしか使えないアプリは望んでいない。
- Amp Orbsのように、特定のPCや実行環境の管理を意識せず同じ作業へ戻れる体験を目指す。
- 十分速く、使っていてストレスがないことを重視する。
- ローカルフォルダやMarkdown sidecarの管理を通常利用の前提にする方向へ戻さない。
- 保存形式の比較を続けるより、上記の具体的な端末切り替え経路を実現することが次の焦点。

以下の技術構成・性能数値は助手の提案であり、ユーザーが個々の技術選択まで承認したものではない。

## Checkoutと作業状態

- Repository: `/home/antisatori/ghq/github.com/dowdiness/canopy`
- 引き継ぎ時のbranch: `main`
- HEAD: `fb6700bd54bfaaba0b45a1f60210e3ed32f67165`
- 引き継ぎ作成直前の `git status --short`: 下記research noteがuntracked。ほかの変更表示なし。
- [調査ノート](../docs/research/2026-09-16-local-first-markdown-workspace-strategies.md)をこの会話で作成した。未コミット。
- 同期・認証・cloud persistenceのコード変更、deploy、性能測定、スマホ実機検証は行っていない。
- 次セッション開始時にcheckoutと差分を確認する。他者の変更があれば保持する。

## Orbsから分かったこと

一次資料:

- https://ampcode.com/what-are-orbs
- https://ampcode.com/docs/orbs
- https://ampcode.com/notes/orbs-explained
- https://ampcode.com/docs/macos-and-ios

公式資料では、threadに対応するremote machineでagentが動き、PCを閉じても実行が続く。Web/CLI/iOSから同じthreadへ戻れ、休眠後も会話・ファイル・サービスを保持して復帰すると説明されている。モバイルには通知とthread linkからの復帰導線がある。

重要なのはVMではなく、作業のidentity・状態・寿命が表示端末から独立していること。Amp内部のDB、通信プロトコル、VM休眠方式、CRDT採用、offline編集保証は公開資料から確認していない。Loomarkに文書ごとのVMやagent機能を追加する要求ではない。

## 確認済みの現在の実装（変更前に再確認）

- [Loomark README](../apps/loomark/README.md): Rabbitaのbrowser Markdown editor。Text/Preview/Split、native textarea、IndexedDBのSource保存がある。
- [製品契約](../apps/loomark/CONTEXT.md): Document identity、Recent documents、Import/Export、IME、Document switch、削除などの現行語彙と契約。
- [Source codec](../apps/loomark/app/internal/source_repository/source_codec.mbt): `source/v1/<id>` は厳密に `document_id` と `text` の2項目。現在のdurable authorityは本文で、CRDT履歴を保存していない。
- [Source repository](../apps/loomark/app/internal/source_repository/): 現在の保存・open・deleteの所有箇所。起動時はstore全体から文書一覧を導出する。
- [Textarea](../apps/loomark/internal/text_area/text_area.mbt): native入力をTextChangeへ変換する既存の接続箇所。
- [Editor](../modules/canopy/editor/README.md): EGWを使うCRDT、Undo、parser、同期などがある。ただし、この統合EditorをそのままLoomarkへ入れるとText modeのlazy parser契約に影響し得る。必要な既存APIを調べて使う。
- [sync_session](../modules/canopy/sync_session/README.md): transport非依存の同期/recovery。`SyncHost`のapply/exportと`SyncTransport`がある。現在の説明には1 MB SyncResponse上限などがある。永続保存の受領確認や大きな文書の復元を提供すると決めつけない。
- [relay module](../modules/canopy/relay/README.md): 接続中peer間の転送で、CRDT本文を解釈しない。
- [relay server](../apps/relay-server/src/index.ts): Cloudflare Worker + Durable Object。roomとpeerを指定してWebSocket接続し、MoonBit relayへ転送する。現在のコードに認証・文書権限チェック・storageへの文書保存はない。
- [deployment config](../apps/relay-server/wrangler.toml): 既存Cloudflare設定がある。Durable Objectという名前だけで文書が永続化されていると誤認しない。

## 提案していた実装方向

各端末で即時編集とローカル保存を行い、マネージド同期先が端末の非同時接続を埋める。既存Cloudflare基盤とEGW/sync_sessionを再利用する方向を第一候補にするが、再利用可能なAPIと保存プロトコルは実装前に確認する。

1. ローカルに文書identityと復元可能なCRDT履歴を保存する。書き込みinstanceごとにwriter identityを分離する。
2. 同期先に文書を永続保存し、全端末切断・サーバー再起動後も新端末から復元できるようにする。
3. 認証と文書単位の認可を設け、文書一覧を新端末で取得できるようにする。文書URLはアクセス権そのものではない。
4. 入力はネットワーク待ちにしない。local durableとremote durableを分け、remote保存完了後に受領確認する。
5. 切断・再送・受領確認消失で変更を失ったり二重適用したりしない。接続状態や送信完了をdurabilityの証拠にしない。
6. 元端末がなくても復元できることを先に証明する。単なる接続中peerへのbroadcastでは不十分。

通常利用でユーザーにGit、同期フォルダ、sidecar、サーバー管理を要求しない。Markdown exportは所有・外部連携の出口でありcausal syncではない。取得済み文書はoffline編集できる方向を提案した。新端末で未取得の文書をofflineで開けるとは約束しない。

## 実装前に扱う契約とリスク

- [Human-centered principles](../docs/architecture/human-centered-product-principles.md)のLocal ownershipには中央サーバー不要のP2P同期がある。マネージド同期を通常経路にする提案との関係を明示的に整理する。クラウド必須へ無断で変更したり、P2P必須を口実にユーザー要件を後回しにしたりしない。
- [Ownership design](../docs/design/local-first-document-ownership.md)は要求と歴史的実装記述が混在する。末尾の「Loomarkが履歴保存済み」という記述を現行コードの証拠に使わない。現行Source codecはtext-only。
- [File-backed ADR](../docs/decisions/2026-08-09-markdown-file-backed-authority-and-external-admission.md)の外部ファイルadmissionと、通常の端末間CRDT同期を混同しない。
- native textareaへremote textを単純代入するとIME・selection・Undoを壊す可能性がある。composition中の変更とremote更新を安全に統合し、Undoで他端末の変更を巻き戻さない契約が必要。
- 既存text-only文書から過去の履歴は復元できない。移行時点を履歴の開始点にする。失敗時の本文保全と、旧保存方式を廃止する条件を設計する。
- 削除した文書を古いoffline端末が再送して復活させない。削除記録とoffline編集との競合方針は未決定で、現行削除契約の変更になる。
- 文書作成と一覧登録が部分成功して文書が見つからなくなる状態を避ける。
- 同期はbackupではない。データ持ち出し、誤削除からの復旧、認証復旧は別契約。完全E2EEや鍵復旧方式は未決定。
- cloud/authのcredential、利用可能なdeploy環境、スマホ実機へのアクセスは未調査。まずrepo設定と利用可能な環境を調べ、読める情報をユーザーへ聞かない。秘密値を出力しない。有料resource作成や公開deployは権限・課金範囲を確認する。

## 最初の完成条件

- スマホで文書を作り、同期先への永続保存を確認する。
- スマホ側のアプリを終了する。
- 同期サーバーを再起動しても文書が残る。
- ローカルデータのないPCブラウザで同じアカウントにログインする。
- 文書一覧から同じ文書を開き、続きを書ける。
- スマホを開き直すとPCの追記が届く。
- 別アカウントからは文書を取得できない。

続く受け入れ条件はoffline同時編集、再接続・重複配送、IME/selection/Undo、複数文書と削除、既存文書移行。最初の経路を証明してもこれらまで完了したとは言わない。二つのtabが通信できるデモをスマホ実機検証の代わりにしない。

## 性能について

構成上、入力にネットワーク往復は不要。しかし統合後の性能は未測定。快適さを保証していない。

助手が提示した暫定目標（未承認・未測定）:

- 通常入力から表示: p95 50 ms以内。
- ローカル文書切り替え: p95 200 ms以内。
- 最近の文書への温かい起動/復帰: p95 1秒以内。
- 良好な通信下の他端末反映: p95 1秒以内。
- 保存・同期で繰り返す50 ms超のmain-thread占有を起こさない。

実装前に対象端末・本文量・履歴量・文書数と測定定義を決める。これらの値を達成済みの数値や確定SLAとして使わない。TextとPreview/Split、履歴が育った文書、offline変更の大量受信、日本語入力、保存と入力が重なる場面を実際のJS/browser targetで測る。

Worker化、履歴圧縮、分割保存、キャッシュを根拠なく先行実装しない。まず実経路で測定し、遅い処理だけ切り出してbenchmarkする。Text modeのlazy Preview/parserを維持する。

## 次セッションの最初の行動

1. [docs入口](../docs/README.md)、Loomarkの現行契約、上記コードを必要な範囲で確認し、作業checkoutと差分を把握する。
2. 既存のCRDT復元/編集API、同期protocol、storage、deploy/auth設定を調べ、一文書の永続同期を実装する最小の変更範囲を確定する。
3. [Task Tracking](../docs/development/task-tracking.md)に従って既存Issueを検索する。正式な実装へ移るときにIssueと一つの実装計画へ整理し、本メモを別backlogにしない。
4. 上記完成条件を満たす実装へ進む。抽象的な「作れそう」という説明や競合製品の再調査だけを繰り返さない。

実装時の関連skill: MoonBitには `moonbit-agent-guide`、Rabbita変更には `rabbita`、性能には `moonbit-perf-investigation`、外部SDK/APIの現行仕様には `context7-mcp`、browser実機能の確認には `agent-browser`。公開symbol変更は利用可能なLSPで参照を確認する。

既存のproduction E2Eコマンドは `./scripts/test-loomark-standalone-e2e.sh`。同期経路の新しい検証をこれだけで証明したことにはしない。認証済みの独立browser context、サーバー再起動、元端末切断を含めて検証する。

## 混同・再開しないこと

- 調査ノートの「archive + associated File Authorityが最有力」「次はarchive形式probe」という結論は、スマホ優先のユーザー修正より前。今回の次工程を決める権威にしない。
- 本メモのクラウド構成はAmp内部実装についての主張ではない。
- Orbs参照をagent、VM、remote terminal、通知機能の追加要求へ拡張しない。
- 既存のCanopy CRDT機能を、Loomarkに統合・永続化・実機確認済みと扱わない。
- 新しいCRDTライブラリへの置換、複数provider、Git連携、filesystem連携、native app開発を初回経路の前提にしない。

## このセッションの検証範囲と教訓

research noteにはdocumentation lifecycle checkと相対リンク検証を行った。同期コードのテスト、公開deploy、二端末実験、性能benchmarkは未実施。

方向性の説明は整理できたが、当初の提案はdesktop保存方式に偏り、ユーザーによる修正が必要だった。次はユーザーの具体的な端末切り替えを基準に進める。技術的に正しい保存形式だけで製品体験が成立したとみなさない。

## 次セッションへの貼り付け文

`tmp/loomark-multidevice-handoff.md`を読んで続きを進めてください。スマホで書いて同期先への保存を確認した後、スマホを閉じても、初めて使うPCから同じ文書を開いて編集できる経路を実装したいです。現在のコード・契約・利用可能なdeploy環境を確認し、必要な決定を明示して最小の縦断実装へ進んでください。調査ノートのdesktop/file-backed優先案には戻さず、実装済みでない同期や未測定の性能を保証しないでください。
