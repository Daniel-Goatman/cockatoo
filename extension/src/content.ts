import { Matcher } from "./core/matcher";
import { PageTransformer } from "./core/transformer";
import { HoverCard } from "./core/hoverCard";
import { ExposureTracker } from "./core/exposureTracker";
import { shouldRunOnPage, coarseHost } from "./core/pageGate";
import type { ExposureEvent, Snapshot } from "./core/types";

// Content script: dumb renderer + event emitter (P1). One snapshot request
// at document_idle, then purely local work; events batch to the background.

declare const browser: {
  runtime: {
    sendMessage(message: unknown): Promise<unknown>;
  };
};

async function main(): Promise<void> {
  const snapshot = (await browser.runtime
    .sendMessage({ kind: "getSnapshot" })
    .catch(() => null)) as Snapshot | null;
  if (!snapshot) return;

  const gate = shouldRunOnPage({
    protocol: location.protocol,
    host: location.hostname,
    enabled: snapshot.settings.enabled,
    blockedHosts: snapshot.settings.blockedHosts,
    ambientItemCount: snapshot.items.length,
  });
  if (!gate) return;

  const host = coarseHost(location.hostname);
  let batch: ExposureEvent[] = [];
  let sendTimer: ReturnType<typeof setTimeout> | null = null;

  const tracker = new ExposureTracker({
    host,
    now: () => Date.now(),
    uuid: () => crypto.randomUUID(),
    emit(event) {
      batch.push(event);
      if (sendTimer) clearTimeout(sendTimer);
      sendTimer = setTimeout(() => {
        const events = batch;
        batch = [];
        void browser.runtime.sendMessage({ kind: "postEvents", events });
      }, 2000);
    },
  });

  const hoverCard = new HoverCard(document, {
    async openDashboard(itemId) {
      const reply = (await browser.runtime
        .sendMessage({ kind: "openDashboard", itemId, destination: "library" })
        .catch(() => null)) as { ok?: boolean } | null;
      return reply?.ok === true;
    },
  });

  const byId = new Map(snapshot.items.map((item) => [item.id, item]));
  const transformer = new PageTransformer(document, new Matcher(snapshot), {
    onToken(el, item, form) {
      const full = byId.get(item.id) ?? item;
      tracker.track(el, full, form);
      hoverCard.attach(el, full);
    },
  });

  transformer.applyInitial();
  transformer.observe();

  // Flush the remaining batch when the tab hides.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden" && batch.length > 0) {
      const events = batch;
      batch = [];
      void browser.runtime.sendMessage({ kind: "postEvents", events });
      void browser.runtime.sendMessage({ kind: "flushNow" });
    }
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => void main());
} else {
  void main();
}
