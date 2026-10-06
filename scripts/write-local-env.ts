/**
 * Writes .env.local for local development from `supabase status`, starting
 * from .env.example. Refuses to overwrite an existing .env.local unless
 * --force is passed.
 *
 *   npm run env:local
 */
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";

const target = ".env.local";
const force = process.argv.includes("--force");

if (existsSync(target) && !force) {
  console.error(`${target} already exists. Re-run with --force to overwrite it.`);
  process.exit(1);
}

let raw: string;
try {
  raw = execFileSync("npx", ["supabase", "status", "-o", "json"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
} catch {
  console.error("Could not read `supabase status`. Is the local stack running? (npm run db:start)");
  process.exit(1);
}

const status = JSON.parse(raw.slice(raw.indexOf("{"))) as Record<string, string | undefined>;
const values: Record<string, string | undefined> = {
  NEXT_PUBLIC_SUPABASE_URL: status.API_URL,
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: status.PUBLISHABLE_KEY,
  SUPABASE_SECRET_KEY: status.SECRET_KEY,
  S3_ENDPOINT: status.STORAGE_S3_URL,
  S3_REGION: status.S3_PROTOCOL_REGION,
  S3_ACCESS_KEY_ID: status.S3_PROTOCOL_ACCESS_KEY_ID,
  S3_SECRET_ACCESS_KEY: status.S3_PROTOCOL_ACCESS_KEY_SECRET,
  NEXT_PUBLIC_ASSET_BASE_URL: status.API_URL
    ? `${status.API_URL}/storage/v1/object/public/public`
    : undefined,
};

const output = readFileSync(".env.example", "utf8")
  .split("\n")
  .map((line) => {
    const key = line.split("=", 1)[0];
    const value = key ? values[key] : undefined;
    return value ? `${key}=${value}` : line;
  })
  .join("\n");

writeFileSync(target, output);
console.log(`Wrote ${target} with local Supabase and storage credentials.`);
