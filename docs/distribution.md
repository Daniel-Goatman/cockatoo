# Distribution and signing status

Cockatoo currently ships as a **source-first Developer Preview**. It does not
offer a trusted downloadable app.

## What was proven

| Workflow | Status | Meaning |
|---|---|---|
| Swift, extension, protocol, and pack tests | Supported | no signing required |
| Universal unsigned Xcode build | Supported | app + appex compile for Intel and Apple Silicon |
| Unsigned full Safari sync loop | Not supported | App Group entitlements require provisioning |
| Apple Development local install | Supported | app + appex share App Group and IPC works |
| Developer ID + notarized download | Not available | requires an eligible Developer ID identity |

The unsigned build reaches Xcode's compile and bundle validation stages, but its
linker ad-hoc signature has no team identifier and cannot authorize
`com.apple.security.application-groups`. Installing it would make the companion
app appear functional while the extension cannot reach its state, so the
installer deliberately refuses that mode.

An Apple Development profile is enough for the repository owner and contributors
to run the complete app locally. It is tied to the developer team and is not a
substitute for Developer ID distribution.

## Current release policy

- GitHub may host source tags, screenshots, video, checksums, and documentation.
- CI artifacts are build evidence only and must not be presented as user downloads.
- No `.dmg`, `.pkg`, Homebrew cask, or unsigned `.app` should be advertised.
- The project description should say **Developer Preview**, **German**, and
  **local-first** until later milestones change those facts.

## Future consumer release gate

A future downloadable release needs all of the following:

1. Developer ID Application signing for the app and nested appex.
2. Hardened Runtime with production entitlements.
3. A notarized and stapled archive or disk image.
4. Gatekeeper verification on a clean macOS user account.
5. Automated versioning, checksums, release notes, and update instructions.
6. An end-to-end Safari enablement test of the exact release artifact.

Until that gate is complete, the honest public deliverable is the repository
and its reproducible development workflow.
