import { readdirSync, readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

const dir = new URL("../../messages/", import.meta.url);

function keys(value: unknown, prefix = ""): string[] {
  if (value === null || typeof value !== "object") return [prefix];
  return Object.entries(value).flatMap(([k, v]) => keys(v, prefix ? `${prefix}.${k}` : k));
}

describe("message catalogs", () => {
  const files = readdirSync(dir).filter((f) => f.endsWith(".json"));
  const english = keys(JSON.parse(readFileSync(new URL("en.json", dir), "utf8")));

  it("has an English catalog", () => {
    expect(files).toContain("en.json");
    expect(english.length).toBeGreaterThan(0);
  });

  it.each(files)("%s has exactly the same keys as en.json", (file) => {
    const other = keys(JSON.parse(readFileSync(new URL(file, dir), "utf8")));
    expect(other.sort()).toEqual([...english].sort());
  });

  it("has no empty strings in English", () => {
    const flat = JSON.stringify(JSON.parse(readFileSync(new URL("en.json", dir), "utf8")));
    expect(flat).not.toContain('""');
  });
});
