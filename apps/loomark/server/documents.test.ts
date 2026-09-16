import { env } from "cloudflare:workers";
import { betterAuth } from "better-auth";
import { testUtils } from "better-auth/plugins";
import { expect, test } from "vitest";
import { createAuth } from "./auth";
import { documentRequest } from "./documents";
import worker from "./index";

async function account() {
  const { test: helpers } = await betterAuth({
    ...createAuth(env).options, plugins: [testUtils()],
  }).$context;
  const user = await helpers.saveUser(helpers.createUser());
  const headers = await helpers.getAuthHeaders({ userId: user.id });
  headers.set("X-Loomark-Account", user.id);
  headers.set("Origin", "https://loomark.test");
  headers.set("Content-Type", "application/json");
  return {
    id: user.id,
    async request(path: string, method = "GET", body?: unknown) {
      return worker.fetch(new Request(`https://loomark.test/api/documents${path}`, {
        method, headers, body: body === undefined ? undefined : JSON.stringify(body),
      }), env);
    },
    headers,
  };
}

test("a newly signed-in device can list and reopen a committed document", async () => {
  const phone = await account();
  const id = crypto.randomUUID();
  const write = await phone.request(`/${id}`, "PUT", {
    operationId: crypto.randomUUID(), baseRevision: 0, text: "# スマホ\n続き 🌳",
  });
  expect(write.status).toBe(200);
  expect(await write.json()).toMatchObject({ id, revision: 1 });
  const list = await phone.request("");
  expect(await list.json()).toMatchObject({ documents: [{ id, revision: 1, deleted: false }] });
  // Every request constructs a new auth instance; no live peer or in-memory room.
  const opened = await phone.request(`/${id}`);
  expect(await opened.json()).toEqual({ id, revision: 1, text: "# スマホ\n続き 🌳", deleted: false });
});

test("a lost response retry cannot overwrite a later PC edit", async () => {
  const client = await account();
  const id = crypto.randomUUID();
  const first = { operationId: crypto.randomUUID(), baseRevision: 0, text: "phone" };
  const accepted = await client.request(`/${id}`, "PUT", first);
  expect(accepted.status).toBe(200);
  const second = await client.request(`/${id}`, "PUT", {
    operationId: crypto.randomUUID(), baseRevision: 1, text: "phone + PC",
  });
  expect(second.status).toBe(200);
  const replay = await client.request(`/${id}`, "PUT", first);
  expect(await replay.json()).toEqual(await accepted.json());
  expect(await (await client.request(`/${id}`)).json()).toMatchObject({ revision: 2, text: "phone + PC" });
  const misuse = await client.request(`/${id}`, "PUT", { ...first, text: "different" });
  expect(misuse.status).toBe(422);
});

test("concurrent saves accept one version and preserve it against stale writes/deletes", async () => {
  const client = await account();
  const id = crypto.randomUUID();
  expect((await client.request(`/${id}`, "PUT", {
    operationId: crypto.randomUUID(), baseRevision: 0, text: "base",
  })).status).toBe(200);
  const edits = await Promise.all(["phone", "PC"].map(text => client.request(`/${id}`, "PUT", {
    operationId: crypto.randomUUID(), baseRevision: 1, text,
  })));
  expect(edits.map(response => response.status).sort()).toEqual([200, 409]);
  expect((await client.request(`/${id}`, "DELETE", {
    operationId: crypto.randomUUID(), baseRevision: 1,
  })).status).toBe(409);
  expect(await (await client.request(`/${id}`)).json()).toMatchObject({ revision: 2, deleted: false });
});

test("a tombstone survives repeated deletion and cannot be recreated by an offline device", async () => {
  const client = await account();
  const id = crypto.randomUUID();
  await client.request(`/${id}`, "PUT", {
    operationId: crypto.randomUUID(), baseRevision: 0, text: "original",
  });
  const deletion = { operationId: crypto.randomUUID(), baseRevision: 1 };
  const deleted = await client.request(`/${id}`, "DELETE", deletion);
  expect(deleted.status).toBe(200);
  expect(await (await client.request(`/${id}`, "DELETE", deletion)).json()).toEqual(await deleted.json());
  for (const baseRevision of [0, 1, 2]) {
    expect((await client.request(`/${id}`, "PUT", {
      operationId: crypto.randomUUID(), baseRevision, text: "offline edit",
    })).status).toBe(409);
  }
  expect(await (await client.request(`/${id}`)).json()).toEqual({ id, revision: 2, text: null, deleted: true });
});

