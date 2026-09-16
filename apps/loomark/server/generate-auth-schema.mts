import { DatabaseSync } from "node:sqlite";
import { getMigrations } from "better-auth/db/migration";
import { authOptions } from "./auth.ts";

// Print reviewable SQL, never migrate a running service or overwrite a migration.
const database = new DatabaseSync(":memory:");
try {
  const migration = await getMigrations({
    ...authOptions({
      BETTER_AUTH_URL: "https://schema.invalid",
      BETTER_AUTH_SECRET: "schema-generation-only-not-a-deployed-secret",
      GOOGLE_CLIENT_ID: "schema-generation",
      GOOGLE_CLIENT_SECRET: "schema-generation",
    }),
    database,
  });
  process.stdout.write(await migration.compileMigrations());
} finally {
  database.close();
}
