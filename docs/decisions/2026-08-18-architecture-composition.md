# Architecture composition — pipeline, collaboration, and document authority

**Date:** 2026-08-18

**Status:** Accepted. This record nests three already-accepted architectures.
It does not replace them.

**Related:**

- [Library API boundary](2026-06-11-library-api-boundary.md)
- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
- [Causal Authority residency](2026-08-12-causal-authority-residency.md)
- [Markdown file-backed authority and external admission](2026-08-09-markdown-file-backed-authority-and-external-admission.md)
- [EGW staged publication responsibility boundary](2026-08-09-egw-staged-publication-responsibility-boundary.md)
- [Loomark concurrent projection execution](2026-08-12-loomark-concurrent-projection-execution.md)
- [Generic language SPI deepening](2026-08-07-generic-language-spi-deepening.md)
- [Composition map](../architecture/ARCHITECTURE_DIAGRAM.md)

**Reader:** Maintainers writing or reviewing ADRs, plans, or package moves that
cross the editor library, collaboration, or document lifetime.

**Decision:** Treat Canopy as three nested architectures with one composition
rule. The session pipeline owns an editing session. The collaboration split
owns how replicas exchange causal work. Document authority owns identity and
access over time. A new ADR must name which of the three it extends, which
layer inside that architecture, and whether the change is shipped behavior or
target architecture. Do not introduce a fourth stack.

**Keep until:** Permanently. Supersede this record if a later ADR proves that
session, collaboration, and document lifetime cannot remain distinct reasons
to change.

## Context

The 2026-06 library redesign extracted wire, session policy, language SPI, and
host registry packages. Those stages landed. Three later decisions then each
answered a different change pressure:

- collaboration layers A–E, with peer-sync shipped and a payload-opaque runtime
  still target;
- document authorities (causal residency, file association, staged
  publication);
- projection execution off the authority commit path.

None of those records stated how they nest. Product code filled the gap with
local ownership: an archive envelope in one app, plain browser storage in
another, and a dual typed-plus-FFI write path in a third. New ADRs kept adding
target architecture on an uncomposed stack.

The June layer diagram also placed language SPI above editor orchestration.
The 2026-08-07 SPI decision made construction editor-owned so source identity,
identity hints, and watch coherence stay in one place. That later decision
stands.

## Decision details

### Nesting

Product shells depend on document lifetime and on host bindings. Document
lifetime depends on the session pipeline and on collaboration. Collaboration
depends on the sync wire and on the EGW peer-sync companion. It does not
depend on editor orchestration. Language construction may depend on editor
orchestration.

Document lifetime is product-owned. Incubate it in the Markdown product until
a second app needs the same envelope. Do not fold durable identity into
editor orchestration.

### Declared exception

Language SPI may depend on editor orchestration. That is the 2026-08-07
construction-ownership rule, not a layering defect.

### Shipped versus target

The composition map states which layers are current code and which remain
accepted target. Implementation plans execute against that distinction. An
accepted target ADR is not a license to start work that the map sequences
behind an earlier stage.

## Consequences

- `docs/architecture/ARCHITECTURE_DIAGRAM.md` is the composition map.
- The 2026-06-11 redesign proposal is historical. Remaining library leftovers
  (editor I/O surface, dual write path, language-family cost) follow the
  composition map rather than that proposal's unchecked boxes.
- Import lint may keep `lang/*/runtime` → editor as an allowed edge.
- JSX streaming stays outside the session pipeline until a second
  session-shaped consumer needs the same contract.
- File-backed admission, staged publication, and the payload-opaque
  collaboration runtime stay sequenced behind admission/projection split and
  behind removal of editor-owned transport.

## Rejected alternatives

### Invent a new layer cake

Rejected because the three architectures already exist as accepted records.
The failure is missing composition, not missing layers.

### Invert language SPI away from editor orchestration

Rejected because construction coherence is the reason the SPI depends on the
editor. One construction host is not a second adapter.

### Put document lifetime on the editor orchestration façade

Rejected because session orchestration and durable identity change for
different reasons. A text snapshot is not an editing base until causal
admission.

### Keep the June proposal as the current target

Rejected because S0–S5 largely landed and the live pressure is product-scale
ownership, not another pipeline split.

## Non-goals

- Implementing leftover library extraction or Loomark projection movement in
  this documentation change.
- Changing EGW core, wire version, or the peer-sync companion.
- Choosing Ideal's surviving write path (typed versus FFI).
- Forcing generative-UI streaming onto the session pipeline.
