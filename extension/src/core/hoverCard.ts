import type { SnapshotItem } from "./types";

// Floating hover card: open on hover/focus, 90ms grace on out, click pins,
// Escape closes, repositions on scroll/resize. The card ALWAYS shows the
// original English (fidelity transparency requirement 2). Buttons appear
// only if functional (P4): v1 ships exactly one — "Open in Cockatoo".

export const CLOSE_DELAY_MS = 90;

export interface HoverCardDelegate {
  openDashboard(itemId: string): void;
}

export class HoverCard {
  private doc: Document;
  private delegate: HoverCardDelegate;
  private card: HTMLElement | null = null;
  private anchor: HTMLElement | null = null;
  private pinned = false;
  private closeTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(doc: Document, delegate: HoverCardDelegate) {
    this.doc = doc;
    this.delegate = delegate;
    doc.addEventListener("keydown", (e) => {
      if (e.key === "Escape") this.close(true);
    });
    doc.defaultView?.addEventListener("scroll", () => this.reposition(), { passive: true });
    doc.defaultView?.addEventListener("resize", () => this.reposition());
  }

  attach(token: HTMLElement, item: SnapshotItem): void {
    token.addEventListener("mouseenter", () => this.open(token, item, false));
    token.addEventListener("focusin", () => this.open(token, item, false));
    token.addEventListener("mouseleave", () => this.scheduleClose());
    token.addEventListener("focusout", () => this.scheduleClose());
    token.addEventListener("click", (e) => {
      e.preventDefault();
      this.open(token, item, true);
    });
    token.addEventListener("keydown", (e) => {
      if ((e as KeyboardEvent).key === "Enter") this.open(token, item, true);
    });
  }

  open(token: HTMLElement, item: SnapshotItem, pin: boolean): void {
    this.cancelClose();
    if (this.card && this.anchor !== token) this.close(true);
    this.pinned = this.pinned || pin;
    this.anchor = token;
    token.classList.add("is-active");

    if (!this.card) {
      this.card = this.build(token, item);
      this.doc.body.append(this.card);
    }
    this.reposition();
  }

  private build(token: HTMLElement, item: SnapshotItem): HTMLElement {
    const card = this.doc.createElement("div");
    card.className = "cck-hovercard";
    card.setAttribute("role", "dialog");
    card.setAttribute("aria-label", `Cockatoo: ${item.hover.target}`);
    card.addEventListener("mouseenter", () => this.cancelClose());
    card.addEventListener("mouseleave", () => this.scheduleClose());

    const target = this.doc.createElement("div");
    target.className = "cck-hovercard-target";
    target.textContent = item.hover.target;
    card.append(target);

    // The ground truth is one hover away, on every token, forever.
    const original = this.doc.createElement("div");
    original.className = "cck-hovercard-original";
    original.textContent = `English: ${token.dataset.cckOriginal ?? ""}`;
    card.append(original);

    if (item.hover.pos) {
      const pos = this.doc.createElement("div");
      pos.className = "cck-hovercard-pos";
      pos.textContent = item.hover.pos;
      card.append(pos);
    }

    if (item.hover.example) {
      const example = this.doc.createElement("div");
      example.className = "cck-hovercard-example";
      example.textContent = `${item.hover.example.target} — ${item.hover.example.source}`;
      card.append(example);
    }

    const seen = this.doc.createElement("div");
    seen.className = "cck-hovercard-seen";
    seen.textContent = `Seen ${item.hover.seenCount} times`;
    card.append(seen);

    const openButton = this.doc.createElement("button");
    openButton.className = "cck-hovercard-open";
    openButton.textContent = "Open in Cockatoo";
    openButton.addEventListener("click", () => this.delegate.openDashboard(item.id));
    card.append(openButton);

    return card;
  }

  private reposition(): void {
    if (!this.card || !this.anchor) return;
    const rect = this.anchor.getBoundingClientRect();
    const view = this.doc.defaultView;
    if (!view) return;
    const cardHeight = this.card.offsetHeight || 120;
    const cardWidth = this.card.offsetWidth || 260;

    // Below the token; flip above when it would leave the viewport.
    let top = rect.bottom + 8;
    if (top + cardHeight > view.innerHeight && rect.top - cardHeight - 8 > 0) {
      top = rect.top - cardHeight - 8;
    }
    const left = Math.max(8, Math.min(rect.left, view.innerWidth - cardWidth - 8));
    this.card.style.top = `${top + view.scrollY}px`;
    this.card.style.left = `${left + view.scrollX}px`;
  }

  private scheduleClose(): void {
    if (this.pinned) return;
    this.cancelClose();
    this.closeTimer = setTimeout(() => this.close(false), CLOSE_DELAY_MS);
  }

  private cancelClose(): void {
    if (this.closeTimer) {
      clearTimeout(this.closeTimer);
      this.closeTimer = null;
    }
  }

  close(force: boolean): void {
    if (this.pinned && !force) return;
    this.card?.remove();
    this.card = null;
    this.anchor?.classList.remove("is-active");
    this.anchor = null;
    this.pinned = false;
  }

  get isOpen(): boolean {
    return this.card !== null;
  }
}
