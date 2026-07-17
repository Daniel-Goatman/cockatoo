# v0.1.0 source-only Developer Preview checklist

## Scope and content

- [x] scope frozen at the bundled 212-item German starter pack
- [x] production-size ~1,000-item pack moved to a future milestone
- [x] Tutor and runtime model/API-key paths removed
- [x] MIT license added
- [ ] German 2026.10 human spot review accepted

## Engineering

- [x] one-command bootstrap, check, build, and signed development install
- [x] unsigned universal build works without an Apple account
- [x] CI covers Swift, extension, protocol, packs, and unsigned Xcode build
- [x] clean-clone README/bootstrap/check test recorded
- [x] clean-clone Apple Development install tested
- [ ] seven-day dogfood record accepted

## GitHub presentation

- [x] final repository commits reviewed and clean
- [ ] demo MP4/GIF or screenshot set added
- [ ] README media section added
- [x] GitHub description/topics chosen
- [ ] source-only `v0.1.0` tag created from `main`
- [x] release notes explicitly say there is no downloadable `.app`

Do not create the tag until every unchecked release gate above is resolved.

## Clean-clone verification record

- Date: 2026-07-17
- Tested commit: `9d3f61804ea94872ec0474ba221312273e081673`
- Environment: macOS 15.7.5, Xcode 26.3, Node.js 25.9.0
- `script/bootstrap.sh`: passed from a fresh local clone
- `script/check.sh`: passed from that clone, including 100 Swift tests,
  42 extension tests, pack validation, protocol checks, and an unsigned
  universal app build
- `script/install-dev.sh --debug`: passed after adding an ignored local Apple
  Development configuration; installed to `~/Applications/Cockatoo.app`,
  registered the Safari extension, and launched the app

This verification was repeated after the native library-navigation fix and
canonical extension-popup branding landed. The fresh clone remained clean
after bootstrap, checks, build, and installation.

The signing configuration was copied only for the local test and remains
untracked. This verifies the contributor workflow, not Developer ID release
signing or notarization.
