/**
 * CrdtBridge type stub — full implementation in Task 5.
 *
 * This interface defines the contract that NodeViews use to communicate
 * text edits back to the CRDT layer. The bridge is null until Task 5
 * wires it up; all call sites guard with null checks.
 */
export interface CrdtBridge {
  /** Called by CM6 NodeViews when leaf text changes (int_literal, var_ref, unbound_ref) */
  handleLeafEdit(nodeId: number, changes: { from: number; to: number; insert: string }[]): void;

  /** Called by CM6 NodeViews when a token sub-span changes (lambda param, let-def name) */
  handleTokenEdit(nodeId: number, tokenRole: string, changes: { from: number; to: number; insert: string }[]): void;

  /** Called for structural edits (delete, wrap, etc.) */
  handleStructuralEdit(opType: string, nodeId: number, extra?: Record<string, unknown>): void;
}
