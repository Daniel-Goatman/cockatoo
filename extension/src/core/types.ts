// Protocol types — the TypeScript mirror of LearnerCore/Sync (one spec, two
// encodings; shared JSON fixtures keep them from drifting).

export const PROTOCOL_VERSION = 1;

export type FidelityTier = "exact" | "formMatched" | "approximate";

export interface SnapshotForm {
  match: string; // lowercased English surface form, e.g. "the house"
  display: string; // target text, e.g. "das Haus"
}

export interface SnapshotItem {
  id: string;
  kind: "word" | "chunk" | "pattern";
  tier: FidelityTier;
  forms: SnapshotForm[];
  hover: {
    target: string;
    pos?: string | null;
    example?: { source: string; target: string } | null;
    seenCount: number;
  };
}

export interface Snapshot {
  version: number;
  language: string;
  settings: {
    enabled: boolean;
    blockedHosts: string[];
    pageContextOptIn: boolean;
  };
  items: SnapshotItem[];
}

export type ExposureEventType = "seen" | "engaged" | "pinned" | "sentenceCaptured";

export interface ExposureEvent {
  id: string; // client UUID — idempotency (R5)
  itemId: string;
  type: ExposureEventType;
  occurredAt: string; // ISO-8601
  host?: string;
  sentence?: string;
}

export interface PostEventsResponse {
  accepted: number;
  latestVersion: number;
}

export type GetSnapshotResponse =
  | { unchanged: true; version: number }
  | { version: number; snapshot: Snapshot };

export type SyncErrorCode =
  | "appUnavailable"
  | "protocolMismatch"
  | "pageContextNotOptedIn"
  | "unknownMethod"
  | "badPayload"
  | "internalError";

export interface SyncErrorResponse {
  error: SyncErrorCode;
}

export function isSyncError(value: unknown): value is SyncErrorResponse {
  return typeof value === "object" && value !== null && "error" in value;
}

export interface MessageEnvelope {
  protocolVersion: number;
  method: string;
  /** JSON TEXT of the payload — plain string, never base64. Mirrors Swift's
   * MessageEnvelope; the envelope fixture test enforces both sides. */
  payload?: string;
}

export function buildEnvelope(method: string, payload?: unknown): MessageEnvelope {
  const envelope: MessageEnvelope = { protocolVersion: PROTOCOL_VERSION, method };
  if (payload !== undefined) envelope.payload = JSON.stringify(payload);
  return envelope;
}

/** The one seam a Chrome port replaces (docs/plan/05-extension.md). */
export interface Transport {
  call<T>(method: string, payload?: unknown): Promise<T | SyncErrorResponse>;
  cacheGet<T>(key: string): Promise<T | undefined>;
  cachePut(key: string, value: unknown): Promise<void>;
}
