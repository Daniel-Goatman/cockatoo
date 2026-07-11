import { beforeEach, describe, expect, it, vi } from "vitest";
import { Matcher } from "../src/core/matcher";
import {
  PageTransformer,
  restoreAll,
  MAX_PAGE_TOKENS,
  MIN_PAGE_TOKENS,
  MUTATION_DEBOUNCE_MS,
} from "../src/core/transformer";
import { hausItem, undItem, makeSnapshot, patchInnerText, setBody } from "./helpers";
import type { SnapshotItem } from "../src/core/types";

patchInnerText();

function makeTransformer(onToken?: (el: HTMLElement, item: SnapshotItem) => void): PageTransformer {
  const matcher = new Matcher(makeSnapshot([hausItem(), undItem()]));
  return new PageTransformer(document, matcher, {
    onToken: (el, item) => onToken?.(el, item),
  });
}

function paragraph(words: number, embed = ""): string {
  const filler = Array.from({ length: words }, (_, i) => `word${i}`).join(" ");
  return `<p>${filler} ${embed}</p>`;
}

describe("PageTransformer", () => {
  beforeEach(() => {
    document.body.innerHTML = "";
  });

  it("replaces matched words inside blocks with marked tokens", () => {
    setBody(`<p>We bought the house and moved in, which was a nice moment for everyone involved here.</p>`);
    const transformer = makeTransformer();
    const placed = transformer.applyInitial();
    expect(placed).toBeGreaterThan(0);

    const token = document.querySelector<HTMLElement>("[data-cck-token]")!;
    expect(token).not.toBeNull();
    expect(token.dataset.cckOriginal).toBeTruthy();
    expect(token.getAttribute("tabindex")).toBe("0");
    expect(token.getAttribute("aria-label")).toContain("originally");
    // The page text was genuinely swapped.
    expect(document.body.textContent).toContain(token.textContent!);
  });

  it("renders the determiner-inclusive display with article", () => {
    setBody(`<p>Everyone said the house was far too expensive for the neighborhood we liked most.</p>`);
    makeTransformer().applyInitial();
    const token = document.querySelector<HTMLElement>("[data-cck-token]")!;
    expect(token.textContent).toBe("das Haus");
    expect(token.dataset.cckOriginal).toBe("the house");
  });

  it("stamps the fidelity tier for CSS marking", () => {
    setBody(`<p>Everyone said the house was far too expensive for the neighborhood we liked most.</p>`);
    makeTransformer().applyInitial();
    expect(document.querySelector<HTMLElement>("[data-cck-token]")!.dataset.cckTier).toBe("formMatched");
  });

  it("never touches excluded zones: code, forms with passwords, contenteditable, nav", () => {
    setBody(`
      <nav><p>house and home navigation menu with plenty of words to pass the minimum size</p></nav>
      <pre><code>the house = and(1)</code></pre>
      <div contenteditable="true"><p>typing about the house and more words to exceed all minimums easily today</p></div>
      <form id="checkout-billing"><p>the house and card number words words words words words words words</p>
        <input type="password" /></form>
      <p>A perfectly normal sentence about the house and the garden with enough words to qualify nicely.</p>
    `);
    makeTransformer().applyInitial();
    const tokens = [...document.querySelectorAll("[data-cck-token]")];
    expect(tokens.length).toBeGreaterThan(0);
    for (const token of tokens) {
      expect(token.closest("nav, pre, code, [contenteditable], form")).toBeNull();
    }
  });

  it("respects the page budget bounds (1 per 40 words, min 3, cap 20)", () => {
    // A page with ~50 candidate paragraphs each containing "and".
    setBody(Array.from({ length: 50 }, () => paragraph(38, "and then")).join(""));
    const transformer = makeTransformer();
    const placed = transformer.applyInitial();
    expect(placed).toBeLessThanOrEqual(MAX_PAGE_TOKENS);
    expect(placed).toBeGreaterThanOrEqual(MIN_PAGE_TOKENS);
  });

  it("places at most one token per item per block", () => {
    setBody(`<p>the house and the house and the house make three houses in a very long sentence here today</p>`);
    makeTransformer().applyInitial();
    const ids = [...document.querySelectorAll<HTMLElement>("[data-cck-token]")].map((t) => t.dataset.cckItem);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("skips tiny blocks", () => {
    setBody(`<p>the house</p>`);
    expect(makeTransformer().applyInitial()).toBe(0);
  });

  describe("incremental mutations (R4)", () => {
    it("processes added subtrees after a debounce without re-scanning", async () => {
      vi.useFakeTimers();
      setBody(paragraph(45, "and the house stood"));
      const transformer = makeTransformer();
      transformer.applyInitial();
      transformer.observe();
      const before = document.querySelectorAll("[data-cck-token]").length;

      const addition = document.createElement("div");
      addition.innerHTML = paragraph(60, "and the houses waited");
      document.body.append(addition);

      // MutationObserver microtask, then the 250ms trailing debounce.
      await Promise.resolve();
      vi.advanceTimersByTime(MUTATION_DEBOUNCE_MS + 10);

      const after = document.querySelectorAll("[data-cck-token]").length;
      expect(after).toBeGreaterThan(before);
      transformer.disconnect();
      vi.useRealTimers();
    });

    it("self-inflicted mutations never re-trigger processing", async () => {
      vi.useFakeTimers();
      setBody(paragraph(45, "and the house stood"));
      const transformer = makeTransformer();
      transformer.applyInitial();
      transformer.observe();
      const flushSpy = vi.spyOn(transformer, "flushPending");

      await Promise.resolve();
      vi.advanceTimersByTime(MUTATION_DEBOUNCE_MS * 4);
      // Token insertion happened before observe(); nothing external mutated,
      // so no flush may have been scheduled by our own DOM writes.
      expect(flushSpy).not.toHaveBeenCalled();
      transformer.disconnect();
      vi.useRealTimers();
    });

    it("infinite scroll stays under the absolute cap", async () => {
      vi.useFakeTimers();
      setBody(paragraph(50, "and the house"));
      const transformer = makeTransformer();
      transformer.applyInitial();
      transformer.observe();

      for (let i = 0; i < 40; i++) {
        const chunk = document.createElement("div");
        chunk.innerHTML = paragraph(50, "and the houses again");
        document.body.append(chunk);
        await Promise.resolve();
        vi.advanceTimersByTime(MUTATION_DEBOUNCE_MS + 10);
      }
      expect(document.querySelectorAll("[data-cck-token]").length).toBeLessThanOrEqual(MAX_PAGE_TOKENS);
      transformer.disconnect();
      vi.useRealTimers();
    });
  });

  it("restoreAll returns the page to its original text", () => {
    const original = "Everyone said the house was far too expensive for the neighborhood we liked most.";
    setBody(`<p>${original}</p>`);
    makeTransformer().applyInitial();
    expect(document.body.textContent).not.toContain("the house");
    restoreAll(document);
    expect(document.querySelectorAll("[data-cck-token]").length).toBe(0);
    expect(document.body.textContent).toContain(original);
  });
});
