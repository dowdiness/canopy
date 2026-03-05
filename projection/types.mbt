// Core types for Projectional Editing
// These types enable bidirectional transformation between projections

///|
using @loomcore {type Range}

///|
/// Unique identifier for AST nodes (persistent across edits)
pub struct NodeId(Int) derive(Show, Eq, Hash, Compare)

///|
/// Identifier for different projections
pub enum ProjectionId {
  Text
  Tree
  Custom(String)
} derive(Show, Eq, Hash)

///|
/// Leaf values that can be edited in AST nodes
pub enum LeafValue {
  IntValue(Int)
  VarName(String)
  OpSymbol(String)
} derive(Show, Eq)

///|
/// Operations on the canonical model (edit algebra)
pub enum ModelOperation {
  /// Insert a new node as a child
  InsertNode(parent~ : NodeId, index~ : Int, node~ : ProjNode)
  /// Delete a node and its descendants
  DeleteNode(node_id~ : NodeId)
  /// Replace a node with a new one (preserves ID)
  ReplaceNode(node_id~ : NodeId, new_node~ : ProjNode)
  /// Update a leaf value (Int, Var name, Op symbol)
  UpdateLeaf(node_id~ : NodeId, new_value~ : LeafValue)
  /// Move a node to a new parent
  MoveNode(node_id~ : NodeId, new_parent~ : NodeId, new_index~ : Int)
} derive(Show)

///|
/// Validation levels for AST nodes
pub enum ValidationLevel {
  /// Is the syntax valid?
  Syntactic
  /// Does it type-check?
  Semantic
  /// Will it run without errors?
  Dynamic
} derive(Show, Eq)

///|
/// Drop position for drag-and-drop operations
pub enum DropPosition {
  /// Insert before the target
  Before
  /// Insert after the target
  After
  /// Insert as a child of the target
  Inside
} derive(Show, Eq)
