// Load in request scope: MoonBit's runtime may initialize platform resources.
// The compiler generates the JS module and its declarations together.
export async function documentRequest(
  request: Request, db: D1Database, owner: string, origin: string,
): Promise<Response> {
  const { document_request } = await import(
    "../../../_build/js/release/build/dowdiness/loomark/server/documents/documents.js"
  );
  return document_request(request, db, owner, origin);
}
