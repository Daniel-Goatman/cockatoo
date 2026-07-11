import type { GetSnapshotResponse, Snapshot, SyncErrorResponse, Transport } from "./types";
import { isSyncError } from "./types";

// Background-side snapshot cache with pull-with-piggyback freshness:
// refresh when postEvents reports a newer version, on startup, and on the
// slow alarms heartbeat. No polling (replaces the prototype's 2s loop).

const SNAPSHOT_KEY = "snapshot";

export class SnapshotStore {
  private transport: Transport;

  constructor(transport: Transport) {
    this.transport = transport;
  }

  async cached(): Promise<Snapshot | undefined> {
    return this.transport.cacheGet<Snapshot>(SNAPSHOT_KEY);
  }

  /** Fetch if the app has something newer than the cache. Returns the
   * freshest snapshot available (cached on failure — graceful app-down). */
  async refreshIfStale(knownLatestVersion?: number): Promise<Snapshot | undefined> {
    const cached = await this.cached();
    if (cached && knownLatestVersion !== undefined && cached.version >= knownLatestVersion) {
      return cached;
    }
    const response = await this.transport
      .call<GetSnapshotResponse | SyncErrorResponse>("getSnapshot", { sinceVersion: cached?.version })
      .catch((): SyncErrorResponse => ({ error: "appUnavailable" }));

    if (isSyncError(response)) return cached;
    if ("unchanged" in response && response.unchanged) return cached;
    const fresh = (response as { snapshot: Snapshot }).snapshot;
    await this.transport.cachePut(SNAPSHOT_KEY, fresh);
    return fresh;
  }
}
