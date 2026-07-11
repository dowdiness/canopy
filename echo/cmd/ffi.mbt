// FFI stubs for functionality not in moonbitlang/x.
// File I/O and args now use @x/fs and @x/sys.

///|
extern "js" fn get_home_dir() -> String =
  #|() => require('node:os').homedir()

///|
extern "js" fn now_iso() -> String =
  #|() => new Date().toISOString()

///|
extern "js" fn path_join(a : String, b : String) -> String =
  #|(a, b) => require('node:path').join(a, b)
