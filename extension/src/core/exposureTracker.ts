import type { ExposureEvent, ExposureEventType, SnapshotItem } from "./types";

// seen = ≥50% visible for ≥1s continuous dwell, once per token per page.
// engaged = hover/focus ≥400ms, once per token per page. pinned = click-pin.
// sentenceCaptured piggybacks on engaged (locally extracted, original
// English restored in place of the token).

export const SEEN_DWELL_MS = 1000;
export const ENGAGE_DWELL_MS = 400;

export interface TrackerDelegate {
  emit(event: ExposureEvent): void;
  host: string;
  now(): number; // epoch ms — injectable for tests
  uuid(): string;
}

export class ExposureTracker {
  private delegate: TrackerDelegate;
  private io: IntersectionObserver | null = null;
  private dwellTimers = new Map<Element, ReturnType<typeof setTimeout>>();
  private seenTokens = new WeakSet<Element>();
  private engagedTokens = new WeakSet<Element>();

  constructor(delegate: TrackerDelegate) {
    this.delegate = delegate;
    if (typeof IntersectionObserver !== "undefined") {
      this.io = new IntersectionObserver((entries) => this.onIntersections(entries), { threshold: 0.5 });
    }
  }

  track(token: HTMLElement, item: SnapshotItem, form: string): void {
    this.io?.observe(token);
    token.addEventListener("mouseenter", () => this.startEngageTimer(token, item));
    token.addEventListener("focusin", () => this.startEngageTimer(token, item));
    token.addEventListener("mouseleave", () => this.cancelEngageTimer(token));
    token.addEventListener("focusout", () => this.cancelEngageTimer(token));
    token.addEventListener("click", (e) => {
      e.preventDefault();
      this.emitOnce(token, item, "pinned", this.engagedTokens);
      this.captureSentence(token, item);
    });
  }

  private onIntersections(entries: IntersectionObserverEntry[]): void {
    for (const entry of entries) {
      const token = entry.target as HTMLElement;
      if (entry.isIntersecting) {
        if (this.seenTokens.has(token) || this.dwellTimers.has(token)) continue;
        this.dwellTimers.set(
          token,
          setTimeout(() => {
            this.dwellTimers.delete(token);
            const itemId = token.dataset.cckItem;
            if (itemId) this.emitRaw(token, itemId, "seen", this.seenTokens);
            this.io?.unobserve(token);
          }, SEEN_DWELL_MS),
        );
      } else {
        this.cancelDwell(token);
      }
    }
  }

  private cancelDwell(token: Element): void {
    const timer = this.dwellTimers.get(token);
    if (timer) {
      clearTimeout(timer);
      this.dwellTimers.delete(token);
    }
  }

  private engageTimers = new Map<Element, ReturnType<typeof setTimeout>>();

  private startEngageTimer(token: HTMLElement, item: SnapshotItem): void {
    if (this.engagedTokens.has(token) || this.engageTimers.has(token)) return;
    this.engageTimers.set(
      token,
      setTimeout(() => {
        this.engageTimers.delete(token);
        this.emitOnce(token, item, "engaged", this.engagedTokens);
        this.captureSentence(token, item);
      }, ENGAGE_DWELL_MS),
    );
  }

  private cancelEngageTimer(token: Element): void {
    const timer = this.engageTimers.get(token);
    if (timer) {
      clearTimeout(timer);
      this.engageTimers.delete(token);
    }
  }

  private emitOnce(token: HTMLElement, item: SnapshotItem, type: ExposureEventType, dedupe: WeakSet<Element>): void {
    this.emitRaw(token, item.id, type, dedupe);
  }

  private emitRaw(token: HTMLElement, itemId: string, type: ExposureEventType, dedupe: WeakSet<Element>): void {
    if (dedupe.has(token)) return;
    dedupe.add(token);
    this.delegate.emit({
      id: this.delegate.uuid(),
      itemId,
      type,
      occurredAt: new Date(this.delegate.now()).toISOString(),
      host: this.delegate.host,
    });
  }

  private capturedTokens = new WeakSet<Element>();

  private captureSentence(token: HTMLElement, item: SnapshotItem): void {
    if (this.capturedTokens.has(token)) return;
    const sentence = extractSentence(token);
    if (!sentence) return;
    this.capturedTokens.add(token);
    this.delegate.emit({
      id: this.delegate.uuid(),
      itemId: item.id,
      type: "sentenceCaptured",
      occurredAt: new Date(this.delegate.now()).toISOString(),
      host: this.delegate.host,
      sentence,
    });
  }
}

/** Sentence around the token from the block's normalized text, with the
 * ORIGINAL English restored in place (fixes the prototype's node-concat
 * mangling). Returns null when the result is too short/long to be useful. */
export function extractSentence(token: HTMLElement): string | null {
  const block = token.closest("p, li, blockquote, dd, figcaption") ?? token.parentElement;
  if (!block) return null;

  // Clone the block, swap the token back to its original text, normalize.
  const clone = block.cloneNode(true) as HTMLElement;
  for (const t of clone.querySelectorAll<HTMLElement>("[data-cck-token]")) {
    t.replaceWith(clone.ownerDocument.createTextNode(t.dataset.cckOriginal ?? ""));
  }
  const text = (clone.textContent ?? "").replace(/\s+/g, " ").trim();
  const original = token.dataset.cckOriginal ?? "";
  if (!original) return null;

  const index = text.toLowerCase().indexOf(original.toLowerCase());
  if (index < 0) return null;

  // Sentence boundaries around the occurrence.
  const enders = /[.!?…]/;
  let start = 0;
  for (let i = index; i > 0; i--) {
    if (enders.test(text[i - 1])) {
      start = i;
      break;
    }
  }
  let end = text.length;
  for (let i = index + original.length; i < text.length; i++) {
    if (enders.test(text[i])) {
      end = i + 1;
      break;
    }
  }
  const sentence = text.slice(start, end).trim();
  return sentence.length >= 20 && sentence.length <= 300 ? sentence : null;
}
