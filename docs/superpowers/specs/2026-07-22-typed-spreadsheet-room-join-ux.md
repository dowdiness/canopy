# Typed spreadsheet room and join UX

**Date:** 2026-07-22

**Status:** Proposed; awaiting confirmation of this synthesized brief

**Related:**
[EGW collaboration responsibility boundary](../../decisions/2026-07-21-egw-collaboration-responsibility-boundary.md) ·
[Typed spreadsheet EGW register and projection boundary](../../../loom/incr/docs/decisions/2026-07-20-typed-spreadsheet-egw-register-projection.md)

**Reader:** Designers and implementers building the first collaborative
room/join flow for the typed spreadsheet product pilot.

**Decision:** Add explicit share-link room creation and automatic join while
keeping the spreadsheet as the primary surface, collaboration status quiet in
the healthy path, and local drafts, selection, and focus outside synchronized
state.

**Keep until:** The room/join product slice is implemented and validated with
real users or is superseded by a later product brief.

**Disposition:** Keep as the product brief while active. After implementation,
retain the durable behavior in product guidance and archive or supersede this
spec.

## 1. Feature summary

This feature turns the typed spreadsheet from a single-user authority prototype
into a product pilot where two people can edit one committed sheet through a
shared URL. It targets people evaluating a real collaborative spreadsheet
workflow while preserving a path from developer evidence to a general-user
product.

The first release uses temporary rooms, link-based edit access, minimal peer
status, offline local edits, and automatic convergence after reconnect.

The pilot does not add accounts, roles, persistent rooms, remote cursors,
synchronized selection, or bearer-link revocation. Stop-sharing semantics must
be decided before room UX implementation.

## 2. Primary user action

A host starts sharing the current committed sheet and sends the generated link.
A collaborator opens that link, waits for the initial sync, and edits the same
sheet without learning CRDT or transport terminology.

The primary understanding is: **the sheet is shared, committed edits will
converge, and unfinished local work remains private.**

## 3. Design direction

Use Canopy's **Legible Instrument** direction: calm, precise, immediate, and
explicit about authority. The spreadsheet remains the artifact; collaboration
controls support it rather than becoming a competing dashboard.

Apply these principles:

- **Cognitive stability:** joining, reconnecting, and remote projection preserve
  cell selection, local focus, scroll position, and dirty drafts.
- **Legible state:** show whether the sheet is local, joining, connected,
  offline, or unable to sync without exposing protocol internals.
- **Action certainty:** “Share” creates an editable room; link copy explains
  that anyone with the link may edit.
- **Restraint:** healthy collaboration uses a compact status. Details appear
  only when the user needs to recover.
- **Human authority:** reset and document replacement never occur as an implicit
  side effect of room or transport events.

The existing spreadsheet's visual language remains primary. Collaboration uses
its established typography, spacing, focus treatment, and sparse semantic color.

## 4. Layout strategy

The 50×50 sheet remains the single primary region.

- Place one **Share** action with other workspace-level controls.
- Open an anchored sharing surface near that action. Avoid a modal because
  copying a link does not need to suspend spreadsheet work.
- Show a compact connection indicator near Share. In the healthy path it carries
  only connection state and peer count.
- Reveal recovery details from that indicator when offline, reconnecting, or in
  error.
- Keep formula bar, grid, trace, and evidence regions in their existing
  positions. Joining changes availability, not layout identity.
- On narrow screens, preserve Share, join status, recovery action, and the same
  reading order. Do not redesign the 50×50 editing surface in this slice.

## 5. Key states

### Local

The sheet is not shared. The user can edit normally and can choose **Share**.
Reset retains its existing single-user behavior.

### Creating room

The Share action shows immediate progress and cannot create duplicate rooms.
The current committed sources seed the room; drafts remain local.

### Ready to share

Show the editable link, **Copy link**, a copied confirmation, and the statement
"Anyone with this link can edit."

The URL contains a high-entropy bearer capability. The provider validates
possession before joining, and the room name cannot be enumerated.

The host may close the sharing surface without ending collaboration.

### Joining

Keep the existing sheet geometry visible but disable editing until bearer-link,
stable document identity, and authority-node validation complete. The authority
identity names the shared document and remains stable after its creator leaves.

Show **Joining…** with an accessible status announcement. Do not seed a second
local authority before attachment.

