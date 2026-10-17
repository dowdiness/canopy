# Historical A6 validation, 2026-10-02

Follow-up source changes are NOT yet runtime validated. See FOLLOWUP-REVIEW.md;
the results below describe the earlier validated snapshot saved to Library.

Working branch: `experiment/a6-loomark-egw-worker` in `dowdiness/canopy`.
Base/current main verified: `122735058b798009a915ea7513ecb4f511dbede4`.
Actual experimental EGW: `07a6a833ed9442eee26d463375f589864539b864`, manifest 0.8.0.
Normal repository submodule pointers were not changed.

This is an isolated real Loomark app-entry/Text editor slice, with Rabbita
TextChange and post-render element effects. It is not a production document
schema migration or ordinary Catalog/Preview integration. Synthetic data only.

> Historical pre-fix export evidence only. These results do not validate the
> current handoff commit or later A6 edits. See [CODEX_HANDOFF.md](CODEX_HANDOFF.md).

## Historical validation

- Pure conversion/protocol tests: 11 passed.
- Real Chrome two-tab scenarios: 12 passed, both headless and headed.
- Fault/recovery scenarios: 10 passed, both headless and headed.
- Actual Rabbita scope unmount/remount: 3 passed, both modes.
- Normal mode isolation: passed; no experimental global or IndexedDB namespace.
- MoonBit affected Loomark app/internal/server packages: 388 tests passed.
- Affected app check with `--deny-warn`, release builds and `git diff --check`: passed.
- The original report said review findings were fixed and re-reviewed. Later
  review identified unresolved issues; see CODEX_HANDOFF.md. This is not a clean
  final review result.

JSON results, screenshots and compressed Chrome traces remain in the original
export archive; they are intentionally omitted from this source-only handoff.
Latest browser/fault/lifecycle JSON contains headed results; both modes were run.
The preliminary mixed-rAF performance file is retained for audit only: phase
overlap contaminated its remote sample counts. Use the final headed/headless files.

## Performance

Installed Chrome 154.0.8037.93, Node 24.11.1, MoonBit 0.10.14+7d59c7ec9.
Each condition has 5 warm reopens, 20 local inputs, 10 remote applications and
30 commits. Headed medians in milliseconds:

| Text/history | Navigation to Ready | Local input proxy | Remote apply proxy | Commit |
|---|---:|---:|---:|---:|
| 10k/basic | 333.0 | 28.35 | 27.35 | 1.0 |
| 10k/+10k history | 1000.5 | 27.10 | 45.10 | 0.9 |
| 100k/basic | 2169.7 | 20.80 | 33.75 | 1.1 |
| 100k/+10k history | 2853.3 | 22.85 | 42.30 | 1.1 |

History adds 5k inserts and 5k deletes while retaining the original text length.
Both final modes observed no Long Task API events >=50ms during measured phases.
Independent CDP traces cover navigation, bundle execution, Worker communication,
text application and settling. Three 100k basic and three churn reopens per mode:
headed renderer-main RunTask maximum **9.557ms**, headless maximum **14.015ms**;
no >50ms task in these samples. Worker threads are excluded from those maxima.

Double rAF is a presentation-opportunity proxy, not pixel paint. Remote timing
starts at the receiver's pull, not the source user's keystroke. Initial shared
seed creation is outside warm-reopen measurements. These are local samples,
not a universal frame-time guarantee.

The previous single-replica main-thread compact-restore probe measured about
1.17s median restore and 1.19s main-thread long task. This implementation restores
two Worker replicas: headed 100k basic Worker restore median 1.99s, then Ready at
2.17s. The result removes measured main-thread blocking, not startup latency;
different boundaries and replica counts prevent a direct speedup ratio.

## Remaining EGW contracts and limitations

- Stable cursor/selection anchors are missing; repeated-character provenance
  remains ambiguous under bounded text alignment.
- Restore remains expensive and synchronous within the Worker. Incremental or
  cancellable restoration, and a supported editor-basis fork/projection contract,
  could reduce startup cost and the need for two replica states.
- Undo state is not archived. Restart clears local Undo. An unacknowledged Undo
  crash remains explicitly unresolved/read-only/Not saved; Retry visibly cancels
  that action and restores the accepted basis. It is not recovered Undo intent.
- Concurrent-delete Undo may revive another tab's deletion; overlap may produce
  redgreen/greenred. Existing semantics were retained and documented.
- Compact archive max100k is unchanged. The 120k catch-up test uses a 4-op seed
  plus six whole valid 20k schema2 packets, not a 120k compact archive. A single
  oversized packet is rejected without slicing or silent history removal.
- Pending packets and local Undo stacks remain outside compact archives.
- Actual OS Japanese IME is unverified: supported node_repl/@oai/sky controls are
  unavailable in this session. Synthetic composition and headed Chrome pass, but
  do not establish actual OS IME behavior.
- Abrupt process loss before IndexedDB commit cannot preserve volatile intent.

## Publication handoff

No commit, push, PR, merge, deploy, permission change or credential setup occurred.
Scope: two small app entry/import edits, a new internal local_tabs binding and
the isolated experimental directory. No production storage migration.

Repository publication gates remain blocked: `just` and `lefthook` are absent;
`gh auth status` cannot read the existing GitHub CLI config (Access is denied).
No bypass was attempted. Full workspace CI was not run; the 388-test result is
the affected Loomark module, not whole-repository CI. Parent should run normal
hooks in an equipped environment, check duplicate PRs and coordinate publication.

## Japanese summary

実際の Loomark Text エディターを使い、2タブの自動マージ・保存・再読込を
隔離環境で確認しました。100k 文書の復元は Worker に移し、実ブラウザーの
測定ではメインスレッドの50ms超タスクはありませんでした。一方で起動待ち、
安定カーソル、Undo の再起動復元、実OS日本語IMEには上記の制約が残ります。
本番ノート・アカウント・クラウド同期には触れていません。
