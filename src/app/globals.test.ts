import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

const css = readFileSync(new URL("./globals.css", import.meta.url), "utf8").replace(
  /\/\*[\s\S]*?\*\//g,
  "",
);

/** Returns the `--name: value` declarations inside the first block after `selector`. */
function tokens(selector: string): string[] {
  const start = css.indexOf(selector);
  if (start < 0) throw new Error(`selector not found: ${selector}`);
  const open = css.indexOf("{", start);
  const close = css.indexOf("}", open);
  return css
    .slice(open + 1, close)
    .split(";")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("--") || line.startsWith("color-scheme"));
}

describe("theme tokens", () => {
  it("defines the dark theme identically for system dark and the dark toggle", () => {
    // The two blocks must stay in sync (one is under prefers-color-scheme).
    expect(tokens(':root:not([data-theme="light"])')).toEqual(tokens(':root[data-theme="dark"]'));
  });

  it("gives every light token a dark value", () => {
    const name = (decl: string) => decl.split(":")[0];
    const light = tokens(":root {").map(name);
    const dark = tokens(':root[data-theme="dark"]').map(name);
    expect(dark.sort()).toEqual(light.sort());
  });
});
