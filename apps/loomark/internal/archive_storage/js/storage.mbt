///|
/// Allocate a browser-side UUID for a fresh writing or document identity.
///
/// `randomUUID` is unavailable on some ordinary HTTP origins. Keep identity
/// allocation available there without weakening the one-identity-per-writing-
/// instance boundary.
pub extern "js" fn random_uuid() -> String =
  #| () => {
  #|   const crypto = globalThis.crypto;
  #|   if (typeof crypto?.randomUUID === "function") return crypto.randomUUID();
  #|   if (typeof crypto?.getRandomValues === "function") {
  #|     const bytes = crypto.getRandomValues(new Uint8Array(16));
  #|     bytes[6] = (bytes[6] & 0x0f) | 0x40;
  #|     bytes[8] = (bytes[8] & 0x3f) | 0x80;
  #|     const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, "0"));
  #|     return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
  #|   }
  #|   return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
  #| }

///|
/// Read callback result codes: missing, loaded, unavailable, failed.
pub extern "js" fn get_item(
  key : String,
  callback : (Int, String) -> Unit,
) -> Unit =
  #| (key, callback) => {
  #|   let kind;
  #|   let value = "";
  #|   try {
  #|     const storage = globalThis.localStorage;
  #|     if (storage == null) {
  #|       kind = 2;
  #|     } else {
  #|       const stored = storage.getItem(key);
  #|       kind = stored === null ? 0 : 1;
  #|       value = stored === null ? "" : stored;
  #|     }
  #|   } catch (error) {
  #|     const name = error?.name;
  #|     kind = name === "SecurityError" || name === "InvalidStateError" ? 2 : 3;
  #|   }
  #|   callback(kind, value);
  #| }

///|
/// Write callback result codes: success, unavailable, quota exceeded, failed.
pub extern "js" fn set_item(
  key : String,
  value : String,
  callback : (Int) -> Unit,
) -> Unit =
  #| (key, value, callback) => {
  #|   let kind;
  #|   try {
  #|     const storage = globalThis.localStorage;
  #|     if (storage == null) {
  #|       kind = 1;
  #|     } else {
  #|       storage.setItem(key, value);
  #|       kind = 0;
  #|     }
  #|   } catch (error) {
  #|     const name = error?.name;
  #|     if (name === "SecurityError" || name === "InvalidStateError") {
  #|       kind = 1;
  #|     } else if (name === "QuotaExceededError" || error?.code === 22 || error?.code === 1014) {
  #|       kind = 2;
  #|     } else {
  #|       kind = 3;
  #|     }
  #|   }
  #|   callback(kind);
  #| }
