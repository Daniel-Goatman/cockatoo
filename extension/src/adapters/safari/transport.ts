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

export class SafariTransport implements Transport {
  async call<T>(method: string, payload?: unknown): Promise<T | SyncErrorResponse> {
    try {
      const response = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, buildEnvelope(method, payload));
      return (typeof response === "string" ? JSON.parse(response) : response) as T;
    } catch {
      return { error: "appUnavailable" };
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
