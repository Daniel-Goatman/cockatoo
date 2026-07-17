import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

describe("shipped branding", () => {
  it("uses the canonical Cockatoo vector in the popup", () => {
    const html = readFileSync(join(__dirname, "..", "popup.html"), "utf8");
    const document = new DOMParser().parseFromString(html, "text/html");
    const mark = document.querySelector(".brand-mark");

    expect(mark?.getAttribute("viewBox")).toBe("0 0 100 100");
    expect(mark?.querySelectorAll("path")).toHaveLength(6);
    expect(mark?.querySelectorAll("circle")).toHaveLength(1);
    expect(document.querySelector(".crest")).toBeNull();
  });
});
