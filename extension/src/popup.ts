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
    .catch(() => null)) as { appUnavailable: boolean; pendingEvents: number } | null;

  if (!reply) {
    status.textContent = "Extension starting…";
    return;
  }
  status.textContent = reply.pendingEvents > 0
    ? `${reply.pendingEvents} progress events waiting to sync`
    : "Everything synced";
  warning.style.display = reply.appUnavailable ? "block" : "none";
}

void init();
