import type { SyncErrorResponse, Transport } from "../../core/types";
import { buildEnvelope } from "../../core/types";

// The ONLY file that touches sendNativeMessage (lint-enforced boundary).
// A Chrome port implements the same Transport over another mechanism.

declare const browser: {
  runtime: {
    sendNativeMessage(app: string, message: unknown): Promise<unknown>;
  };
  storage: {
    local: {
      get(keys: string[]): Promise<Record<string, unknown>>;
      set(items: Record<string, unknown>): Promise<void>;
    };
  };
};

const NATIVE_APP_ID = "application.id"; // Safari resolves to the containing app
const NATIVE_MESSAGE_TIMEOUT_MS = 8_000;

async function withTimeout<T>(operation: Promise<T>, timeoutMs: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      operation,
      new Promise<T>((_, reject) => {
        timer = setTimeout(() => reject(new Error("native message timed out")), timeoutMs);
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export class SafariTransport implements Transport {
  async call<T>(method: string, payload?: unknown): Promise<T | SyncErrorResponse> {
    try {
      const response = await withTimeout(
        browser.runtime.sendNativeMessage(NATIVE_APP_ID, buildEnvelope(method, payload)),
        NATIVE_MESSAGE_TIMEOUT_MS,
      );
      return (typeof response === "string" ? JSON.parse(response) : response) as T;
    } catch (error) {
      return {
        error: "appUnavailable",
        detail: error instanceof Error ? error.message : undefined,
      };
    }
  }

  async cacheGet<T>(key: string): Promise<T | undefined> {
    const result = await browser.storage.local.get([key]);
    return result[key] as T | undefined;
  }

  async cachePut(key: string, value: unknown): Promise<void> {
    await browser.storage.local.set({ [key]: value });
  }
}