test("another account cannot read or mutate a guessed document identity", async () => {
  const owner = await account();
  const other = await account();
  const id = crypto.randomUUID();
  await owner.request(`/${id}`, "PUT", {
    operationId: crypto.randomUUID(), baseRevision: 0, text: "private",
  });
  expect((await other.request(`/${id}`)).status).toBe(404);
  expect(await (await other.request("")).json()).toMatchObject({ documents: [] });
  expect((await other.request(`/${id}`, "PUT", {
    operationId: crypto.randomUUID(), baseRevision: 1, text: "attack",
  })).status).toBe(409);
  other.headers.set("X-Loomark-Account", owner.id);
  expect((await other.request(`/${id}`)).status).toBe(409);
  expect(await (await owner.request(`/${id}`)).json()).toMatchObject({ text: "private" });
});

test("document mutations reject cross-origin requests and malformed data", async () => {
  const client = await account();
  const id = crypto.randomUUID();
  const body = { operationId: crypto.randomUUID(), baseRevision: 0, text: "valid" };
  expect((await client.request(`/${id}`, "PUT", { ...body, owner: "forged" })).status).toBe(400);
  client.headers.set("Origin", "https://attacker.test");
  expect((await client.request(`/${id}`, "PUT", body)).status).toBe(403);
  expect((await client.request(`/${id}`)).status).toBe(404);
});

test.each(["prepare", "batch"])("synchronous D1 %s exceptions reject the FFI promise instead of hanging", async (failingMethod) => {
  const request = new Request(`https://loomark.test/api/documents/${crypto.randomUUID()}`, {
    method: "PUT",
    headers: {
      "X-Loomark-Account": "account", Origin: "https://loomark.test", "Content-Type": "application/json",
    },
    body: JSON.stringify({ operationId: crypto.randomUUID(), baseRevision: 0, text: "retained locally" }),
  });
  const brokenDb = new Proxy(env.AUTH_DB, {
    get(target, key, receiver) {
      if (key === failingMethod) return () => { throw new Error("test-only storage failure"); };
      return Reflect.get(target, key, receiver);
    },
  });
  await expect(documentRequest(request, brokenDb, "account", "https://loomark.test")).rejects.toBeDefined();
});

test("Unicode byte limits and invalid UTF-8 reject without replacing saved text", async () => {
  const client = await account();
  const id = crypto.randomUUID();
  const text = "界".repeat(349525) + "a"; // exactly 1 MiB, not 1 Mi characters
  expect((await client.request(`/${id}`, "PUT", {
    operationId: crypto.randomUUID(), baseRevision: 0, text,
  })).status).toBe(200);
  expect((await client.request(`/${id}`, "PUT", {
    operationId: crypto.randomUUID(), baseRevision: 1, text: text + "a",
  })).status).toBe(413);
  const invalid = await worker.fetch(new Request(`https://loomark.test/api/documents/${id}`, {
    method: "PUT", headers: client.headers, body: new Uint8Array([0xff]),
  }), env);
  expect(invalid.status).toBe(400);
  expect(await (await client.request(`/${id}`)).json()).toMatchObject({ revision: 1, text });
});

test("failed D1 document write rolls back its receipt and permits the same retry", async () => {
  const client = await account();
  const id = crypto.randomUUID();
  const body = { operationId: crypto.randomUUID(), baseRevision: 0, text: "recoverable" };
  // Make the real session refresh-due without expiring it.
  const oldExpiry = Date.now() + 60_000;
  await env.AUTH_DB.prepare('UPDATE "session" SET "expiresAt" = ? WHERE "userId" = ?')
    .bind(new Date(oldExpiry).toISOString(), client.id).run();
  // Disposable test D1 only. Fail the second statement after receipt admission.
  await env.AUTH_DB.exec(`CREATE TRIGGER loomark_test_fail_write BEFORE INSERT ON loomark_document BEGIN SELECT RAISE(ABORT, 'test-only failure'); END`);
  try {
    const failed = await client.request(`/${id}`, "PUT", body);
    expect(failed.status).toBe(503);
    expect(await failed.json()).toEqual({ error: "account_unavailable" });
    const session = await env.AUTH_DB.prepare('SELECT "expiresAt" FROM "session" WHERE "userId" = ?')
      .bind(client.id).first<{ expiresAt: string }>();
    expect(new Date(session!.expiresAt).getTime()).toBeGreaterThan(oldExpiry);
    const cookies = failed.headers.getSetCookie().filter(cookie => cookie.includes("session_token="));
    expect(cookies).toHaveLength(1);
    expect(cookies[0]).toContain("HttpOnly");
    expect(failed.headers.get("cache-control")).toBe("no-store");
    expect(await env.AUTH_DB.prepare("SELECT revision FROM loomark_receipt WHERE owner = ? AND operation_id = ?")
      .bind(client.id, body.operationId).first()).toBeNull();
    expect((await client.request(`/${id}`)).status).toBe(404);
  } finally {
    await env.AUTH_DB.exec("DROP TRIGGER loomark_test_fail_write");
  }
  expect((await client.request(`/${id}`, "PUT", body)).status).toBe(200);
  expect(await (await client.request(`/${id}`)).json()).toMatchObject({ revision: 1, text: "recoverable" });
});
