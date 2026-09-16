import { createAuth } from "./auth";
import { documentRequest } from "./documents";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (!path.startsWith("/api/")) return env.ASSETS.fetch(request);

    let response: Response;
    let sessionHeaders: Headers | undefined;
    try {
      if (path.startsWith("/api/auth/")) {
        response = await createAuth(env).handler(request);
        // OAuth remains library-owned; only redact the returned failure URL.
        const location = response.headers.get("Location");
        if (path.startsWith("/api/auth/callback/") && response.status >= 300 && response.status < 400 && location) {
          const redirect = new URL(location, env.BETTER_AUTH_URL);
          if (redirect.searchParams.has("error")) {
            redirect.searchParams.set("error", "authentication_failed");
            redirect.searchParams.delete("error_description");
            response.headers.set("Location", redirect.href);
          }
        }
      } else if ((path === "/api/account" && request.method === "GET") ||
        path === "/api/documents" || path.startsWith("/api/documents/")) {
        const { response: session, headers } = await createAuth(env).api.getSession({
          headers: request.headers,
          returnHeaders: true,
        });
        sessionHeaders = headers;
        if (!session) {
          response = Response.json({ error: "sign_in_required" }, { status: 401 });
        } else if (path === "/api/account") {
          response = Response.json({ id: session.user.id, name: session.user.name });
        } else {
          response = await documentRequest(request, env.AUTH_DB, session.user.id, new URL(env.BETTER_AUTH_URL).origin);
        }
      } else {
        response = Response.json({ error: "not_found" }, { status: 404 });
      }
    } catch {
      // Do not expose provider errors, cookies, SQL, or identity data in responses/logs.
      console.error("Loomark account service unavailable");
      response = Response.json({ error: "account_unavailable" }, { status: 503 });
    }
    // Session renewal may already be committed even when document handling fails.
    for (const cookie of sessionHeaders?.getSetCookie() ?? []) response.headers.append("Set-Cookie", cookie);
    response.headers.set("Cache-Control", "no-store");
    return response;
  },
} satisfies ExportedHandler<Env>;
