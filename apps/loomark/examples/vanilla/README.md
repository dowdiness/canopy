# Loomark browser tests

This directory contains the Node and Playwright dependencies shared by two
separate browser boundaries.

- `dev-host.spec.ts` exercises the disposable private development driver. It
  owns one fresh connected mount per BrowserContext and observes detached
  snapshots, typed event effects, and Rabbita timing.
- `standalone.spec.ts` exercises only the Warren production output through its
  visible Raw editor, Block editor, and Preview controls. It imports no private
  driver module.

Neither boundary is a public Browser App/Session contract.

## Behavioral and lifetime test inventory

| Boundary | Harness assertion | Lifetime claim |
| --- | --- | --- |
| Fresh connected host | one application mounts once into one connected container | mount ownership starts only after the fresh host is validated |
| Second mount | a second mount attempt is rejected by the private driver | no host reuse or remount |
| Page/process termination | the isolated page/context closes to end the run | termination is the only lifetime end; runtime cleanup is unclaimed |
| Source/mode/event/error/focus | typed source, mode, editor, error, and focus operations remain independent of host lifetime | application behavior is testable without teardown |
| Immediate reads / after-render writes | snapshots read committed state immediately; focus, selection, and measurement write/read after the corresponding render command | no synchronous read-after-write assumption |
| Selection / measurement | supported capabilities succeed; unsupported or failed capabilities report typed boundary errors | DOM capability semantics belong to `dom-boundary` |
| Listener load / tagger refresh / unload | one retained-key test listener is installed, its source-dependent tagger refreshes through `RunningSub.update_tagger`, unload removes it exactly once, and repeated cleanup stops delivery | control transport remains available while the test listener is stopped |
| Fatal driver state | fatal application errors reject later private driver operations with an operation/reason snapshot | the control listener remains reachable so rejection is observable; no teardown claim is made |
| Forbidden paths | no clear, reuse, remount, transfer, or cleanup approximation appears in a case | a new page/process is used for every isolated case |

The one mount-ownership site in the private adapter is the migration point that
#1072 will replace with Rabbita `MountedApp::unmount`. That migration must add
disposal, repeated-unmount, fatal-cleanup, reentrancy, remount, and host-reuse
tests before deleting this adapter and harness.

## Driver seam

The generated JavaScript for `internal/dev_host` is private test infrastructure.
Its exports accept `String`/`Int` arguments and return `Unit` or serialized
status/snapshot `String`s. Each request is encoded in MoonBit, dispatched
through typed `dom-boundary` custom-event APIs (the DOM `CustomEvent.detail` is
a `String`), and decoded into a typed `DriverEvent`; there is no live enqueue
closure or global handle registry. Raw DOM/Rabbita values, `MarkdownApp`,
`MarkdownSession`, and `unmount` are deliberately absent.
