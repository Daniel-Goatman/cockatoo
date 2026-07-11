import type { ExposureEvent, PostEventsResponse, SyncErrorResponse, Transport } from "./types";
import { isSyncError } from "./types";

// At-least-once event delivery: the queue is cleared only after the native
// response acknowledges; duplicates are harmless by idempotency (R5).
// No silent catch-and-drop (the prototype's fire-and-forget flaw).

export const FLUSH_THRESHOLD = 20;
export const FLUSH_INTERVAL_MS = 30_000;
const QUEUE_KEY = "eventQueue";

export interface QueueDelegate {
  /** Called with the server's latestVersion after a successful flush —
   * the piggyback freshness signal (docs/plan/05 §freshness). */
  onLatestVersion(version: number): void;
  onAppUnavailable(): void;
}

export class EventQueue {
  private transport: Transport;
  private delegate: QueueDelegate;
  private flushing = false;

  constructor(transport: Transport, delegate: QueueDelegate) {
    this.transport = transport;
    this.delegate = delegate;
  }

  async enqueue(events: ExposureEvent[]): Promise<void> {
    if (events.length === 0) return;
    const queue = (await this.transport.cacheGet<ExposureEvent[]>(QUEUE_KEY)) ?? [];
    queue.push(...events);
    await this.transport.cachePut(QUEUE_KEY, queue);
    if (queue.length >= FLUSH_THRESHOLD) {
      await this.flush();
    }
  }

  async pending(): Promise<number> {
    return ((await this.transport.cacheGet<ExposureEvent[]>(QUEUE_KEY)) ?? []).length;
  }

  /** Flush everything queued. Ack-then-clear; on failure the queue stays. */
  async flush(): Promise<boolean> {
    if (this.flushing) return false;
    this.flushing = true;
    try {
      const queue = (await this.transport.cacheGet<ExposureEvent[]>(QUEUE_KEY)) ?? [];
      if (queue.length === 0) return true;

      const response = await this.transport.call<PostEventsResponse | SyncErrorResponse>(
        "postEvents",
        { events: queue },
      );
      if (isSyncError(response)) {
        if (response.error === "appUnavailable") this.delegate.onAppUnavailable();
        return false; // queue retained — retried on the next trigger
      }

      // Acknowledged: clear exactly what we sent (new events may have
      // arrived while awaiting).
      const current = (await this.transport.cacheGet<ExposureEvent[]>(QUEUE_KEY)) ?? [];
      const sentIds = new Set(queue.map((e) => e.id));
      await this.transport.cachePut(QUEUE_KEY, current.filter((e) => !sentIds.has(e.id)));

      this.delegate.onLatestVersion((response as PostEventsResponse).latestVersion);
      return true;
    } catch {
      return false; // transport threw — queue retained
    } finally {
      this.flushing = false;
    }
  }
}
