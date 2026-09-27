///|
const DEFAULT_MIN_DEGREE : Int = 10

///|
pub(all) enum BTreeNode[T] {
  Leaf(elem~ : T, span~ : Int)
  Internal(children~ : Array[BTreeNode[T]], counts~ : Array[Int], total~ : Int)
} derive(Debug, Eq)

///|
pub(all) struct BTree[T] {
  priv mut root : BTreeNode[T]?
  priv min_degree : Int
  priv mut size : Int
} derive(Debug, Eq)

///|
pub(open) trait BTreeElem: @rle.Spanning + @rle.Mergeable + @rle.Sliceable {}

///|
pub(all) struct FindResult[T] {
  elem : T
  offset : Int
} derive(Debug, Eq)

///|
pub impl[T : Debug] Show for FindResult[T] with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend BTree with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BTree with Eq::{equal, not_equal}

///|
pub extend BTreeNode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BTreeNode with Eq::{equal, not_equal}

///|
pub extend FindResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FindResult with Eq::{equal, not_equal}

///|
pub extend FindResult with Show::{output, to_string}
