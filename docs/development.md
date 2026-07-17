# Development workflow

This project is built from the terminal. Xcode must be installed for Apple's
Safari extension toolchain, but opening the IDE is optional.

## Toolchain

- macOS 15.6 or newer (build host; the built app targets macOS 14)
- Xcode 26.0 or newer (the project uses Xcode's object version 77)
- Swift 5.10 or newer
- Node.js 20 or newer; CI uses Node.js 24
- npm and Git

Run `script/doctor.sh` for a concrete check of the current machine.

## First checkout

```sh
script/bootstrap.sh
script/check.sh
```

`bootstrap.sh` uses `npm ci`, so `extension/package-lock.json` is authoritative.
SwiftPM resolves the pinned GRDB version from `Package.resolved`.

## Signing configuration

Checked-in configuration lives in `App/Config/`:

- `Base.xcconfig` contains shared IDs, minimum macOS, universal architectures,
  and unsigned clean-clone defaults.
- `Debug.xcconfig` and `Release.xcconfig` include the base and optional local file.
- `Local.example.xcconfig` documents the contributor-owned overrides.
- `Local.xcconfig` is gitignored and must never be committed.

For full Safari testing:

```sh
cp App/Config/Local.example.xcconfig App/Config/Local.xcconfig
```

Edit these values:

- `COCKATOO_DEVELOPMENT_TEAM`: your Apple team ID
- `COCKATOO_APP_BUNDLE_ID`: a bundle ID your team can provision
- `COCKATOO_APP_GROUP`: an App Group registered for the same team
- `COCKATOO_IPC_SERVICE`: normally `$(COCKATOO_APP_GROUP).api`

Both targets read these values from the same configuration. Their entitlements,
Info.plists, app launch lookup, database container, and CFMessagePort name stay
in sync automatically.

Apple Development signing is for local testing. It is not Developer ID signing,
not notarized, and not a redistributable release artifact.

## Commands

### Build and test

```sh
script/check.sh                 # complete local/CI-equivalent verification
script/check.sh --skip-xcode    # core, extension, and packs only
script/build.sh                 # Release; local signing if configured, unsigned otherwise
script/build.sh --debug
script/build.sh --unsigned      # force clean-clone unsigned compile verification
```

The app is written to `build/DerivedData/Build/Products/<Configuration>/Cockatoo.app`.
Both the app and appex are built as `arm64 + x86_64` universal binaries.

### Install and run

```sh
script/install-dev.sh                    # ~/Applications/Cockatoo.app
script/install-dev.sh --debug
script/install-dev.sh --restart-safari
script/install.sh                        # /Applications/Cockatoo.app
script/build_and_run.sh --verify
```

Installation intentionally requires `Local.xcconfig`. An unsigned build cannot
use the App Group and is refused instead of installing a partially working app.

After the first install, enable Cockatoo in Safari → Settings → Extensions.
Safari caches extension processes, so reload existing tabs or restart Safari
after changing extension resources.

#### Safari and locally-signed (dev) builds

`install-dev.sh` produces an **Apple Development**-signed build. Safari treats
any web extension whose containing app is not Developer ID-signed **and**
notarized as "unsigned," so it appears in Settings → Extensions but its toolbar
button, per-site permission UI, and content-script injection stay inert until
you enable the developer toggle:

1. Safari → Settings → Advanced → **Show features for web developers**.
2. Menu bar → **Develop → Allow Unsigned Extensions** (or the Developer
   settings tab) and authenticate.

This setting **resets every time Safari quits**, so a dev build needs it
re-enabled each launch. That reset is Safari's behaviour, not a Cockatoo bug.
Community launch agents automate the re-toggle (it still prompts for your
password) — e.g. [apuokenas/allow-unsigned-extensions][aue] (MIT). For a build
that just works, produce a notarized one (below).

[aue]: https://github.com/apuokenas/allow-unsigned-extensions

### Distributable (notarized) build

`script/release.sh` builds a **Developer ID-signed, notarized, stapled**
`Cockatoo.app`. A notarized build loads its Safari extension permanently — no
"Allow Unsigned Extensions" toggle, no per-launch password.

One-time setup:

- A **paid Apple Developer Program team** — free/personal teams cannot create
  Developer ID profiles, so notarized distribution needs a paid membership.
- A **Developer ID Application** certificate for that team in your login
  keychain (Xcode → Settings → Accounts → Manage Certificates → +).
- The bundle ID and App Group registered under that same team. The release team
  may differ from the one in `Local.xcconfig`; point the build at it with
  `COCKATOO_DEVELOPMENT_TEAM=<paid-team-id>` (it must match the Developer ID
  certificate's team).
- A notarytool credential profile stored in your keychain:

  ```sh
  xcrun notarytool store-credentials cockatoo-notary \
    --apple-id you@example.com --team-id ABCDE12345 \
    --password <app-specific-password>
  # or, with an App Store Connect API key:
  #   --key <AuthKey.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>
  ```

Then build (set `COCKATOO_DEVELOPMENT_TEAM` if your paid team differs from
`Local.xcconfig`):

```sh
export COCKATOO_NOTARY_PROFILE=cockatoo-notary
export COCKATOO_DEVELOPMENT_TEAM=ABCDE12345   # your paid Developer ID team

script/release.sh            # build + notarize + staple
script/release.sh --install  # also install to ~/Applications
script/release.sh --system   # install to /Applications
script/release.sh --no-notarize  # signing-only dry run (skips the notary service)
```

The script signs with Developer ID (automatic signing + `-allowProvisioningUpdates`
so the App Group entitlement gets a matching profile), notarizes the exported
app, staples the ticket, and verifies with `codesign` and `spctl`. Output lands
in `build/release-export/Cockatoo.app`.

### Individual subsystems

```sh
swift test
swift run CockatooDev
swift run packtool validate packs/build/de-2026.10.json
swift run packtool import-test packs/build/de-2026.10.json
swift run learnerctl --db /tmp/cockatoo.sqlite import packs/build/de-2026.10.json
swift run learnerctl --db /tmp/cockatoo.sqlite simulate --days 30

cd extension
npm test
npm run lint:boundaries
npm run build
```

## Cleaning

`script/clean.sh` removes Swift/Xcode and extension build output.
`script/clean.sh --dependencies` also removes `extension/node_modules`; rerun
`script/bootstrap.sh` afterwards.

## Troubleshooting

- **Provisioning profile required:** unsigned App Group entitlements were
  requested. Use `script/build.sh --unsigned` for compile-only verification or
  configure an Apple Development team for installation.
- **Extension not visible:** confirm the app is in a stable Applications folder,
  rerun the installer, then reopen Safari's Extensions settings.
- **Extension is enabled but does nothing** (no toolbar button, "Edit Websites"
  is unresponsive, no swaps): the dev build is unsigned as far as Safari is
  concerned. Enable **Develop → Allow Unsigned Extensions** (resets each launch,
  see above), or ship a notarized build with `script/release.sh`.
- **Multiple Cockatoo extensions after rebuilds, then a broken record:** dev
  builds share the extension bundle ID, so deleting some copies can leave
  Safari's per-extension record stale. Remove every `Cockatoo.app`, relaunch
  Safari once so it drops the extension, then reinstall and reopen Safari.
- **Extension shows app unavailable:** launch Cockatoo and confirm the app and
  appex have the same App Group using `codesign -d --entitlements :- <bundle>`.
- **Old content scripts:** reload affected tabs or pass `--restart-safari`.
- **Repo moved:** run `script/clean.sh`; SwiftPM caches absolute paths.
