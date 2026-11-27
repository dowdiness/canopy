///|
/// The device clock, in milliseconds since the epoch.
pub extern "js" fn now() -> Double =
  #| () => Date.now()

///|
/// Today's date on the device clock in its time zone, as `YYYY-MM-DD`.
pub extern "js" fn local_date() -> String =
  #| () => {
  #|   const d = new Date();
  #|   const pad = (n) => String(n).padStart(2, "0");
  #|   return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  #| }
