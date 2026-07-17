import { beforeEach, describe, expect, it, vi } from "vitest";
import type { GetOverviewResponse } from "../src/core/types";
import { initPopup, languageDisplayName, renderPopup, type PopupReply } from "../src/popup";

function popupDOM(): void {
  document.body.innerHTML = `
    <span id="connection-dot" class="connection-dot checking"></span>
    <span id="connection-label"></span>
    <h1 id="language"></h1>
    <p id="status"></p>
    <section id="stats" hidden></section>
    <span id="due-stat"></span><span id="new-stat"></span>
    <span id="library-stat"></span><span id="known-stat"></span>
    <p id="warning" hidden></p>
    <button id="practice" hidden></button>
    <button id="open">Open Cockatoo</button>
    <p id="sync-detail"></p>
  `;
}

function overview(overrides: Partial<GetOverviewResponse> = {}): GetOverviewResponse {
  return {
    activeLanguage: "de",
    libraryCount: 42,
    dueNow: 3,
    newAvailable: 2,
    knownCount: 11,
    availablePracticeItems: 5,
    ...overrides,
  };
}

function reply(overrides: Partial<PopupReply> = {}): PopupReply {
  return {
    appUnavailable: false,
    lastSyncError: null,
    pendingEvents: 0,
    snapshotVersion: 12,
    activeWords: 18,
    overview: overview(),
    isCached: false,
    ...overrides,
  };
}

describe("extension popup", () => {
  beforeEach(popupDOM);

  it("renders Swift-computed stats and an actionable practice button", () => {
    renderPopup(reply());

    expect(document.getElementById("language")?.textContent).toBe(languageDisplayName("de"));
    expect(document.getElementById("due-stat")?.textContent).toBe("3");
    expect(document.getElementById("new-stat")?.textContent).toBe("2");
    expect(document.getElementById("library-stat")?.textContent).toBe("42");
    expect(document.getElementById("known-stat")?.textContent).toBe("11");
    expect((document.getElementById("stats") as HTMLElement).hidden).toBe(false);
    expect((document.getElementById("practice") as HTMLButtonElement).hidden).toBe(false);
    expect(document.getElementById("practice")?.textContent).toBe("Practice 5 words");
  });

  it("hides practice when Swift reports no scheduled items", () => {
    renderPopup(reply({ overview: overview({ dueNow: 0, newAvailable: 0, availablePracticeItems: 0 }) }));

    expect((document.getElementById("practice") as HTMLButtonElement).hidden).toBe(true);
    expect(document.getElementById("status")?.textContent).toBe("No scheduled practice right now.");
  });

  it("shows an honest offline state without inventing live stats", () => {
    renderPopup(reply({ appUnavailable: true, lastSyncError: "appUnavailable", overview: null }));

    expect(document.getElementById("connection-label")?.textContent).toBe("App closed");
    expect((document.getElementById("warning") as HTMLElement).hidden).toBe(false);
    expect((document.getElementById("stats") as HTMLElement).hidden).toBe(true);
    expect(document.getElementById("status")?.textContent).toContain("cached for browsing");
  });

  it("paints cached stats before the live probe completes", async () => {
    let finishLive: ((value: PopupReply) => void) | undefined;
    const live = new Promise<PopupReply>((resolve) => { finishLive = resolve; });
    const cached = reply({ isCached: true, overview: overview({ dueNow: 7 }) });
    const fresh = reply({ overview: overview({ dueNow: 2 }) });
    const sendMessage = vi.fn((message: unknown) => {
      const kind = (message as { kind: string }).kind;
      return kind === "cachedStatus" ? Promise.resolve(cached) : live;
    });

    const initializing = initPopup(sendMessage);
    await Promise.resolve();
    await Promise.resolve();

    expect(document.getElementById("due-stat")?.textContent).toBe("7");
    expect(document.getElementById("connection-label")?.textContent).toBe("Refreshing");

    finishLive?.(fresh);
    await initializing;
    expect(document.getElementById("due-stat")?.textContent).toBe("2");
    expect(document.getElementById("connection-label")?.textContent).toBe("Connected");
    expect(sendMessage.mock.calls.map(([message]) => (message as { kind: string }).kind))
      .toEqual(["cachedStatus", "status"]);
  });

  it("shows an actionable error when Cockatoo cannot be opened", async () => {
    const sendMessage = vi.fn(async (message: unknown) => {
      const kind = (message as { kind: string }).kind;
      if (kind === "openDashboard") return { ok: false, error: "appUnavailable" };
      return reply();
    });
    await initPopup(sendMessage);

    (document.getElementById("open") as HTMLButtonElement).click();
    await Promise.resolve();
    await Promise.resolve();

    expect(document.getElementById("open")?.textContent).toContain("Couldn’t open");
    expect((document.getElementById("open") as HTMLButtonElement).disabled).toBe(false);
  });
});
