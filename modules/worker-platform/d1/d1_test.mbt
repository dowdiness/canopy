///|
// Host fixtures cross the same opaque types as the real Worker entry point.
extern "js" fn fixture(mode : String) -> @d1.Database =
  #|(mode) => {
  #|  const fail = () => { throw new Error("private SQL and parameters"); };
  #|  const answer = value => {
  #|    if (mode === "throw") return fail();
  #|    if (mode === "reject") return Promise.reject(new Error("private provider failure"));
  #|    if (mode === "invalid") return Promise.resolve(42);
  #|    if (mode === "unserializable") return Promise.resolve({toJSON: fail});
  #|    if (mode === "undefined") return Promise.resolve(undefined);
  #|    return Promise.resolve(value);
  #|  };
  #|  const envelope = row => {
  #|    if (mode === "failed") return {success: false, results: [row], error: "private SQL and parameters"};
  #|    if (mode === "missing-status") return {results: [row]};
  #|    if (mode === "invalid-status") return {success: "true", results: [row]};
  #|    return {success: true, results: [row]};
  #|  };
  #|  return {
  #|    prepare(sql) {
  #|      if (mode === "prepare") return fail();
  #|      return {bind(...values) {
  #|        if (mode === "bind") return fail();
  #|        const row = {sql, values};
  #|        return {row, all: () => answer(envelope(row)), first: () => answer(mode === "missing" ? null : row)};
  #|      }};
  #|    },
  #|    batch(statements) {return answer(mode === "short" ? [] : statements.map((s, i) => i === statements.length - 1 ? envelope(s.row) : {success: true, results: [s.row]}));}
  #|  };
  #|}

///|
async test "D1 preserves parameters and batch order and distinguishes absent rows" {
  let db = fixture("ok")
  let a = db.prepare("first", [Text("日本語"), Number(7.5), Null])
  let b = db.prepare("second", [])
  let expected : Json = { "sql": "first", "values": ["日本語", 7.5, null] }
  assert_true(a.first() == Some(expected))
  assert_eq(a.all(), [expected])
  assert_eq(db.batch([b, a]), [[{ "sql": "second", "values": [] }], [expected]])
  assert_true(fixture("missing").prepare("missing", []).first() is None)
}

///|
test "D1 redacts synchronous prepare and bind failures" {
  for mode in ["prepare", "bind"] {
    let rejected = try {
      let _ = fixture(mode).prepare("secret", [Text("private")])
      false
    } catch {
      @d1.DatabaseError::OperationFailed => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
async test "D1 catches sync and async failures and invalid results after suspension" {
  for mode in ["throw", "reject", "invalid", "unserializable", "undefined"] {
    let db = fixture(mode)
    let statement = db.prepare("secret", [])
    for operation in ["all", "first", "batch"] {
      let rejected = try {
        match operation {
          "all" => {
            let _ = statement.all()
            ()
          }
          "first" => {
            let _ = statement.first()
            ()
          }
          _ => {
            let _ = db.batch([statement])
            ()
          }
        }
        false
      } catch {
        @d1.DatabaseError::OperationFailed =>
          mode == "throw" || mode == "reject"
        @d1.DatabaseError::InvalidResult =>
          mode == "invalid" || mode == "unserializable" || mode == "undefined"
        _ => false
      }
      assert_true(rejected)
    }
  }
  let db = fixture("short")
  let rejected = try {
    let _ = db.batch([db.prepare("a", [])])
    false
  } catch {
    @d1.DatabaseError::InvalidResult => true
    _ => false
  }
  assert_true(rejected)
}

///|
async test "D1 requires a successful envelope for all and every batch result" {
  for mode in ["failed", "missing-status", "invalid-status"] {
    let db = fixture(mode)
    let statement = db.prepare("secret", [Text("private")])
    for operation in ["all", "batch"] {
      let rejected = try {
        if operation == "all" {
          let _ = statement.all()
        } else {
          let _ = db.batch([statement, statement])
        }
        false
      } catch {
        @d1.DatabaseError::OperationFailed => mode == "failed"
        @d1.DatabaseError::InvalidResult => mode != "failed"
        _ => false
      }
      assert_true(rejected)
    }
  }
}
