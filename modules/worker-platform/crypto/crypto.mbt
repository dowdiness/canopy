///|
pub(all) suberror CryptoError {
  DigestFailed
} derive(Debug, Eq)

///|
/// Hashes UTF-8 text with Web Crypto, returning lowercase hexadecimal.
pub async fn sha256(text : String) -> String {
  let digest : @js.Any = @js.try_sync(() => {
    @js.global()
    .get("crypto")
    .get("subtle")
    .call("digest", [@js.any("SHA-256"), @js.any(@utf8.encode(text))])
  }).await_() catch {
    _ => raise DigestFailed
  }
  let bytes : Bytes = @js.global().get("Uint8Array").construct([digest]).cast()
  @hex.encode(bytes)
}
