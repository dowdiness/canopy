///|
const DEFAULT_MIN_DEGREE : Int = 10

///|
pub(all) enum BTreeNode[T] {
  Leaf(elem~ : T, span~ : Int)
  Internal(children~ : Array[BTreeNode[T]], counts~ : Array[Int], total~ : Int)
} derive(Debug, Eq)

///|
pub struct BTree[T] {
  mut root : BTreeNode[T]?
  min_degree : Int
  mut size : Int
} derive(Debug, Eq)

///|
pub struct FindResult[T] {
  elem : T
  offset : Int
} derive(Debug, Eq)

///|
pub impl[T : Debug] Show for FindResult[T] with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
