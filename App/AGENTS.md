# App/ — agent instructions

The Xcode project (app + Safari appex) and its packaging. README.md here has
the original manual setup checklist; the project now exists, so day-to-day
you only need `script/install.sh` from the repo root.

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
  `../CockatooExtension.entitlements` — both carry App Group
  `group.dev.cockatoo.shared`. The appex launches the app by bundle id
  `dev.cockatoo.app`; renaming either bundle id breaks the pairing.
- Deployment target 14.0 — do not let Xcode bump it above the host macOS.

## IPC (hard-won — don't regress)

- App side: `CockatooXPCListener` (XPCListener.swift) registers a
  **CFMessagePort** named `group.dev.cockatoo.shared.api` on the main
  runloop. NSXPCListener(machServiceName:) does NOT work here — it only
  registered when Xcode launched the app (docs/plan/03 §R2 outcome).
- Appex side: stateless `CFMessagePortCreateRemote` + synchronous
  send/reply per request. Launch-on-miss ONLY for `openDashboard`.
- `openDashboard` fronts the window via `.cockatooOpenDashboard`
  notification, received by the always-alive MenuBarLabel view.

## Editing the pbxproj

It's hand-editable (this project's targets were partly wired that way), but
close Xcode first, keep edits surgical, and verify with
`xcodebuild -project App/Cockatoo/Cockatoo.xcodeproj -scheme Cockatoo build`
before committing. `xcuserdata/` is gitignored — never commit it.

## Login item

Settings → "Launch Cockatoo at login" uses `SMAppService.mainApp`. It only
registers reliably from the stable `/Applications` copy (install script),
not from DerivedData builds — the toggle surfaces the error rather than
pretending.
