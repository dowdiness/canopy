///|
const DEFAULT_MIN_DEGREE : Int32 = 10

///|
#derive(Debug, Eq)
pub(all) enum BTreeNode[T] {
  Leaf(elem~ : T, span~ : Int32)
  Internal(
    children~ : Array[BTreeNode[T]],
    counts~ : Array[Int32],
    total~ : Int32,
  )
}

///|
#derive(Debug, Eq)
pub(all) struct BTree[T] {
  priv mut root : BTreeNode[T]?
  priv min_degree : Int32
  priv mut size : Int32
}

///|
pub(open) trait BTreeElem: @rle.Spanning + @rle.Mergeable + @rle.Sliceable {}

///|
#derive(Debug, Eq)
pub(all) struct FindResult[T] {
  elem : T
  offset : Int32
}

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
