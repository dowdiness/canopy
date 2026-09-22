/// <reference path="../../server/worker-configuration.d.ts" />

import { betterAuth } from "better-auth"
import { testUtils } from "better-auth/plugins"
import { createAuth } from "../../server/auth"
import production from "../../server/index"

const accounts = {
  phone: {
    id: "11111111-1111-4111-8111-111111111111",
    name: "Phone account",
    email: "phone@loomark.test",
  },
  conflict: {
    id: "33333333-3333-4333-8333-333333333333",
    name: "Conflict account",
    email: "conflict@loomark.test",
  },
  deletion: {
    id: "55555555-5555-4555-8555-555555555555",
    name: "Deletion account",
    email: "deletion@loomark.test",
  },
  accountA: {
    id: "44444444-4444-4444-8444-444444444444",
    name: "Account A",
    email: "account-a@loomark.test",
  },
  other: {
    id: "22222222-2222-4222-8222-222222222222",
    name: "Other account",
    email: "other@loomark.test",
  },
} as const

let loseNextMutationResponse = false

async function createSession(request: Request, env: Env): Promise<Response> {
  const body = await request.json<{ account?: keyof typeof accounts }>()
  const account = body.account === undefined ? undefined : accounts[body.account]
  if (!account) return Response.json({ error: "unknown_account" }, { status: 400 })

  const auth = betterAuth({ ...createAuth(env).options, plugins: [testUtils()] })
  const { test } = await auth.$context
  const existing = await env.AUTH_DB.prepare('SELECT "id" FROM "user" WHERE "id" = ?')
    .bind(account.id)
    .first()
  if (!existing) {
    await test.saveUser(test.createUser({
      id: account.id,
      name: account.name,
      email: account.email,
      emailVerified: true,
    }))
  }
  const login = await test.login({ userId: account.id })
  const headers = new Headers({
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
  })
  for (const cookie of login.cookies) {
    headers.append(
      "Set-Cookie",
      `${cookie.name}=${cookie.value}; Path=${cookie.path}; HttpOnly; SameSite=${cookie.sameSite ?? "Lax"}`,
    )
  }
  return new Response(JSON.stringify(account), { headers })
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url)
    if (url.pathname === "/__e2e__/session" && request.method === "POST") {
      return createSession(request, env)
    }
    if (url.pathname === "/__e2e__/lose-next-mutation-response" && request.method === "POST") {
      loseNextMutationResponse = true
      return new Response(null, { status: 204 })
    }

    const response = await production.fetch(request, env)
    const mutation = url.pathname.startsWith("/api/documents/") &&
      (request.method === "PUT" || request.method === "DELETE")
    if (mutation && loseNextMutationResponse && response.status === 200) {
      loseNextMutationResponse = false
      return Response.json({ error: "response_lost" }, { status: 503 })
    }
    return response
  },
} satisfies ExportedHandler<Env>
