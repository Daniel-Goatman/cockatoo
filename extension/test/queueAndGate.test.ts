import { describe, expect, it } from "vitest";
import { EventQueue } from "../src/core/eventQueue";
import { SnapshotStore } from "../src/core/snapshotStore";
import { shouldRunOnPage, coarseHost } from "../src/core/pageGate";
import { extractSentence } from "../src/core/exposureTracker";
import { FakeTransport, hausItem, makeSnapshot, setBody } from "./helpers";
import type { ExposureEvent } from "../src/core/types";

function event(id: string): ExposureEvent {
  return { id, itemId: "de.word.haus", type: "seen", occurredAt: "2026-07-11T10:00:00Z" };
}

describe("EventQueue (at-least-once, ack-then-clear)", () => {
  function makeQueue(transport: FakeTransport) {
    const seen: number[] = [];
    let unavailable = 0;
    const queue = new EventQueue(transport, {
      onLatestVersion: (v) => seen.push(v),
      onAppUnavailable: () => unavailable++,
    });
    return { queue, seen, unavailableCount: () => unavailable };
  }

  it("acknowledged flush clears exactly what was sent and reports the version", async () => {
    const transport = new FakeTransport();
    transport.on("postEvents", () => ({ accepted: 2, latestVersion: 42 }));
    const { queue, seen } = makeQueue(transport);

    await queue.enqueue([event("a"), event("b")]);
    expect(await queue.flush()).toBe(true);
    expect(await queue.pending()).toBe(0);
    expect(seen).toEqual([42]);
  });

  it("keeps the queue on appUnavailable — progress delayed, never lost", async () => {
    const transport = new FakeTransport();
    transport.failWith = { error: "appUnavailable" };
    const { queue, unavailableCount } = makeQueue(transport);

    await queue.enqueue([event("a")]);
    expect(await queue.flush()).toBe(false);
    expect(await queue.pending()).toBe(1);
    expect(unavailableCount()).toBeGreaterThan(0);

    // App comes back → the same events drain.
    transport.failWith = null;
    transport.on("postEvents", (payload) => {
      const events = (payload as { events: ExposureEvent[] }).events;
      expect(events.map((e) => e.id)).toEqual(["a"]);
      return { accepted: 1, latestVersion: 7 };
    });
    expect(await queue.flush()).toBe(true);
    expect(await queue.pending()).toBe(0);
  });

  it("auto-flushes at the batch threshold", async () => {
    const transport = new FakeTransport();
    transport.on("postEvents", () => ({ accepted: 20, latestVersion: 1 }));
    const { queue } = makeQueue(transport);
    await queue.enqueue(Array.from({ length: 20 }, (_, i) => event(`e${i}`)));
    expect(transport.calls.filter((c) => c.method === "postEvents")).toHaveLength(1);
    expect(await queue.pending()).toBe(0);
  });

  it("events enqueued during a flush survive the clear", async () => {
    const transport = new FakeTransport();
    const { queue } = makeQueue(transport);
    await queue.enqueue([event("a")]);
    transport.on("postEvents", () => {
      // Simulate a concurrent enqueue landing while awaiting the ack.
      const current = (transport.cache.get("eventQueue") as ExposureEvent[]) ?? [];
      transport.cache.set("eventQueue", [...current, event("late")]);
      return { accepted: 1, latestVersion: 1 };
    });
    await queue.flush();
    const remaining = (transport.cache.get("eventQueue") as ExposureEvent[]).map((e) => e.id);
    expect(remaining).toEqual(["late"]);
  });
});

describe("SnapshotStore (pull-with-piggyback)", () => {
  it("skips the fetch when the cache already covers the reported version", async () => {
    const transport = new FakeTransport();
    transport.cache.set("snapshot", makeSnapshot([hausItem()]));
    const store = new SnapshotStore(transport);
    await store.refreshIfStale(1);
    expect(transport.calls).toHaveLength(0);
  });

  it("fetches when a newer version is reported and caches it", async () => {
    const transport = new FakeTransport();
    transport.cache.set("snapshot", makeSnapshot([hausItem()]));
    const fresh = { ...makeSnapshot([hausItem()]), version: 5 };
    transport.on("getSnapshot", () => ({ version: 5, snapshot: fresh }));
    const store = new SnapshotStore(transport);
    const result = await store.refreshIfStale(5);
    expect(result?.version).toBe(5);
    expect((transport.cache.get("snapshot") as { version: number }).version).toBe(5);
  });

  it("keeps serving the cache when the app is down", async () => {
    const transport = new FakeTransport();
    transport.cache.set("snapshot", makeSnapshot([hausItem()]));
    transport.failWith = { error: "appUnavailable" };
    const store = new SnapshotStore(transport);
    const result = await store.refreshIfStale(99);
    expect(result?.version).toBe(1);
  });
});

describe("pageGate", () => {
  const base = { protocol: "https:", host: "example.org", enabled: true, blockedHosts: [], ambientItemCount: 5 };

  it("runs on ordinary pages", () => {
    expect(shouldRunOnPage(base)).toBe(true);
  });

  it("refuses non-http, disabled, empty-vocab, sensitive and blocked hosts", () => {
    expect(shouldRunOnPage({ ...base, protocol: "file:" })).toBe(false);
    expect(shouldRunOnPage({ ...base, enabled: false })).toBe(false);
    expect(shouldRunOnPage({ ...base, ambientItemCount: 0 })).toBe(false);
    expect(shouldRunOnPage({ ...base, host: "www.mybank.com" })).toBe(false);
    expect(shouldRunOnPage({ ...base, host: "accounts.google.com" })).toBe(false);
    expect(shouldRunOnPage({ ...base, blockedHosts: ["example.org"] })).toBe(false);
    expect(shouldRunOnPage({ ...base, host: "sub.example.org", blockedHosts: ["example.org"] })).toBe(false);
  });

  it("coarsens hosts to eTLD+1-ish for event tagging", () => {
    expect(coarseHost("news.site.example.com")).toBe("example.com");
    expect(coarseHost("example.com")).toBe("example.com");
  });
});

describe("extractSentence", () => {
  it("restores the original English and cuts at sentence boundaries", () => {
    setBody(`<p>Something first. We walked past <span data-cck-token="1" data-cck-original="the houses">die Häuser</span> at dusk. Then home.</p>`);
    const token = document.querySelector<HTMLElement>("[data-cck-token]")!;
    expect(extractSentence(token)).toBe("We walked past the houses at dusk.");
  });

  it("returns null for unusably short fragments", () => {
    setBody(`<p>See <span data-cck-token="1" data-cck-original="the house">das Haus</span>.</p>`);
    const token = document.querySelector<HTMLElement>("[data-cck-token]")!;
    expect(extractSentence(token)).toBeNull();
  });
});
