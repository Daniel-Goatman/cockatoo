import { Matcher } from "./matcher";
import type { SnapshotItem } from "./types";

// The DOM transformer. Carried-over rules from the prototype (budget math,
// block model, exclusions); new: incremental added-subtree processing with
// a trailing debounce and a persistent page budget (R4 fixes).

export const WORDS_PER_TOKEN = 40;
export const MIN_PAGE_TOKENS = 3;
export const MAX_PAGE_TOKENS = 20;
export const BLOCK_WORDS_PER_TOKEN = 25;
export const MIN_BLOCK_WORDS = 8;
export const MUTATION_DEBOUNCE_MS = 250;

export const BLOCK_SELECTOR = "p, li, blockquote, dd, figcaption, [role='listitem']";
export const EXCLUDED_SELECTOR = [
  "input", "textarea", "select", "button", "label", "option",
  "[contenteditable]", "[contenteditable] *",
  "code", "pre", "kbd", "samp", "var", "script", "style",
  "nav", "header", "footer", "aside",
  "[aria-hidden='true']",
  "[data-cck-token]", "[data-cck-token] *",
].join(", ");

const SENSITIVE_FORM_RE = /password|passwort|checkout|billing|payment|card|iban|ssn|social.?security/i;

export interface TokenCallbacks {
  onToken(el: HTMLElement, item: SnapshotItem, form: string): void;
}

export class PageTransformer {
  private matcher: Matcher;
  private doc: Document;
  private callbacks: TokenCallbacks;
  private budget = 0;
  private tokensPlaced = 0;
  private perItemInBlock = new WeakMap<Element, Set<string>>();
  private observer: MutationObserver | null = null;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private pendingRoots = new Set<Node>();

  constructor(doc: Document, matcher: Matcher, callbacks: TokenCallbacks) {
    this.doc = doc;
    this.matcher = matcher;
    this.callbacks = callbacks;
  }

  /** Initial pass over the whole document; budget derived from page size. */
  applyInitial(): number {
    const totalWords = approximateWordCount(this.doc.body);
    this.budget = clamp(Math.floor(totalWords / WORDS_PER_TOKEN), MIN_PAGE_TOKENS, MAX_PAGE_TOKENS);
    this.processRoot(this.doc.body);
    return this.tokensPlaced;
  }

