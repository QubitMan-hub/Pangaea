import { describe, expect, it } from "vitest";

import { parseEnv, publicEnvSchema, serverEnvSchema } from "./schema";

const base = {
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
  SUPABASE_SECRET_KEY: "sb_secret_test",
};

describe("serverEnvSchema", () => {
  it("applies the documented defaults", () => {
    const env = parseEnv(serverEnvSchema, base);
    expect(env.ANTHROPIC_MODEL).toBe("claude-haiku-4-5");
    expect(env.VOYAGE_MODEL).toBe("voyage-4");
    expect(env.EARNED_SPACE_HALF_LIFE_DAYS).toBe(30);
    expect(env.S3_REGION).toBe("auto");
    expect(env.S3_PUBLIC_BUCKET).toBe("public");
  });

  it("treats an empty S3 endpoint as unset", () => {
    const env = parseEnv(serverEnvSchema, { ...base, S3_ENDPOINT: "" });
    expect(env.S3_ENDPOINT).toBeUndefined();
  });

  it("lets ANTHROPIC_MODEL be overridden", () => {
    const env = parseEnv(serverEnvSchema, { ...base, ANTHROPIC_MODEL: "claude-sonnet-5-5" });
    expect(env.ANTHROPIC_MODEL).toBe("claude-sonnet-5-5");
  });

  it("treats empty optional secrets as unset", () => {
    const env = parseEnv(serverEnvSchema, { ...base, ANTHROPIC_API_KEY: "" });
    expect(env.ANTHROPIC_API_KEY).toBeUndefined();
  });

  it("parses a configurable half-life", () => {
    const env = parseEnv(serverEnvSchema, { ...base, EARNED_SPACE_HALF_LIFE_DAYS: "14" });
    expect(env.EARNED_SPACE_HALF_LIFE_DAYS).toBe(14);
  });

  it("rejects a non-positive half-life", () => {
    expect(() => parseEnv(serverEnvSchema, { ...base, EARNED_SPACE_HALF_LIFE_DAYS: "0" })).toThrow(
      /EARNED_SPACE_HALF_LIFE_DAYS/,
    );
  });

  it("requires the Supabase secret key", () => {
    const { SUPABASE_SECRET_KEY: _omitted, ...rest } = base;
    expect(() => parseEnv(serverEnvSchema, rest)).toThrow(/SUPABASE_SECRET_KEY/);
  });

  it("never echoes secret values in errors", () => {
    try {
      parseEnv(serverEnvSchema, { ...base, NEXT_PUBLIC_SUPABASE_URL: "not a url" });
      expect.unreachable();
    } catch (error) {
      expect(String(error)).not.toContain("sb_secret_test");
    }
  });
});

describe("publicEnvSchema", () => {
  it("rejects an invalid Supabase URL", () => {
    expect(() =>
      parseEnv(publicEnvSchema, { ...base, NEXT_PUBLIC_SUPABASE_URL: "localhost" }),
    ).toThrow(/NEXT_PUBLIC_SUPABASE_URL/);
  });
});
