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

///|
pub extend AlphaRef with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AlphaRef with Eq::{equal, not_equal}

///|
pub extend AlphaTerm with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AlphaTerm with Eq::{equal, not_equal}

///|
pub extend Binder with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Binder with Eq::{equal, not_equal}

///|
pub extend BinderId with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BinderId with Eq::{equal, not_equal}

///|
pub extend BinderId with Hash::{hash, hash_combine}

///|
pub extend BinderOrigin with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BinderOrigin with Eq::{equal, not_equal}

///|
pub extend FreeName with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FreeName with Eq::{equal, not_equal}

///|
pub extend FreeOrigin with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FreeOrigin with Eq::{equal, not_equal}

///|
pub extend ReifyPolicy with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ReifyPolicy with Eq::{equal, not_equal}