  /** Incremental: added subtrees only, debounced. NEVER re-scans the page. */
  observe(): void {
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (this.isManaged(node)) continue;
          this.pendingRoots.add(node);
        }
      }
      if (this.pendingRoots.size > 0) this.scheduleFlush();
    });
    this.observer.observe(this.doc.body, { childList: true, subtree: true });
  }

  disconnect(): void {
    this.observer?.disconnect();
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
  }

  private scheduleFlush(): void {
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => this.flushPending(), MUTATION_DEBOUNCE_MS);
  }

  /** Exposed for tests (fake timers). */
  flushPending(): void {
    const roots = [...this.pendingRoots];
    this.pendingRoots.clear();
    for (const root of roots) {
      if (!root.isConnected) continue;
      // Infinite scroll grows the budget by the added text, same 1/40 ratio,
      // still under the absolute page cap.
      const addedWords = root instanceof Element || root instanceof Document
        ? approximateWordCount(root as Element)
        : 0;
      this.budget = Math.min(
        MAX_PAGE_TOKENS,
        this.budget + Math.floor(addedWords / WORDS_PER_TOKEN),
      );
      if (root instanceof Element) this.processRoot(root);
    }
  }

  private get remaining(): number {
    return this.budget - this.tokensPlaced;
  }

  private processRoot(root: Element): void {
    if (this.matcher.isEmpty || this.remaining <= 0) return;

    const blocks: Element[] = [];
    if (root.matches?.(BLOCK_SELECTOR)) blocks.push(root);
    blocks.push(...root.querySelectorAll(BLOCK_SELECTOR));

    const candidates = blocks.filter((b) => !this.isExcluded(b) && approximateWordCount(b) >= MIN_BLOCK_WORDS);
    if (candidates.length === 0) return;

    // Even distribution: round-robin one token per block, spaced subset.
    const spaced = evenlySpacedSubset(candidates, Math.min(candidates.length, this.remaining));
    for (const block of spaced) {
      if (this.remaining <= 0) break;
      this.fillBlock(block);
    }
  }

  private fillBlock(block: Element): void {
    const blockBudget = Math.max(1, Math.floor(approximateWordCount(block) / BLOCK_WORDS_PER_TOKEN));
    const used = this.perItemInBlock.get(block) ?? new Set<string>();
    this.perItemInBlock.set(block, used);
    let placed = 0;

    // Re-walk after each insertion: splitting a text node invalidates the walker.
    while (placed < blockBudget && this.remaining > 0) {
      if (!this.insertOneToken(block, used)) break;
      placed += 1;
    }
  }

  private insertOneToken(block: Element, usedItemIds: Set<string>): boolean {
    const walker = this.doc.createTreeWalker(block, NodeFilter.SHOW_TEXT);
    let node: Node | null;
    while ((node = walker.nextNode())) {
      const text = node.textContent ?? "";
      if (text.trim().length < 3) continue;
      const parent = node.parentElement;
      if (!parent || this.isExcluded(parent)) continue;

      for (const match of this.matcher.matches(text)) {
        if (usedItemIds.has(match.item.id)) continue; // one instance per item per block
        this.replaceRange(node as Text, match.start, match.end, match.item, match.form, match.display);
        usedItemIds.add(match.item.id);
        this.tokensPlaced += 1;
        return true;
      }
    }
    return false;
  }

  private replaceRange(
    textNode: Text,
    start: number,
    end: number,
    item: SnapshotItem,
    form: string,
    display: string,
  ): void {
    const original = textNode.textContent ?? "";
    const token = this.doc.createElement("span");
    token.className = "cck-token";
    token.dataset.cckToken = "1";
    token.dataset.cckItem = item.id;
    token.dataset.cckForm = form;
    token.dataset.cckOriginal = original.slice(start, end);
    token.dataset.cckTier = item.tier; // approximate → dotted marker via CSS
    token.setAttribute("tabindex", "0");
    token.setAttribute("role", "button");
    token.setAttribute("aria-label", `Cockatoo vocabulary: ${display}, originally ${original.slice(start, end)}`);
    token.textContent = display;

    const fragment = this.doc.createDocumentFragment();
    if (start > 0) fragment.append(this.doc.createTextNode(original.slice(0, start)));
    fragment.append(token);
    if (end < original.length) fragment.append(this.doc.createTextNode(original.slice(end)));
    textNode.replaceWith(fragment);
    this.callbacks.onToken(token, item, form);
  }

  isExcluded(el: Element): boolean {
    if (el.closest(EXCLUDED_SELECTOR.replaceAll(", [contenteditable] *", "").replaceAll(", [data-cck-token] *", ""))) {
      return true;
    }
    const form = el.closest("form");
    if (form) {
      const attrs = `${form.id} ${form.className} ${form.getAttribute("action") ?? ""} ${form.getAttribute("name") ?? ""}`;
      if (SENSITIVE_FORM_RE.test(attrs)) return true;
      if (form.querySelector("input[type='password']")) return true;
    }
    return !isVisible(el);
  }

  private isManaged(node: Node): boolean {
    if (!(node instanceof Element)) return node.parentElement?.closest("[data-cck-token]") != null;
    return node.matches?.("[data-cck-token], [data-cck-token] *, .cck-hovercard, .cck-hovercard *") ?? false;
  }
}

/** Restore every token to its original text (disable / host block). */
export function restoreAll(doc: Document): void {
  for (const token of doc.querySelectorAll<HTMLElement>("[data-cck-token]")) {
    token.replaceWith(doc.createTextNode(token.dataset.cckOriginal ?? token.textContent ?? ""));
  }
}

export function approximateWordCount(el: Element): number {
  const text = (el as HTMLElement).innerText ?? el.textContent ?? "";
  return text.split(/\s+/).filter(Boolean).length;
}

/** Fixed prototype hole: zero-rect / opacity:0 elements are not visible. */
export function isVisible(el: Element): boolean {
  const html = el as HTMLElement;
  if (html.hidden) return false;
  const view = el.ownerDocument.defaultView;
  if (view) {
    const style = view.getComputedStyle(html);
    if (style.display === "none" || style.visibility === "hidden") return false;
    if (style.opacity !== "" && Number(style.opacity) === 0) return false;
  }
  // jsdom has no layout: only enforce rect checks when a real layout exists.
  if (typeof html.getClientRects === "function") {
    const rects = html.getClientRects();
    if (view && "innerWidth" in view && rects.length === 0 && html.offsetParent === null && isRealLayout(view)) {
      return false;
    }
  }
  return true;
}

function isRealLayout(view: Window & typeof globalThis): boolean {
  return !(view.navigator?.userAgent ?? "").includes("jsdom");
}

export function evenlySpacedSubset<T>(items: T[], count: number): T[] {
  if (count >= items.length) return [...items];
  if (count <= 0) return [];
  const result: T[] = [];
  const step = items.length / count;
  for (let i = 0; i < count; i++) {
    result.push(items[Math.floor(i * step)]);
  }
  return result;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}
