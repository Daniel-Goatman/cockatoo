import { beforeEach, describe, expect, it, vi } from "vitest";
import { HoverCard, OPEN_TIMEOUT_MS } from "../src/core/hoverCard";
import { hausItem } from "./helpers";

describe("HoverCard", () => {
  beforeEach(() => {
    document.body.innerHTML = '<span id="token" data-cck-original="the house">das Haus</span>';
  });

  it("keeps secondary learning detail collapsed in a compact disclosure", () => {
    const card = new HoverCard(document, { openDashboard: async () => true });
    card.open(document.getElementById("token")!, hausItem(), true);

    const details = document.querySelector(".cck-hovercard-details") as HTMLDetailsElement;
    expect(details).not.toBeNull();
    expect(details.open).toBe(false);
    expect(details.querySelector("summary")?.textContent).toBe("Details");
    expect(details.textContent).toContain("The house is old.");
    expect(details.textContent).toContain("Seen 3 times");
  });

  it("waits for and reflects the real open result", async () => {
    const openDashboard = vi.fn(async () => false);
    const card = new HoverCard(document, { openDashboard });
    card.open(document.getElementById("token")!, hausItem(), true);

    const button = document.querySelector(".cck-hovercard-open") as HTMLButtonElement;
    button.click();

    expect(openDashboard).toHaveBeenCalledWith("de.word.haus");
    await vi.waitFor(() => {
      expect(button.textContent).toContain("Couldn’t open");
      expect(button.disabled).toBe(false);
    });
  });

  it("recovers when the native open request never replies", async () => {
    vi.useFakeTimers();
    try {
      const card = new HoverCard(document, {
        openDashboard: () => new Promise<boolean>(() => {}),
      });
      card.open(document.getElementById("token")!, hausItem(), true);

      const button = document.querySelector(".cck-hovercard-open") as HTMLButtonElement;
      button.click();
      expect(button.textContent).toBe("Opening…");

      await vi.advanceTimersByTimeAsync(OPEN_TIMEOUT_MS);

      expect(button.textContent).toContain("Couldn’t open");
      expect(button.disabled).toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });
});
