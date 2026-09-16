import { env } from "cloudflare:workers";
import { betterAuth } from "better-auth";
import { getMigrations } from "better-auth/db/migration";
import { testUtils } from "better-auth/plugins";
import { expect, test, vi } from "vitest";
import { createAuth } from "./auth";
import worker from "./index";

test("checked-in migration matches the installed Better Auth configuration", async () => {
  const migration = await getMigrations(createAuth(env).options);
  expect(migration.toBeCreated).toEqual([]);
  expect(migration.toBeAdded).toEqual([]);
  expect(migration.toBeAddedIndexes).toEqual([]);
  expect(migration.schemaProblems).toEqual([]);
});

test("anonymous account requests are not authenticated", async () => {
  const response = await worker.fetch(new Request("https://loomark.test/api/account"), env);
  expect(response.status).toBe(401);
  expect(response.headers.get("cache-control")).toBe("no-store");
});

test("session user lookup failures never log private database errors", async () => {
  const { test: helpers } = await betterAuth({
    ...createAuth(env).options, plugins: [testUtils()],
  }).$context;
  const user = await helpers.saveUser(helpers.createUser());
  const headers = await helpers.getAuthHeaders({ userId: user.id });
  const marker = "PRIVATE-D1-USER-LOOKUP";
  let failed = false;
  const database = new Proxy(env.AUTH_DB, {
    get(target, key, receiver) {
      if (key === "prepare") return (sql: string) => {
        if (sql.includes('"user"')) {
          failed = true;
          throw new Error(marker);
        }
        return target.prepare(sql);
      };
      return Reflect.get(target, key, receiver);
    },
  });
  const logs = (["error", "warn", "info", "debug", "log"] as const)
    .map(level => vi.spyOn(console, level).mockImplementation(() => {}));
  try {
    const response = await worker.fetch(new Request("https://loomark.test/api/account", { headers }), {
      ...env, AUTH_DB: database,
    });
    expect(failed).toBe(true);
    expect(response.status).toBe(503);
    expect(await response.text()).not.toContain(marker);
    expect(logs.flatMap(log => log.mock.calls.flat()).map(String).join("\n")).not.toContain(marker);
  } finally {
    for (const log of logs) log.mockRestore();
  }
});

test("Google sign-in uses Better Auth state and PKCE with a fixed callback", async () => {
  const response = await worker.fetch(new Request("https://loomark.test/api/auth/sign-in/social", {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "https://loomark.test" },
    body: JSON.stringify({ provider: "google", callbackURL: "/", disableRedirect: true }),
  }), env);
  expect(response.status).toBe(200);
  const result = await response.json<{ url: string }>();
  const url = new URL(result.url);
  expect(url.origin).toBe("https://accounts.google.com");
  expect(url.searchParams.get("redirect_uri")).toBe("https://loomark.test/api/auth/callback/google");
  expect(url.searchParams.get("state")).toBeTruthy();
  expect(url.searchParams.get("code_challenge_method")).toBe("S256");
  const cookies = response.headers.get("set-cookie") ?? "";
  expect(cookies).toContain("HttpOnly");
  expect(cookies).toContain("Secure");
});

test("Better Auth rejects cookie-bearing CSRF and untrusted redirects", async () => {
  for (const [origin, callbackURL] of [
    ["https://attacker.test", "/"],
    ["https://loomark.test", "https://attacker.test"],
  ]) {
    const response = await worker.fetch(new Request("https://loomark.test/api/auth/sign-in/social", {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: origin, Cookie: "browser=present" },
      body: JSON.stringify({ provider: "google", callbackURL }),
    }), env);
    expect(response.status).toBe(403);
  }
});

test("OAuth failure redirects omit provider details and preserve state cleanup cookies", async () => {
  const start = await worker.fetch(new Request("https://loomark.test/api/auth/sign-in/social", {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "https://loomark.test", "cf-connecting-ip": "192.0.2.20" },
    body: JSON.stringify({ provider: "google", callbackURL: "/", errorCallbackURL: "/", disableRedirect: true }),
  }), env);
  expect(start.status).toBe(200);
  const authorization = new URL((await start.json<{ url: string }>()).url);
  const callback = new URL("https://loomark.test/api/auth/callback/google");
  callback.searchParams.set("state", authorization.searchParams.get("state")!);
  callback.searchParams.set("error", "PRIVATE-PROVIDER-CODE");
  callback.searchParams.set("error_description", "PRIVATE-PROVIDER-DESCRIPTION");
  const response = await worker.fetch(new Request(callback, {
    headers: { Cookie: start.headers.getSetCookie().map(cookie => cookie.split(";")[0]).join("; ") },
  }), env);
  expect(response.status).toBe(302);
  expect(response.headers.get("location")).toBe("https://loomark.test/?error=authentication_failed");
  expect(response.headers.getSetCookie().join(";")).toContain("Max-Age=0");
  expect(response.headers.get("cache-control")).toBe("no-store");
});

test("cookieless cross-origin JSON requests cannot pass browser CORS preflight", async () => {
  const response = await worker.fetch(new Request("https://loomark.test/api/auth/sign-in/social", {
    method: "OPTIONS",
    headers: {
      Origin: "https://attacker.test",
      "Access-Control-Request-Method": "POST",
      "Access-Control-Request-Headers": "content-type",
    },
  }), env);
  expect(response.headers.get("Access-Control-Allow-Origin")).toBeNull();
  expect(response.headers.get("Access-Control-Allow-Credentials")).toBeNull();
});

test("sessions survive fresh auth instances and logout revokes the old cookie", async () => {
  const auth = betterAuth({ ...createAuth(env).options, plugins: [testUtils()] });
  const { test: helpers } = await auth.$context;
  const user = await helpers.saveUser(helpers.createUser({ email: "phone@example.test" }));
  const headers = await helpers.getAuthHeaders({ userId: user.id });
  const account = await worker.fetch(new Request("https://loomark.test/api/account", { headers }), env);
  expect(account.status).toBe(200);
  expect(await account.json()).toEqual({ id: user.id, name: user.name });
  headers.set("Origin", "https://loomark.test");
  headers.set("Content-Type", "application/json");
  const logout = await worker.fetch(new Request("https://loomark.test/api/auth/sign-out", {
    method: "POST", headers, body: "{}",
  }), env);
  expect(logout.status).toBe(200);
  const replay = await worker.fetch(new Request("https://loomark.test/api/account", { headers }), env);
  expect(replay.status).toBe(401);
});

test("production auth has no password, test-login, or migration endpoint", async () => {
  for (const route of ["/api/auth/sign-up/email", "/api/test-login", "/api/migrate"]) {
    const response = await worker.fetch(new Request(`https://loomark.test${route}`, {
      method: "POST",
      headers: { Origin: "https://loomark.test", "Content-Type": "application/json" },
      body: "{}",
    }), env);
    expect([400, 404]).toContain(response.status);
  }
});
