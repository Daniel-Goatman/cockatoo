import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type {
  ExposureEvent,
  GetOverviewResponse,
  MessageEnvelope,
  PostEventsResponse,
  Snapshot,
  SyncErrorResponse,
} from "../src/core/types";
import { buildEnvelope } from "../src/core/types";
import { Matcher } from "../src/core/matcher";

// Same fixture files the Swift tests decode (protocol-fixtures/ at the repo
// root) — one spec, two encodings, drift caught on either side.

const fixturesDir = join(__dirname, "..", "..", "protocol-fixtures");
const load = <T>(name: string): T => JSON.parse(readFileSync(join(fixturesDir, name), "utf8")) as T;

describe("protocol fixtures", () => {
  it("snapshot.json decodes and drives the matcher", () => {
    const snapshot = load<Snapshot>("snapshot.json");
    expect(snapshot.version).toBe(412);
    expect(snapshot.items[0].tier).toBe("formMatched");
    expect(snapshot.settings.blockedHosts).toEqual(["bank.example"]);

    const matcher = new Matcher(snapshot);
    const matches = matcher.matches("We saw the houses and left");
    expect(matches.map((m) => m.display)).toEqual(["die Häuser", "und"]);
  });

  it("envelope.json matches what the transport actually builds", () => {
    const fixture = load<{
      withPayload: MessageEnvelope;
      withoutPayload: MessageEnvelope;
      openPractice: MessageEnvelope;
      openLibraryItem: MessageEnvelope;
    }>("envelope.json");
    expect(buildEnvelope("getSnapshot", { sinceVersion: 412 })).toEqual(fixture.withPayload);
    expect(buildEnvelope("getSettings")).toEqual(fixture.withoutPayload);
    expect(buildEnvelope("openDashboard", { destination: "practice" })).toEqual(fixture.openPractice);
    expect(buildEnvelope("openDashboard", { itemId: "de:jetzt", destination: "library" })).toEqual(fixture.openLibraryItem);
    // The payload is JSON TEXT (string), never base64/object — the Swift
    // side decodes exactly this shape (ProtocolFixtureTests).
    expect(typeof fixture.withPayload.payload).toBe("string");
  });

  it("overview.json carries only Swift-computed popup facts", () => {
    const overview = load<GetOverviewResponse>("overview.json");
    expect(overview.activeLanguage).toBe("de");
    expect(overview.availablePracticeItems).toBe(5);
    expect(overview.knownCount).toBe(11);
  });

  it("postEvents.json request/response/error decode", () => {
    const fixture = load<{
      request: { events: ExposureEvent[] };
      response: PostEventsResponse;
      errorResponse: SyncErrorResponse;
    }>("postEvents.json");
    expect(fixture.request.events).toHaveLength(2);
    expect(fixture.request.events[1].sentence).toContain("houses");
    expect(fixture.response.latestVersion).toBe(413);
    expect(fixture.errorResponse.error).toBe("appUnavailable");
  });
});
