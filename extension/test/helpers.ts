import type { Snapshot, SnapshotItem, SyncErrorResponse, Transport } from "../src/core/types";

export function makeItem(partial: Partial<SnapshotItem> & { id: string }): SnapshotItem {
  return {
    kind: "word",
    tier: "formMatched",
    forms: [],
    hover: { target: partial.id, pos: null, example: null, seenCount: 0 },
    ...partial,
  };
}

export function hausItem(): SnapshotItem {
  return makeItem({
    id: "de.word.haus",
    forms: [
      { match: "the house", display: "das Haus" },
      { match: "a house", display: "ein Haus" },
      { match: "house", display: "Haus" },
      { match: "houses", display: "Häuser" },
      { match: "the houses", display: "die Häuser" },
    ],
    hover: { target: "das Haus", pos: "noun", example: { source: "The house is old.", target: "Das Haus ist alt." }, seenCount: 3 },
  });
}

export function undItem(): SnapshotItem {
  return makeItem({
    id: "de.word.und",
    tier: "exact",
    forms: [{ match: "and", display: "und" }],
    hover: { target: "und", pos: "conjunction", example: null, seenCount: 0 },
  });
}

export function makeSnapshot(items: SnapshotItem[], overrides: Partial<Snapshot["settings"]> = {}): Snapshot {
  return {
    version: 1,
    language: "de",
    settings: { enabled: true, blockedHosts: [], pageContextOptIn: false, ...overrides },
    items,
  };
}

/** In-memory Transport with scripted responses per method. */
export class FakeTransport implements Transport {
  cache = new Map<string, unknown>();
  calls: { method: string; payload: unknown }[] = [];
  handlers = new Map<string, (payload: unknown) => unknown>();
  failWith: SyncErrorResponse | null = null;

  on(method: string, handler: (payload: unknown) => unknown): void {
    this.handlers.set(method, handler);
  }

  async call<T>(method: string, payload?: unknown): Promise<T | SyncErrorResponse> {
    this.calls.push({ method, payload });
    if (this.failWith) return this.failWith;
    const handler = this.handlers.get(method);
    if (!handler) return { error: "unknownMethod" };
    return handler(payload) as T;
  }

  async cacheGet<T>(key: string): Promise<T | undefined> {
    return this.cache.get(key) as T | undefined;
  }

  async cachePut(key: string, value: unknown): Promise<void> {
    this.cache.set(key, value);
  }
}

export function setBody(html: string): void {
  document.body.innerHTML = html;
}

/** jsdom has no innerText; back it with textContent for the transformer. */
export function patchInnerText(): void {
  if (!Object.getOwnPropertyDescriptor(HTMLElement.prototype, "innerText")) {
    Object.defineProperty(HTMLElement.prototype, "innerText", {
      get() {
        return this.textContent ?? "";
      },
      configurable: true,
    });
  }
}
