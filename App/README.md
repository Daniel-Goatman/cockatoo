# macOS app packaging

The checked-in Xcode project builds the Cockatoo app and its Safari app
extension. No manual Xcode project setup is required.

Use the repository-level commands:

```sh
script/build.sh --unsigned   # universal compile verification; no install
script/install-dev.sh        # Apple Development-signed local install
script/check.sh              # all tests, packs, extension, and Xcode build
```

Build identity and signing configuration live in `App/Config/`. See
[`docs/development.md`](../docs/development.md) for local signing setup and
[`docs/distribution.md`](../docs/distribution.md) for why an unsigned full
Safari workflow is not supported.
