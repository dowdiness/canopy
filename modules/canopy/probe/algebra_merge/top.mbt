///|
/// Probe package: does Canopy's text CRDT preserve *intent* when two
/// semantically independent operations touch the same text region?
///
/// Scenario reproduces Fig. 3 of "Beyond Text Editing: Algebraic Manipulation
/// of Source Code" (Pulo, ICSME 2026) in Canopy's lambda language: one replica
/// renames a parameter (a change that cascades to every use site), the other
/// reorders the parameter list. Text patches conflict; the paper claims the
/// operations commute when represented algebraically.
///
/// The probe has no runtime surface — see `algebra_merge_wbtest.mbt`.
pub const PROBE_SUBJECT : String = "text-crdt intent preservation"
