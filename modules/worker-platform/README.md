# Worker platform bindings

`dowdiness/worker_platform` provides a small, JS-target-only boundary for
platform operations used by MoonBit Worker applications. It is not a complete
Cloudflare SDK, an ORM, or an authentication framework.

- `http`: opaque Request/Response handles, request metadata, bounded strict
  UTF-8 body consumption, and JSON responses. The caller chooses admission
  limits, routing, content types, authentication, and HTTP error policy.
- `d1`: opaque Database/Statement handles, explicit text/number/null parameters,
  first/all queries, and ordered atomic batches. It converts synchronous host
  exceptions and rejected promises to redacted errors, and validates result
  envelopes: `all` and every batch result require `success: true` and a results
  array. An explicit failure becomes `OperationFailed`; malformed envelopes
  become `InvalidResult`. Applications validate row schemas and own SQL and
  migrations.
- `crypto`: Web Crypto SHA-256, using core `encoding/utf8` and `encoding/hex`
  for encoding. Callers use core UTF-8 directly for byte counts. This package
  does not implement cryptographic algorithms or OAuth itself.

The public MoonBit interfaces contain no `js.Any`; dynamic calls and casts are
private implementation details backed by the existing `dowdiness/js_ffi`
exception and Promise bridge. Host handles must come from the real Worker
runtime, not untrusted JSON. The compiler currently emits `any` for external
handles in TypeScript declarations: MoonBit's opaque types do not validate a
JavaScript caller. Keep the TypeScript host signature typed and test that
boundary against workerd.

Body reads consume the stream once. Oversize input cancels the reader and all
read/decode completion paths release its lock. A missing body is invalid;
an empty body is valid at a zero-byte limit. Provider failures must be mapped
to application responses at the host; never log private SQL or parameters.

The stream bridge intentionally does not use `async/js_async.ReadableStream`.
With async 0.22.1, a stream that supplies valid bytes then rejects can appear
to finish normally through `io.Reader`; closing it also produced an unhandled
rejection in the Node probe. Retain explicit read-error propagation until an
upstream fix passes this boundary's interrupted-body and cleanup tests.
The async Promise bridge is still reused; no fork of async is maintained.

Account identity, authorization, document revisions, receipts, tombstones, and
conflict policy deliberately remain outside this module. Add platform APIs
only when another concrete caller needs them, rather than copying an SDK.

From the Canopy workspace root:

```sh
NEW_MOON_MOD=0 moon test --target js -p dowdiness/worker_platform/http dowdiness/worker_platform/d1 dowdiness/worker_platform/crypto
NEW_MOON_MOD=0 moon info --target js -p dowdiness/worker_platform
npm --prefix apps/loomark run test:server
```

Module tests cover generated Unicode byte limits, split/invalid UTF-8, stream
lock cleanup, standard SHA-256, parameter/result order, and synchronous,
asynchronous, and malformed D1 results. Loomark integration tests exercise
the real Workers runtime and disposable D1, including atomic receipts and
cross-account isolation. They do not prove deployed service availability.
