import type { GetOverviewResponse } from "./core/types";

declare const browser: {
  runtime: { sendMessage(message: unknown): Promise<unknown> };
};

export interface PopupReply {
  appUnavailable: boolean;
  lastSyncError: string | null;
  pendingEvents: number;
  snapshotVersion: number | null;
  activeWords: number;
  overview: GetOverviewResponse | null;
  isCached: boolean;
}

export interface OpenReply {
  ok: boolean;
  error?: string;
}

function element(doc: Document, id: string): HTMLElement {
  const value = doc.getElementById(id);
  if (!value) throw new Error(`missing popup element #${id}`);
  return value;
}

export function languageDisplayName(code: string): string {
  try {
    return new Intl.DisplayNames(["en"], { type: "language" }).of(code) ?? code.toUpperCase();
  } catch {
    return code.toUpperCase();
  }
}

function practiceLabel(overview: GetOverviewResponse): string {
  if (overview.dueNow > 0 && overview.newAvailable === 0) {
    return `Practice ${overview.dueNow} due word${overview.dueNow === 1 ? "" : "s"}`;
  }
  if (overview.newAvailable > 0 && overview.dueNow === 0) {
    return `Practice ${overview.newAvailable} new word${overview.newAvailable === 1 ? "" : "s"}`;
  }
  return `Practice ${overview.availablePracticeItems} words`;
}

export function renderPopup(reply: PopupReply | null, doc: Document = document): void {
  const status = element(doc, "status");
  const warning = element(doc, "warning");
  const stats = element(doc, "stats");
  const practice = element(doc, "practice") as HTMLButtonElement;
  const dot = element(doc, "connection-dot");
  const connectionLabel = element(doc, "connection-label");
  const syncDetail = element(doc, "sync-detail");

  if (!reply) {
    status.textContent = "Extension starting…";
    connectionLabel.textContent = "Starting";
    return;
  }

  dot.className = `connection-dot ${reply.appUnavailable ? "offline" : reply.isCached ? "checking" : "live"}`;
  connectionLabel.textContent = reply.appUnavailable ? "App closed" : reply.isCached ? "Refreshing" : "Connected";
  warning.hidden = !reply.appUnavailable;

  if (reply.overview) {
    const overview = reply.overview;
    element(doc, "language").textContent = languageDisplayName(overview.activeLanguage);
    element(doc, "due-stat").textContent = String(overview.dueNow);
    element(doc, "new-stat").textContent = String(overview.newAvailable);
    element(doc, "library-stat").textContent = String(overview.libraryCount);
    element(doc, "known-stat").textContent = String(overview.knownCount);
    stats.hidden = false;

    if (overview.availablePracticeItems > 0) {
      status.textContent = `${overview.availablePracticeItems} word${overview.availablePracticeItems === 1 ? " is" : "s are"} ready for a short session.`;
      practice.textContent = practiceLabel(overview);
      practice.hidden = false;
    } else {
      status.textContent = "No scheduled practice right now.";
      practice.hidden = true;
    }
  } else if (reply.lastSyncError && reply.lastSyncError !== "appUnavailable") {
    status.textContent = `Sync problem: ${reply.lastSyncError}`;
  } else if (reply.activeWords === 0) {
    status.textContent = "No active words yet. Open Cockatoo to import a language pack.";
  } else {
    status.textContent = `${reply.activeWords} word${reply.activeWords === 1 ? "" : "s"} cached for browsing.`;
  }

  const syncParts: string[] = [];
  if (reply.activeWords > 0) syncParts.push(`${reply.activeWords} active on pages`);
  if (reply.pendingEvents > 0) syncParts.push(`${reply.pendingEvents} event${reply.pendingEvents === 1 ? "" : "s"} waiting`);
  else if (!reply.appUnavailable) syncParts.push("synced locally");
  syncDetail.textContent = syncParts.join(" · ");
}

async function openCockatoo(
  sendMessage: (message: unknown) => Promise<unknown>,
  button: HTMLButtonElement,
  destination?: "practice",
): Promise<void> {
  const original = button.textContent ?? "Open Cockatoo";
  button.disabled = true;
  button.textContent = "Opening…";
  const reply = (await sendMessage({ kind: "openDashboard", destination }).catch(() => null)) as OpenReply | null;
  if (!reply?.ok) {
    button.textContent = "Couldn’t open — try again";
    button.disabled = false;
    button.title = reply?.error ?? "Cockatoo did not respond";
    return;
  }
  button.textContent = original;
}

export async function initPopup(
  sendMessage: (message: unknown) => Promise<unknown>,
  doc: Document = document,
): Promise<void> {
  const open = element(doc, "open") as HTMLButtonElement;
  const practice = element(doc, "practice") as HTMLButtonElement;
  open.addEventListener("click", () => void openCockatoo(sendMessage, open));
  practice.addEventListener("click", () => void openCockatoo(sendMessage, practice, "practice"));

  const cached = (await sendMessage({ kind: "cachedStatus" }).catch(() => null)) as PopupReply | null;
  if (cached) renderPopup(cached, doc);

  const fresh = (await sendMessage({ kind: "status" }).catch(() => null)) as PopupReply | null;
  if (fresh) renderPopup(fresh, doc);
  else if (!cached) renderPopup(null, doc);
}

if (typeof browser !== "undefined") void initPopup(browser.runtime.sendMessage.bind(browser.runtime));
