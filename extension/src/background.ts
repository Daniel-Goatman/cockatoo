import { EventQueue, FLUSH_INTERVAL_MS } from "./core/eventQueue";
import { SnapshotStore } from "./core/snapshotStore";
import type { ExposureEvent } from "./core/types";
import { SafariTransport } from "./adapters/safari/transport";

// Background script: owns the snapshot cache and the event queue. Content
// scripts talk ONLY to the background; the background talks ONLY through
// the transport.

declare const browser: {
  runtime: {
    onMessage: {
      addListener(
        listener: (message: unknown, sender: unknown, sendResponse: (response: unknown) => void) => boolean | void,
      ): void;
    };
  };
  alarms?: {
    create(name: string, info: { periodInMinutes: number }): void;
    onAlarm: { addListener(listener: (alarm: { name: string }) => void): void };
  };
};

const transport = new SafariTransport();
const snapshots = new SnapshotStore(transport);
let appUnavailable = false;

const queue = new EventQueue(transport, {
  onLatestVersion(version) {
    appUnavailable = false;
    // Piggyback freshness: browsing generates events; events report the
    // latest version; a newer version pulls a fresh snapshot.
    void snapshots.refreshIfStale(version);
  },
  onAppUnavailable() {
    appUnavailable = true;
  },
});

// Startup refresh (also fires when Safari cold-starts the background page).
void snapshots.refreshIfStale();

// Slow heartbeat floor — 10 minutes, NOT a 2-second poll.
browser.alarms?.create("cck-heartbeat", { periodInMinutes: 10 });
browser.alarms?.onAlarm.addListener((alarm) => {
  if (alarm.name === "cck-heartbeat") {
    void snapshots.refreshIfStale();
    void queue.flush();
  }
});

// Periodic queue flush while events exist.
setInterval(() => void queue.flush(), FLUSH_INTERVAL_MS);

interface ContentMessage {
  kind: "getSnapshot" | "postEvents" | "flushNow" | "openDashboard" | "status";
  events?: ExposureEvent[];
  itemId?: string;
}

browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  const msg = message as ContentMessage;
  switch (msg.kind) {
    case "getSnapshot":
      void snapshots.cached().then(async (cached) => {
        sendResponse(cached ?? (await snapshots.refreshIfStale()) ?? null);
      });
      return true;
    case "postEvents":
      void queue.enqueue(msg.events ?? []).then(() => sendResponse({ ok: true }));
      return true;
    case "flushNow":
      void queue.flush().then((ok) => sendResponse({ ok }));
      return true;
    case "openDashboard":
      void transport.call("openDashboard", { itemId: msg.itemId }).then(() => sendResponse({ ok: true }));
      return true;
    case "status":
      void queue.pending().then((pending) => sendResponse({ appUnavailable, pendingEvents: pending }));
      return true;
  }
});
