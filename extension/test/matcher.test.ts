import { describe, expect, it } from "vitest";
import { Matcher, applyCapitalization } from "../src/core/matcher";
import { hausItem, undItem, makeSnapshot } from "./helpers";

describe("Matcher", () => {
  const matcher = new Matcher(makeSnapshot([hausItem(), undItem()]));

  it("matches bare forms with word boundaries", () => {
    const matches = matcher.matches("A greenhouse and house near the road");
    // "greenhouse" must NOT match; "and" and "house" must.
    expect(matches.map((m) => m.form)).toEqual(["and", "house"]);
  });

  it("prefers determiner-extended forms via longest match (D10)", () => {
    const matches = matcher.matches("We saw the house yesterday");
    expect(matches).toHaveLength(1);
    expect(matches[0].form).toBe("the house");
    expect(matches[0].display).toBe("das Haus");
  });

  it("matches plural determiner forms", () => {
    const matches = matcher.matches("All the houses were dark");
    expect(matches[0].form).toBe("the houses");
    expect(matches[0].display).toBe("die Häuser");
  });

  it("preserves sentence-start capitalization", () => {
    const matches = matcher.matches("The house is old");
    expect(matches[0].display).toBe("Das Haus");
    expect(applyCapitalization("And", "und")).toBe("Und");
    expect(applyCapitalization("and", "und")).toBe("und");
  });

  it("returns non-overlapping matches left to right", () => {
    const matches = matcher.matches("the house and the houses and a house");
    expect(matches.map((m) => m.form)).toEqual(["the house", "and", "the houses", "and", "a house"]);
  });

  it("is case-insensitive on the match side", () => {
    const matches = matcher.matches("THE HOUSE was loud");
    expect(matches[0].form).toBe("the house");
    expect(matches[0].display).toBe("Das Haus");
  });
});
