# Setup guide

How to get Cockatoo running, whether you just want to explore the app or run the
full Safari extension. Everything here is a terminal command; you never need to
open the Xcode IDE, though Xcode must be installed because Apple builds Safari
extensions with its toolchain.

## Requirements

| Purpose | What you need |
|---|---|
| Run the app on its own | macOS 14 or newer |
| Build the app and Safari extension | macOS 15.6+, Xcode 26+, Node.js 20+, Git |
| Run the core and pack tools | Swift 5.10+ and Node.js 20+ |
| Run the full Safari sync loop | an Apple Development team and a provisioned App Group |

Run `script/doctor.sh` at any time to check your machine against these.

## Get the code

```sh
git clone https://github.com/Daniel-Goatman/cockatoo.git
cd cockatoo
script/doctor.sh      # check the toolchain
script/bootstrap.sh   # npm ci, then swift package resolve
```

## Path 1: explore the app (no Apple account)

This runs the SwiftUI app (Overview, Practice, Library, Settings) against the
bundled German pack, without the Safari extension. It is the fastest way to see
Cockatoo.

```sh
swift run CockatooDev
```

## Path 2: run the full Safari extension

The extension and app must share a provisioned App Group, so this path needs an
Apple developer account with an App Group registered to your team. Developer ID
signing and notarization are not required for local use; Apple Development
signing is enough.

1. Create your local signing config:

   ```sh
   cp App/Config/Local.example.xcconfig App/Config/Local.xcconfig
   ```

2. Edit `App/Config/Local.xcconfig` and set:
   - `COCKATOO_DEVELOPMENT_TEAM`: your Apple team ID
   - `COCKATOO_APP_BUNDLE_ID`: a bundle ID your team can provision
   - `COCKATOO_APP_GROUP`: an App Group registered to the same team
   - `COCKATOO_IPC_SERVICE`: normally `$(COCKATOO_APP_GROUP).api`

   This file is gitignored. Never commit it.

3. Build and install:

   ```sh
   script/install-dev.sh
   ```

   This builds both architectures, installs to `~/Applications/Cockatoo.app`,
   registers the extension, and launches the app.

4. Enable the extension in **Safari > Settings > Extensions**.

After changing content scripts, reinstall with `script/install-dev.sh
--restart-safari`, because Safari caches extension processes and already-open
tabs will run stale scripts otherwise.

`script/install.sh` installs the same build to `/Applications` instead, which is
useful for a stable login-item path.

## Verify a checkout

```sh
script/check.sh            # add --skip-xcode to skip the universal build (about a minute)
```

`check.sh` runs the Swift and extension test suites, the boundary lint, pack
reproducibility and validation, and an unsigned universal app build. It is the
same suite CI runs, so keep it green before opening a pull request.

## Common commands

| Command | What it does |
|---|---|
| `script/doctor.sh` | check the local toolchain and signing mode |
| `script/bootstrap.sh` | install locked npm dependencies and resolve Swift packages |
| `script/check.sh [--skip-xcode]` | run all tests, pack checks, and an unsigned build |
| `swift run CockatooDev` | launch the app with no Apple account |
| `swift test` | run the Swift suite (the deepest tested part of the project) |
| `cd extension && npm test` | run the extension suite |
| `script/build.sh [--debug] [--unsigned]` | build the universal app bundle |
| `script/install-dev.sh` | signed local install to `~/Applications` |
| `script/build_and_run.sh --verify` | signed build, install, launch, and process check |
| `script/clean.sh [--dependencies]` | remove generated output, optionally dependencies |

## Troubleshooting

- **Extension changes do not show up.** Safari caches extension processes.
  Reload the tab or reinstall with `script/install-dev.sh --restart-safari`.
- **"Authorization denied" reading the database.** The app database lives in a
  TCC-protected App Group container on macOS 15+. Inspect state through the
  app's own port or a `learnerctl` copy rather than shell tools. See
  [AGENTS.md](../AGENTS.md).
- **Build errors after moving or renaming the repo.** `swift build` caches
  absolute paths. Run `rm -rf .build` and rebuild.

For deeper development notes see [development.md](development.md), and for the
exact signing and distribution limits see [distribution.md](distribution.md).
</content>
