///|
extern "js" fn js_fetch(
  url : String,
  http_method : String,
  headers_json : String,
  body : String,
) -> @js_async.Promise[String] =
  #| (url, httpMethod, headersJson, body) => {
  #|   return fetch(url, {
  #|     method: httpMethod,
  #|     headers: JSON.parse(headersJson),
  #|     body: body || undefined,
  #|   }).then(async r => {
  #|     const text = await r.text();
  #|     if (!r.ok) throw new Error(`HTTP ${r.status}: ${text.slice(0, 200)}`);
  #|     return text;
  #|   })
  #| }
