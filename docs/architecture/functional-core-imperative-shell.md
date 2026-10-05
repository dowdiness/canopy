# Functional Core / Imperative Shell

Canopy separates deterministic domain decisions from effects. This document is
the repository's source of truth for that boundary.

Domain transformations, validation, lowering, and state-transition decisions
belong in the functional core. Pass inputs explicitly and return values, next
state, commands, or structured diagnostics. Core decisions must not depend on
the filesystem, network, clock, random sources, DOM, provider clients, or
mutable session state.

The imperative shell owns I/O, scheduling, cancellation, replay cursors,
lifecycle mutation, provider adapters, DOM/session adapters, and persistence.
It translates effects into core inputs and executes the returned decisions.
Keep this wiring thin so domain behavior can be tested without those effects.

Prefer state transitions that compute the next state and decision from the
current state and an event. A mutable facade is acceptable when it remains a
shell around deterministic transition logic.

Validated core results must not expose internal mutable collections. Use
immutable views or defensive copies according to the ownership boundary.
Local builder mutation is permitted in a pure function only when it has no
observable external effect and is justified by the operation being built.

Test the functional core with deterministic unit and property tests. Focus
shell tests on effect wiring, integration boundaries, and a small number of
end-to-end cases.

The [Functional Core / Imperative Shell reference collection](https://github.com/kbilsted/Functional-core-imperative-shell)
describes this separation of dependencies and mutation from decision paths.

## DOM actions and calculations

DOM reads are actions, not just DOM writes: `querySelector`, element lookup,
selection reads, and layout measurements depend on when they run. Passing an
element explicitly removes hidden lookup dependencies; it does not make live
DOM access pure. This follows the actions/calculations/data distinction in
[Eric Normand's “What is an action?”](https://ericnormand.me/podcast/what-is-an-action).

- Resolve application-specific IDs and selectors at composition, mount, or
  after-render boundaries. Reusable DOM helpers receive the actual elements
  and browser handles they operate on, rather than locating them internally.
- Read the required values in the shell, pass those values to pure calculations,
  and apply the returned decisions in the shell. Core calculations accept
  measured data, not live elements or callbacks that read them.
- Bind observations to the node's lifetime. If rendering replaces a node,
  disconnect the old observation and resolve the replacement after rendering.
  Keep cancellation and pending-work guards in the shell.
- Prefer existing typed MoonBit browser bindings. Keep JS FFI limited to missing
  native operations and interop conversion; return typed handles or measured
  values rather than leaking dynamic JavaScript objects into the core.
  Keep application decisions, scheduling, retained state, and resource lifetime
  in the MoonBit shell. Extract numeric decisions into the core, including the
  next value of an accumulated baseline; do not hide mutation in a policy method.

For example, caret visibility is a calculation over the measured line bounds,
scroll position, viewport height, and padding. Measuring a textarea and writing
its new scroll position remain separate actions.
