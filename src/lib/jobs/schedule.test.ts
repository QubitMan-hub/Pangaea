import { readFileSync } from "node:fs";

import { parse } from "jsonc-parser";
import { describe, expect, it } from "vitest";

import { CRON_JOBS, IMPLEMENTED_JOBS, isJobName, jobsForCron, secretsMatch } from "./schedule";

function wranglerCrons(): string[] {
  const raw = readFileSync(new URL("../../../wrangler.jsonc", import.meta.url), "utf8");
  const config = parse(raw) as { triggers?: { crons?: string[] } };
  return config.triggers?.crons ?? [];
}

describe("cron schedule", () => {
  it("registers only planned crons that have an implemented job", () => {
    for (const cron of wranglerCrons()) {
      expect(Object.keys(CRON_JOBS)).toContain(cron);
      expect(jobsForCron(cron).length).toBeGreaterThan(0);
    }
  });

  it("registers every cron that has an implemented job", () => {
    const needed = Object.keys(CRON_JOBS).filter((cron) => jobsForCron(cron).length > 0);
    expect(wranglerCrons().sort()).toEqual(needed.sort());
  });

  it("stays within the free plan's 5 cron triggers", () => {
    expect(Object.keys(CRON_JOBS).length).toBeLessThanOrEqual(5);
  });

  it("returns only implemented jobs, in planned order", () => {
    for (const [cron, planned] of Object.entries(CRON_JOBS)) {
      expect(jobsForCron(cron)).toEqual(planned.filter((job) => IMPLEMENTED_JOBS.has(job)));
    }
    expect(jobsForCron("not a cron")).toEqual([]);
    expect(jobsForCron("constructor")).toEqual([]);
  });

  it("recognizes only known job names", () => {
    expect(isJobName("moderation-queue")).toBe(true);
    expect(isJobName("../secrets")).toBe(false);
  });
});

describe("secretsMatch", () => {
  it("accepts only the exact secret", () => {
    expect(secretsMatch("s3cret-value", "s3cret-value")).toBe(true);
    expect(secretsMatch("s3cret-valuX", "s3cret-value")).toBe(false);
    expect(secretsMatch("short", "s3cret-value")).toBe(false);
  });

  it("refuses when either side is missing", () => {
    expect(secretsMatch(null, "s3cret-value")).toBe(false);
    expect(secretsMatch("anything", undefined)).toBe(false);
    expect(secretsMatch("", "")).toBe(false);
  });
});
