///|
/// A platform-provided D1 binding, passed by the Worker host. Not constructible
/// from arbitrary JavaScript values through this package's MoonBit API.
#external
pub type Database

///|
#external
pub type Statement

///|
/// The supported SQLite parameter subset. No implicit Bool or Option encoding.
pub(all) enum Value {
  Text(String)
  Number(Double)
  Null
}

///|
/// Redacted failures: SQL, bound values and provider exceptions never escape.
pub(all) suberror DatabaseError {
  OperationFailed
  InvalidResult
} derive(Debug, Eq)

///|
fn Value::to_js(self : Value) -> @js.Any {
  match self {
    Text(value) => @js.any(value)
    Number(value) => @js.any(value)
    Null => @js.null_()
  }
}

///|
pub fn Database::prepare(
  self : Database,
  sql : String,
  parameters : ArrayView[Value],
) -> Statement raise DatabaseError {
  @js.try_sync(() => {
    @js.any(self)
    .call("prepare", [@js.any(sql)])
    .call("bind", parameters.map(value => value.to_js()))
  }).cast() catch {
    _ => raise OperationFailed
  }
}

///|
fn rows(result : Json) -> Array[Json] raise DatabaseError {
  match result {
    { "success": False, .. } => raise OperationFailed
    { "success": True, "results": Array(rows), .. } => rows
    _ => raise InvalidResult
  }
}

///|
fn decode(value : @js.Any) -> Json raise DatabaseError {
  let text : String = @js.try_sync(() => @js.any(value.stringify())).cast() catch {
    _ => raise InvalidResult
  }
  @json.parse(text) catch {
    _ => raise InvalidResult
  }
}

///|
pub async fn Statement::all(self : Statement) -> Array[Json] {
  let result : @js.Any = @js.try_sync(() => @js.any(self).call("all", [])).await_() catch {
    _ => raise OperationFailed
  }
  rows(decode(result))
}

///|
pub async fn Statement::first(self : Statement) -> Json? {
  let result : @js.Any = @js.try_sync(() => @js.any(self).call("first", [])).await_() catch {
    _ => raise OperationFailed
  }
  let row = decode(result)
  match row {
    Null => None
    Object(_) => Some(row)
    _ => raise InvalidResult
  }
}

///|
/// Executes one atomic D1 batch. Failure rejects the whole batch; the caller
/// must await completion before acknowledging durability. Results retain order.
pub async fn Database::batch(
  self : Database,
  statements : ArrayView[Statement],
) -> Array[Array[Json]] {
  let result : @js.Any = @js.try_sync(() => {
    @js.any(self).call("batch", [
      @js.any(FixedArray::from_array(statements.to_owned())),
    ])
  }).await_() catch {
    _ => raise OperationFailed
  }
  let value = decode(result)
  guard value is Array(results) && results.length() == statements.length() else {
    raise InvalidResult
  }
  results.map(rows)
}