### Connected

Enable editing in place. Show a compact state such as **Connected · 2**. A room
with only the current peer remains connected and shareable.

### Offline with local changes

Continue accepting local committed edits and drafts. Show **Offline — changes
will sync when reconnected** without blocking the sheet.

### Reconnecting

Attempt transport reconnect and full sync while preserving local committed
operations and local-only UI state, then announce recovery once without moving
focus.

### Invalid, expired, or unavailable room

Use one primary message for an unauthorized, malformed, expired, or absent
bearer link so the response does not reveal whether a room exists. Offer a path
back to a local sheet; do not silently create a room under the old link.

### Invalid or incompatible document

Distinguish an invalid room identity, missing/dead authority node, incompatible
sync payload, and unrecoverable synchronization failure in diagnostics. The
primary message stays user-facing; technical detail belongs in disclosure or
trace output.

### Dirty draft during remote commit

Keep the user's draft text and editing focus. Update committed authority and
calculated results through the normal projection path without replacing the
unfinished draft.

### Collaborative reset

Disable Reset while attached to a room. Explain: **Reset is unavailable while
collaborating. Start a new sheet instead.** Document replacement remains future
work.

### Room expiry

The creator has no special lifetime role after seeding. A remaining peer can
bootstrap later joiners after the original host departs. The room expires only
after every peer disconnects and the reconnect grace period elapses.

An explicit **Leave collaboration** action is outside this slice. Closing or
navigating away disconnects the current peer. A later product decision must
define whether an intentional leave creates a detached local identity or keeps
a reconnectable room identity before adding that control.

## 6. Interaction model

1. The host activates **Share**.
2. The application creates a stable document identity and unguessable room
   capability, seeds committed sources, attaches the local replica, and presents
   the bearer link.
3. The host copies and sends the link.
4. The joiner opens it. The provider validates the bearer capability; the
   application validates stable document and authority-node identity. Any
   remaining peer can supply full sync before the joiner attaches without
   reseeding and enables editing.
5. Each local commit updates EGW authority first, projects through the existing
   adapter path, and sends an incremental sync message.
6. Each remote message enters the same adapter projection path.
7. During disconnection, local commits continue and are marked for later sync.
8. Reconnect performs full sync before returning to Connected.

Repeated keyboard editing does not animate spatially. Status changes use text,
shape, and restrained semantic color. Focus remains at the causal control or
active editor.

## 7. Content requirements

Required labels and messages:

- **Share**
- **Copy link**
- **Link copied**
- **Anyone with this link can edit.**
- **Joining…**
- **Connected · {peerCount}**
- **Offline — changes will sync when reconnected**
- **Reconnecting…**
- **This shared link is invalid, expired, or unavailable.**
- **This shared sheet is incompatible with this version.**
- **Reset is unavailable while collaborating. Start a new sheet instead.**

Connection status must be available through a polite live region. Errors and
recovery actions must remain keyboard reachable and must not rely on color
alone.

Dynamic ranges for the pilot:

- zero remote peers after room creation;
- typically one remote peer;
- a small number of peers rather than large-room presence;
- temporary disconnects from milliseconds to minutes; and
- arbitrary committed cell count within the existing 50×50 sheet.

## 8. Recommended references

Implementation should consult:

- `.impeccable.md` for Legible Instrument product and motion constraints;
- `interaction-design.md` for the anchored share surface, disabled editing, and
  recovery controls;
- `ux-writing.md` for connection, expiry, and incompatibility messages;
- `responsive-design.md` for preserving Share and recovery actions on narrow
  screens; and
- `color-and-contrast.md` for redundant status signaling.

## 9. Open questions

These choices do not block the peer-sync contract spike, but must be resolved
before room UX implementation:

1. How long is the reconnect grace period after the last peer disconnects?
2. Should a dirty draft whose committed cell changed remotely receive a quiet
   per-cell notice, or remain visible only through trace/evidence?
3. What room and peer-count limits should the pilot enforce?
4. Which rate limits and abuse controls must accompany bearer-link access before
   public deployment?
5. What detach or reconnect semantics would justify adding an explicit Leave
   action in a later slice?
6. Should **Stop sharing** revoke the bearer capability immediately, and what
   happens to connected peers and their unsynchronized local commits?
