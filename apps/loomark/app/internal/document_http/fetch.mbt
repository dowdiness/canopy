///|
#external
priv type CompleteResponse

///|
extern "js" fn complete_mutation(
  url : String,
  http_method : String,
  account : String,
  body : String,
) -> @js_async.Promise[CompleteResponse] =
  #| async (url, httpMethod, account, body) => {
  #|   const response = await fetch(url, {
  #|     method: httpMethod,
  #|     headers: {
  #|       "X-Loomark-Account": account,
  #|       "Content-Type": "application/json",
  #|     },
  #|     body,
  #|   });
  #|   const bytes = await response.arrayBuffer();
  #|   const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  #|   return { status: response.status, body: text };
  #| }

///|
extern "js" fn complete_get(
  url : String,
  account : String,
) -> @js_async.Promise[CompleteResponse] =
  #| async (url, account) => {
  #|   const response = await fetch(url, {
  #|     headers: { "X-Loomark-Account": account },
  #|   });
  #|   const bytes = await response.arrayBuffer();
  #|   const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  #|   return { status: response.status, body: text };
  #| }

///|
extern "js" fn CompleteResponse::status(self : CompleteResponse) -> Int =
  #| response => response.status

///|
extern "js" fn CompleteResponse::body(self : CompleteResponse) -> String =
  #| response => response.body
