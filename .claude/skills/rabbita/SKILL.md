---
name: rabbita
description: "Rabbita binding and idiom reference. Use BEFORE designing, implementing, or reviewing any code that uses @sub, @cmd, @html, @dom, @http, or that authors or modifies a rabbita binding (e.g. lib/rabbita_codemirror). Requires reading the local rabbita repository's authoritative docs before answering. Triggers on 'rabbita', '@sub', '@cmd', '@html', '@dom', '@http', 'custom_sub', 'custom_cmd', 'suberror', 'Emit', 'Sub binding', 'TEA', 'rabbita_codemirror', 'rabbita_xterm'."
---

# Rabbita skill (canopy-local)

Rabbita is canopy's vendored TEA-style UI framework at `./rabbita/`
(submodule, fork of `moonbit-community/rabbita`). The local docs and the
shipping bindings under `rabbita/rabbita/*` are the **authoritative**
source of truth for idioms — not training data, not the rabbita_xterm
spec, not any prior plan in this repo.

## BEFORE you answer or implement — read these in order

Treat this list as a checklist. If you're asked a rabbita-related
question or asked to implement rabbita-touching code, you read these
*first*, then answer. The first three are the framework basics; the
sub/binding files are for any work that wires native JS state into the
TEA loop.

| # | Path | Why |
|---|---|---|
| 1 | `rabbita/skills/rabbita.md` | Upstream's own skill: basic conventions + HTTP anti-patterns. Inlined below for reference, but read the file if it has been updated. |
| 2 | `rabbita/doc/001_intro/readme.mbt.md` | TEA shape: Model / Msg / update / view / Cmd. |
| 3 | `rabbita/doc/002_writing_html/readme.mbt.md` | HTML wrappers, labeled args, `Attrs::build()` as workaround, keyed children, `nothing`. |
| 4 | `rabbita/doc/004_using_command/readme.mbt.md` | `Cmd`, `none`, `batch`, `perform`, `attempt`, `delay`, `effect`. `simple_cell` vs `cell`. |
| 5 | `rabbita/doc/005_http/readme.mbt.md` | HTTP idioms (in addition to the inlined anti-patterns below). |
| 6 | `rabbita/doc/using_subscriptions/readme.mbt.md` | `Sub`, `subscriptions(emit, model)`, `@sub.batch`, `@sub.none`, builtin Subs. |
| 7 | `rabbita/doc/suberror_as_extensible_enum/readme.mbt.md` | `suberror` as extensible enum — the payload pattern for `custom_sub`. |
| 8 | `rabbita/rabbita/sub/design.md` | Why `Sub`s diff via a `Ref[Callback]` and `update_tagger` — the mechanism that requires our `diff_subs` patch. |
| 9 | `rabbita/rabbita/sub/README.mbt.md` | Public Sub API summary. |
| 10 | `rabbita/rabbita/html/design.md` + `rabbita/rabbita/html/README.mbt.md` | HTML EDSL rationale. |
| 11 | `rabbita/rabbita/websocket/listen.mbt` | **Canonical Sub-binding pattern.** Function-based public API + `priv suberror` payload + `let mut tagger` + `update_tagger` rebind. Mirror this pattern when authoring any new `@sub.custom_sub`-using binding. |
| 12 | `rabbita/rabbita/websocket/websocket.mbt` | **Canonical Cmd-binding pattern.** `pub fn op(id, ...) -> Cmd` + internal `Map[String, Entry]` registry. Mirror this when authoring any new binding's lifecycle / mutation ops. |
| 13 | `rabbita/examples/shiki_editor/main/client.mbt` | Editor-binding analog: async load via `with_init`, `Highlighter.code_to_html(...)`, sub-free editor (since shiki is highlight-only). |
| 14 | `rabbita/examples/subscriptions/main/client.mbt` | Multi-sub composition with `@sub.batch`. |
| 15 | `rabbita/examples/websocket/main/client.mbt` | End-to-end consumer of a function-based binding. |

After this reading: cite the specific file paths you used when
justifying any design decision. If the rabbita docs disagree with
older canopy plans (`docs/plans/*.md`) or with the original spec passed
in by the user, **the rabbita docs win** — the plans should be revised,
not the other way around. Canopy's `docs/plans/2026-05-18-codemirror-rabbita-binding-phase1-audit.md` and `…phase2.md` already encode this rule
explicitly.

## Authoritative inline rules (from `rabbita/skills/rabbita.md`)

These rules apply to **consumer-facing code** (canopy app code, examples).
**Bindings themselves** (`lib/rabbita_codemirror/`, future libraries) are
the escape-hatch shell — they legitimately use the listed escape hatches
internally. The rules below describe what consumer code must not do.

### Basic requirements

- **Prefer the library's high-level API over manual JS FFI.** Avoid the
  escape hatches `@cmd.custom_cmd`, `@sub.custom_sub`, `@cmd.effect`,
  `@cmd.attempt`, `@html.Attrs`, `@dom`, `trait Scheduler` in *consumer*
  code. Use them only inside a binding's implementation.
- **Eliminate unnecessary state management.** Routes: use `@html.a`,
  `@sub.on_url_changed`, `@sub.on_url_request` — do not encode a URL
  state machine in `update`.
