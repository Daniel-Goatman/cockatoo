# App/ — agent instructions

The Xcode project (app + Safari appex) and its packaging. Build settings live
in `App/Config/`; day-to-day use the repo-level scripts rather than the Xcode UI.

## Project facts

- `Cockatoo/Cockatoo.xcodeproj` — two targets:
  - **Cockatoo** (app, bundle id `dev.cockatoo.app`) — sources are the
    file-system-synchronized folder `Cockatoo/Cockatoo/`; the SAME folder is
    the `CockatooDev` SPM target, so code must build under both (Xcode adds
    MemberImportVisibility + default-MainActor; import Combine explicitly).
  - **CockatooExtension Extension** (appex, `dev.cockatoo.app.Extension`) —
    handler source lives ONLY in `Cockatoo/CockatooExtension Extension/`;
    web-extension resources are rsynced from `extension/dist-resources/` by
    the "Copy WebExtension Resources" script phase (script sandboxing is OFF
    for that target — required for the rsync).
- Entitlements: `Cockatoo.entitlements` (in the app folder) and
  `../CockatooExtension.entitlements` carry the App Group from xcconfig. The
  appex reads the containing app ID and IPC name from its Info.plist; all
  identity values must come from the same configuration.
- Deployment target 14.0 — do not let Xcode bump it above the host macOS.

## IPC (hard-won — don't regress)

- App side: `CockatooIPCListener` (`IPCListener.swift`) registers a
  **CFMessagePort** named `group.dev.cockatoo.shared.api` on the main
  runloop. NSXPCListener(machServiceName:) does NOT work here — it only
  registered when Xcode launched the app (docs/plan/03 §R2 outcome).
- Appex side: stateless `CFMessagePortCreateRemote` + synchronous
  send/reply per request. Launch/activation is allowed ONLY for
  `openDashboard`; background traffic never resurrects the app.
- `openDashboard` fronts the window via `.cockatooOpenDashboard`; its optional
  `destination: "practice"` payload selects the Practice section before the
  window appears.
  notification, received by the always-alive MenuBarLabel view.

## Editing the pbxproj

It's hand-editable (this project's targets were partly wired that way), but
close Xcode first, keep edits surgical, and verify with
`xcodebuild -project App/Cockatoo/Cockatoo.xcodeproj -scheme Cockatoo build`
before committing. `xcuserdata/` and `App/Config/Local.xcconfig` are gitignored — never commit them.

## Login item

Settings → "Launch Cockatoo at login" uses `SMAppService.mainApp`. It only
registers reliably from the stable `/Applications` copy (install script),
not from DerivedData builds — the toggle surfaces the error rather than
pretending.
