import { betterAuth, type BetterAuthOptions } from "better-auth";

type AuthConfiguration = Pick<Env,
  "BETTER_AUTH_URL" | "BETTER_AUTH_SECRET" | "GOOGLE_CLIENT_ID" | "GOOGLE_CLIENT_SECRET"
>;

// Shared with schema generation: database tables follow this exact configuration.
export function authOptions(config: AuthConfiguration) {
  return {
    appName: "Loomark",
    baseURL: config.BETTER_AUTH_URL,
    secret: config.BETTER_AUTH_SECRET,
    trustedOrigins: [new URL(config.BETTER_AUTH_URL).origin],
    socialProviders: {
      google: {
        clientId: config.GOOGLE_CLIENT_ID,
        clientSecret: config.GOOGLE_CLIENT_SECRET,
        accessType: "online",
        prompt: "select_account",
      },
    },
    account: {
      accountLinking: { enabled: false },
      encryptOAuthTokens: true,
    },
    // Revocations must take effect on the next request, not after a cookie cache TTL.
    session: { cookieCache: { enabled: false } },
    rateLimit: { enabled: true, storage: "database" },
    advanced: {
      // D1 supports native joins. Avoid the fallback join path in Better Auth
      // 1.7.5, which logs raw database errors outside the configured logger.
      database: { joins: true },
      ipAddress: { ipAddressHeaders: ["cf-connecting-ip"] },
    },
    telemetry: { enabled: false },
    logger: {
      level: "error",
      // Provider/database errors can contain credentials or user data.
      log() { console.error("Loomark authentication failed"); },
    },
  } satisfies BetterAuthOptions;
}

export function createAuth(env: Env) {
  return betterAuth({ ...authOptions(env), database: env.AUTH_DB });
}