- **Prefer immutable data structures** (immut `Map`, `Array`, `Set`) over
  mutable ones, except array literals in `view`.
- **Do not store callback / message / Cmd in Model.** Model holds only
  values. Bindings expose `fn(id, ...) -> Cmd`; consumer Models hold
  just the `String` id.
- **Message-sending lambdas stay short.** `x => send(UserMsg1(x))`,
  `send(UserMsg2)`. No business logic inside a callback.

### HTTP anti-patterns (avoid in consumer code)

- Mutable state in Model mutated in place.
- Embedding logic in the message-sending callback (compute in `update`).
- Ignoring the returned `Request`/`RequestWithBody`/`Cmd`.
- Storing the `Request` or `Cmd` in a global / Model / data structure.
- Wrapping HTTP construction in a helper function — chain inline
  through `update` instead.

(Examples for each are in `rabbita/skills/rabbita.md`; read that file
when actually writing HTTP code.)

## Binding-authoring patterns (canonical)

When authoring a binding (e.g. `lib/rabbita_codemirror/`), follow the
patterns in `rabbita/rabbita/websocket/`:

### Two-package shape

```
lib/<name>/js/          extern "js" only, opaque newtypes, Disposable
lib/<name>/             public fn-returning-Cmd API + priv registry +
                        priv suberror payloads + priv sub loader
lib/<name>/addon/X/     optional typed payload wrappers per extension
                        family (e.g. Theme, Keymap); imports js/ only
```

### Function-based public API

```
pub fn op(id : String, args..., failed? : Emit[String]) -> Cmd
pub fn listen(id : String, callback~ : Emit[T]?, ...) -> Sub
```

The consumer's Model holds only the string id. All JS handles live in
the binding's internal mutable `Map[String, Entry]`. The skill rule
*"do not store Cmd/Msg/callback in Model"* is what makes this shape
mandatory for consumer code.

### Suberror payload pattern

```moonbit
priv suberror MySubscription {
  Listen(
    id : String,
    on_x~ : Emit[X]?,
    on_y~ : Emit[Y]?,
  )
}

fn my_sub_loader(payload : Error, scheduler : &Scheduler) -> RunningSub? {
  match payload {
    Listen(id~, on_x~, on_y~) => {
      let mut on_x_tagger = on_x       // mutable captured by listeners
      let mut on_y_tagger = on_y       // and re-bound by update_tagger
      // install JS-side listeners that read on_x_tagger / on_y_tagger
      Some({
        unload: _ => { /* tear down listeners */ },
        update_tagger: payload => {
          guard payload is Listen(_, on_x~, on_y~) else { return }
          on_x_tagger = on_x
          on_y_tagger = on_y
        }
      })
    }
    _ => None
  }
}

pub fn listen(id : String, on_x? : Emit[X], on_y? : Emit[Y]) -> Sub {
  guard on_x is Some(_) || on_y is Some(_) else { @sub.none }
  let key = "my.listen(id=\{id},on_x=\{on_x is Some(_)},on_y=\{on_y is Some(_)})"
  @sub.custom_sub(key, Local, Listen(id~, on_x~, on_y~), my_sub_loader)
}
```

This pattern depends on Rabbita's `diff_subs` calling `update_tagger`
on the preserved sub. **Canopy's `rabbita/` submodule includes the
patch that makes this work** (`patch/diff-subs-update-tagger` branch).
Upstream Rabbita 0.12.2 does not. See
`docs/plans/2026-05-18-codemirror-rabbita-binding-phase2.md` §P2.0.

### Sub key conventions

The `@sub.custom_sub` key string encodes parameters whose change should
mean "re-install a fresh sub" rather than "rebind taggers". Tagger
*identities* must **not** appear in the key — only their presence (e.g.
`on_x=Bool`). Otherwise every re-render re-installs listeners and
`update_tagger` never runs.

## Codex delegations

Codex sessions do not see canopy's skills or memory. When dispatching
rabbita-related work via `mcp__codex__codex`, the orchestrator (Claude)
must include in the prompt:

1. A "Required reading" section with the relevant paths from the table
   above (typically 3–6 paths, scoped to the task).
2. The relevant inline rules from this skill that apply (e.g. consumer
   vs binding-author distinction).
3. The expected pattern shape (suberror, fn-based API, etc.).

The Phase 2 plan's delegation table at `docs/plans/2026-05-18-codemirror-rabbita-binding-phase2.md`
§"Delegation plan" describes the artifact contract Codex returns.

## When the skill auto-invokes

Trigger keywords in the user's prompt: `rabbita`, `@sub`, `@cmd`,
`@html`, `@dom`, `@http`, `custom_sub`, `custom_cmd`, `suberror`,
`Emit`, `Sub binding`, `TEA`, `rabbita_codemirror`, `rabbita_xterm`. If
*any* of these appear in a task description, invoke this skill *before*
answering — including before clarifying questions.

If the task is unrelated to rabbita despite a keyword match (e.g. user
mentions `Map` which contains `@`), the agent may exit the skill after
reading this section. Do not skip the skill *invocation*; the discipline
is "invoke first, decide relevance second."
