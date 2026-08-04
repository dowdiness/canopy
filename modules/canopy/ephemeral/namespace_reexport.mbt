///| Frame-namespace API re-export.
///
/// The ephemeral frame namespace (wire-level byte mapping) moved to
/// `dowdiness/canopy/protocol/wire` in redesign S1. Ephemeral re-exports it
/// so `@ephemeral.EphemeralNamespace` and the namespace helpers remain
/// stable for consumers, and so this package's own code keeps the names in
/// local scope.

///|
pub using @wire {
  type EphemeralNamespace,
  namespace_to_byte,
  namespace_from_byte,
  all_namespaces,
}
