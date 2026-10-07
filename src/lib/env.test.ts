import { describe, expect, it } from "vitest";

import { parseEnv, serverEnvSchema } from "./env";

const valid = {
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  SUPABASE_SECRET_KEY: "sb_secret_test",
};

describe("environment validation", () => {
  it("accepts a complete configuration", () => {
    expect(parseEnv(serverEnvSchema, valid).SUPABASE_SECRET_KEY).toBe("sb_secret_test");
  });

  it("names the missing secret", () => {
    const { SUPABASE_SECRET_KEY: _omitted, ...rest } = valid;
    expect(() => parseEnv(serverEnvSchema, rest)).toThrow(/SUPABASE_SECRET_KEY/);
  });

  it("never echoes values in errors", () => {
    const bad = { ...valid, NEXT_PUBLIC_SUPABASE_URL: "not-a-url-secret-ish" };
    expect(() => parseEnv(serverEnvSchema, bad)).toThrow(/NEXT_PUBLIC_SUPABASE_URL/);
    expect(() => parseEnv(serverEnvSchema, bad)).not.toThrow(/not-a-url-secret-ish/);
  });
});
