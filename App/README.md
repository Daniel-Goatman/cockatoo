# App packaging — manual Xcode step

Everything in this repo builds and tests headlessly (`swift build`, `swift test`,
`npm test`) **except** the final Safari packaging, which needs an Xcode project.
This is the P0/P4 manual step from [docs/plan/08-roadmap.md](../docs/plan/08-roadmap.md).

## What already exists

| Piece | Where | Status |
|---|---|---|
| App code (SwiftUI, menu bar, XPC listener) | `App/Cockatoo/Cockatoo/` | builds via SwiftPM |
| Appex forwarder | `App/SafariWebExtensionHandler.swift` | source ready |
| Extension resources | `extension/dist-resources/` (after `npm run build`) | built |
| Entitlements | `App/*.entitlements` | ready |

## One-time Xcode setup

1. **New project** → macOS App, product name `Cockatoo`, bundle id `dev.cockatoo.app`.
   Delete the template's ContentView/App files; app sources live in
   `App/Cockatoo/Cockatoo/` to the app target, and add the local SwiftPM package
   (repo root) so the target links `LearnerCore`.
2. **Add target** → Safari Extension (macOS), name `CockatooExtension`,
   bundle id `dev.cockatoo.app.Extension`. Replace the template handler with
   `App/SafariWebExtensionHandler.swift`. Point the
   extension's Resources at `extension/dist-resources/` (folder reference so
   `npm run build` output flows in).
3. **Entitlements**: assign `App/Cockatoo.entitlements` to the app and
   `App/CockatooExtension.entitlements` to the appex. Both
   carry App Group `group.dev.cockatoo.shared` — this is also what authorizes
   the appex to look up the XPC mach service `group.dev.cockatoo.shared.api`
   (decision D9).
4. **Login item**: in the app target's Info, no extra step for dev; for the
   real login-item behavior call `SMAppService.mainApp.register()` from
   Settings (TODO wired in a later pass).
5. **URL scheme**: register `cockatoo://` in the app target's Info → URL Types
   (used by the hover card's "Open in Cockatoo").

## The P0 spike checklist (run this FIRST, it de-risks everything)

With both targets installed and Safari's extension enabled:

- [ ] App running → browse a page → tokens appear (snapshot round-trip works)
- [ ] XPC round-trip latency acceptable (< 50 ms; log timestamps in the handler)
- [ ] Quit the app → browse → tokens still render (cached snapshot), popup shows
      "Cockatoo isn't running", events accumulate (popup shows pending count)
- [ ] Reopen the app → pending events drain (Library counts move)
- [ ] `sqlite3 <app-group>/cockatoo.sqlite 'select count(*) from exposure_event'`
      grows during browsing

If the mach-service lookup fails despite matching App Group prefixes, the
fallback is an `NSXPCListener.anonymous` endpoint published via the app group
container — see docs/plan/03-data-model-and-storage.md §R2.

## Dev loop without Xcode

- Learning engine: `swift test`
- Full loop simulation: `learnerctl --db /tmp/dev.sqlite import packs/build/de-2026.07.json && learnerctl --db /tmp/dev.sqlite simulate --days 30`
- App UI (no appex): `swift run CockatooDev` — the XPC listener registration
  fails harmlessly outside a bundle; everything else works, including
  onboarding, pack import, practice, and settings.
- Extension logic: `cd extension && npm test`
