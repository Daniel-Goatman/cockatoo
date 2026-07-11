declare const browser: {
  runtime: { sendMessage(message: unknown): Promise<unknown> };
};

async function init(): Promise<void> {
  const status = document.getElementById("status")!;
  const warning = document.getElementById("warning")!;
  document.getElementById("open")!.addEventListener("click", () => {
    void browser.runtime.sendMessage({ kind: "openDashboard" });
  });

  const reply = (await browser.runtime
    .sendMessage({ kind: "status" })
    .catch(() => null)) as {
    appUnavailable: boolean;
    lastSyncError: string | null;
    pendingEvents: number;
    snapshotVersion: number | null;
    activeWords: number;
  } | null;

  if (!reply) {
    status.textContent = "Extension starting…";
    return;
  }
  if (reply.lastSyncError && reply.lastSyncError !== "appUnavailable") {
    status.textContent = `Sync problem: ${reply.lastSyncError}`;
  } else if (reply.activeWords === 0) {
    status.textContent = "No words active yet — open Cockatoo to import a language pack.";
  } else {
    const pending = reply.pendingEvents > 0 ? ` · ${reply.pendingEvents} events waiting` : " · synced";
    status.textContent = `${reply.activeWords} words in rotation${pending}`;
  }
  warning.style.display = reply.appUnavailable ? "block" : "none";
}

void init();
