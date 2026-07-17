# Cockatoo — agent instructions

macOS language-learning app: Safari extension swaps words on pages into
German; menu bar app owns all state. Design docs in `docs/plan/` are the
source of truth for intent — read `01-vision-and-principles.md` before
architectural changes. Principles are cited in code comments as P1–P8 and
risks as R1–R8; those references resolve in the plan docs.

## Commands

| Task | Command |
|---|---|
| Swift tests (the deep suite) | `swift test` |
| Extension tests | `cd extension && npm test` |
| Extension bundle | `cd extension && npm run build` (output: `extension/dist-resources/`, consumed by the appex's Copy WebExtension Resources phase) |
| Boundary lint | `cd extension && npm run lint:boundaries` |
| Pack validation | `swift run packtool validate packs/build/de-2026.10.json` |
| Full-loop simulation (no Safari) | `swift run learnerctl --db /tmp/dev.sqlite import packs/build/de-2026.10.json && swift run learnerctl --db /tmp/dev.sqlite simulate --days 30` |
| App UI without installing | `swift run CockatooDev` |
| Complete verification | `script/check.sh` |
| Signed local install | `script/install-dev.sh` (`script/install.sh` keeps the stable `/Applications` workflow) |

After changing extension or app code, `script/install-dev.sh` is the local
deploy step. It requires Apple Development configuration; the user does not
open Xcode.

## Hard rules

- **P1 — Swift owns all learning logic.** SRS, tiers, stages, due-ness,
  eligibility live ONLY in `Sources/LearnerCore/`. The extension is a dumb
  renderer + event emitter. Never implement a learning rule in TypeScript.
- **P2 — one progress store.** `item_progress` is the only progress state.
  No parallel stores, ever (the prototype died of this).
- **P4 — no fake UI.** A control that renders must function. Don't add
  placeholder buttons or advertised-but-ungeneratable modes.
- **Protocol changes need BOTH sides + a fixture.** The app⇄extension
  protocol is defined twice (Swift `Sources/LearnerCore/Sync/Messages.swift`,
  TS `extension/src/core/types.ts`) and pinned by `protocol-fixtures/*.json`,
  decoded by tests on both sides. Any protocol change: update both types AND
  the fixture in the same commit.
- **Envelope payloads are JSON TEXT strings** — never base64/Data, never
  nested objects. (A `Data`-typed payload once silently broke every request.)
- **Dates on the wire have fractional seconds** (JS `toISOString()`). Swift
  decoding must go through `JSONCoding.decoder` (lenient ISO-8601) — never a
  fresh `JSONDecoder` with `.iso8601`.
- **IPC is CFMessagePort, not NSXPCListener.** `NSXPCListener(machServiceName:)`
  only registers when Xcode launches the app (verified live; docs/plan/03
  §R2 outcome). Port name `group.dev.cockatoo.shared.api` — the App-Group
  prefix is what the sandbox authorizes on both sides.
- **Quit means quit.** The appex may launch the app ONLY for `openDashboard`
  (explicit user intent). Background sync degrades to `appUnavailable`.
- **No decode-time migrations, no legacy imports** (D8). Schema changes go
  through numbered GRDB migrations in `AppDatabase.swift`.
- **No model or API-key path ships in the runtime.** Future agent/LLM pack
  authoring belongs in a separate CLI and secrets must never enter source.

## Gotchas (each cost real debugging time)

- The app's database lives in `~/Library/Group Containers/group.dev.cockatoo.shared/`
  — **TCC-protected on macOS 15+**: shell tools get "authorization denied".
  Inspect live state through the app's own port instead: send a JSON envelope
  (`{"protocolVersion":1,"method":"getSnapshot"}`) to the CFMessagePort — see
  the probe pattern in the session docs, or use `learnerctl` against a copy.
- Safari caches extension processes: after installing a new build, content
  scripts in already-open tabs are stale. Reload tabs or restart Safari.
- `swift build` caches absolute paths — after moving/renaming the repo,
  `rm -rf .build`.
- The Xcode project uses **file-system-synchronized folders**: files on disk
  under `App/Cockatoo/Cockatoo/` ARE the app target. Adding/removing files
  there changes the build without touching the pbxproj.
- App sources are built by BOTH the Xcode target and the `CockatooDev` SPM
  target (`Package.swift` points at the same folder). Code must compile in
  both: Xcode enables MemberImportVisibility (explicit `import Combine` etc.)
  and default-MainActor isolation.
- `learnerctl simulate` is sandboxed (in-memory) by default; `--persist`
  writes through to the target DB. Every `--db` path is a separate world.

## Verification bar

Before claiming a change works: `swift test` + `npm test` green, and for
anything touching the extension↔app boundary, `script/install-dev.sh` and drive
the real flow in Safari (browse → tokens → hover → popup status → practice).
The popup's status line is diagnostic-grade: it reports live sync errors
with detail, not cached optimism.
