///|
pub(all) struct BinderId(Int) derive(Debug, Eq, Hash)

///|
pub(all) enum BinderOrigin {
  SourceDecl(node_id~ : @core.NodeId, hint~ : String)
  Generated(Int)
} derive(Debug, Eq)

///|
pub(all) struct Binder {
  id : BinderId
  hint : String
  origin : BinderOrigin
} derive(Debug, Eq)

///|
pub(all) enum FreeOrigin {
  SourceVar
  SourceUnbound
  GeneratedFree
} derive(Debug, Eq)

///|
pub(all) struct FreeName {
  name : String
  origin : FreeOrigin
} derive(Debug, Eq)

///|
pub(all) enum AlphaRef {
  Bound(BinderId)
  Free(FreeName)
} derive(Debug, Eq)

///|
pub(all) enum AlphaTerm {
  Int(Int)
  Unit
  Var(AlphaRef)
  Lam(Binder, AlphaTerm)
  App(AlphaTerm, AlphaTerm)
  Bop(@ast.Bop, AlphaTerm, AlphaTerm)
  If(AlphaTerm, AlphaTerm, AlphaTerm)
  LetDef(Binder, AlphaTerm)
  Module(Array[(Binder, AlphaTerm)], AlphaTerm)
  Error(String)
  Hole(Int)
} derive(Debug, Eq)

///|
pub(all) enum ReifyPolicy {
  Display
  Source
} derive(Debug, Eq)
