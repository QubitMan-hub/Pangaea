import "server-only";

import { parseEnv, serverEnvSchema, type ServerEnv } from "./schema";

let cached: ServerEnv | undefined;

/** Server-only env vars, validated on first use. */
export function serverEnv(): ServerEnv {
  cached ??= parseEnv(serverEnvSchema, process.env);
  return cached;
}
