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
