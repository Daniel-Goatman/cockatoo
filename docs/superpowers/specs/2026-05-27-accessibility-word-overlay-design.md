# Accessibility Word Overlay Proof of Concept Design

## Purpose

Build a native macOS feasibility prototype that visually replaces one exposed
English word in the user's current context without modifying content owned by
another application. The first teaching mapping is the standalone word
`and` rendered as `und`.

This prototype answers one question: can a macOS app obtain usable text and
screen-space bounds from the frontmost window of common apps through
Accessibility APIs, then place a stable teaching overlay above that word?

## Scope

The prototype will:

- Run as a native macOS Swift app with a menu bar control surface.
- Request Accessibility access when the user enables scanning.
- Inspect only the frontmost application's focused or main window.
- Search exposed window text for the first visible standalone,
  case-insensitive `and`.
- Draw one visual overlay showing `und` above the original word location.
- Keep the overlay click-through so underlying applications remain usable.
- Report useful compatibility status while moving among apps.

The prototype will not:

- Rewrite source text, alter documents, messages, fields, or browser DOM.
- Inspect every visible window at once.
- Overlay more than one occurrence of the teaching word.
- Use Screen Recording, OCR, a browser extension, vocabulary progression,
  pronunciation, persistence, hover explanations, or lesson UI.

## Architecture

The repository will start as a Swift Package Manager macOS GUI executable,
bundled for launch by a project-local run script. SwiftPM keeps the experiment
small and reproducible while allowing AppKit, SwiftUI, and ApplicationServices.

SwiftUI owns the user-facing app state and a short menu bar interface: whether
scanning is enabled, permission state, current compatibility status, and quit
or permission actions. AppKit is used only where macOS requires imperative
desktop behavior: checking Accessibility trust, interrogating another app's
accessibility hierarchy, and presenting a non-activating overlay panel.

The initial scanner uses a modest periodic refresh rather than per-application
Accessibility observers. Polling is appropriate for this compatibility probe
because it handles app switching, scrolling, and differing notification
behavior with one predictable path. An observer-based refresh can replace it
later if the supported-app evidence warrants production optimization.

## Components

### App And Menu Bar Surface

The app launches as a menu bar utility. Its menu contains an enabled toggle,
the fixed mapping `and -> und`, a compact status message, an action to prompt
for Accessibility permission when needed, and Quit. It does not open a normal
document window.

### Permission Service

A small service checks `AXIsProcessTrusted()` and invokes the standard
Accessibility prompt when requested. Until trust is available, scanning stops,
the overlay is hidden, and status explains that permission is required.

### Frontmost Window Scanner

On each enabled refresh, the scanner obtains the frontmost non-self
application, chooses its focused window with main-window fallback, and attempts
to retrieve text and range geometry from accessible text elements in that
window.

The search matches the first standalone occurrence of `and` without matching
inside words such as `android` or `candy`. It prioritizes text elements
available through the accessibility tree and discards matches for which macOS
does not return a usable non-empty screen rectangle through the bounds-for-range
parameterized attribute. A located match is considered visible only when that
rectangle intersects both the active window frame and a connected screen's
visible frame.

### Overlay Presenter

The presenter owns at most one borderless, non-activating `NSPanel`. It places
a label reading `und` at the reported screen rectangle, with an opaque
system-adaptive background sufficient to obscure the source glyphs. The panel
does not become key, ignores mouse events, and is removed whenever scanning is
disabled, permission is absent, focus moves to the teaching app itself, no
match is found, or a range cannot be placed.

## Data Flow

1. The user enables scanning from the menu bar.
2. The permission service reports trusted or prompts for access.
3. A timer requests a scan of the frontmost external app window.
4. The scanner emits either a located word rectangle plus app name or a
   descriptive no-overlay result.
5. The app state updates the menu status.
6. The overlay presenter shows, repositions, or hides the single `und` panel.

No captured text is persisted or sent off-device.

## Compatibility And Failure States

Apps may expose no readable accessibility text, readable text without
range-level geometry, or text whose coordinates change during scroll or layout
updates. Those are expected results of the feasibility test, not crashes.

The status surface distinguishes:

- Accessibility permission required.
- Scanning disabled.
- Frontmost app unavailable or is this app.
- No accessible standalone `and` found in the active window.
- An `and` was exposed but its screen bounds were unavailable.
- Overlay active in a named application.

The overlay is cleared on every non-active result to avoid leaving translated
text floating above stale content.

## Validation

Automated tests cover logic that is deterministic without controlling another
process: standalone word matching, scan-result status formatting, and mapping
configuration. Accessibility traversal and panel placement are thin platform
integration boundaries verified manually in the running app.

Manual compatibility checks will switch the frontmost window among apps such
as Notes, Safari or Chrome, Codex, Discord, and WhatsApp with visible text
containing `and`. For each app, record whether a correctly positioned `und`
appears, whether it tracks focus or scrolling, or whether the app reports a
readability or geometry limitation.

## Distribution Boundary

This proof of concept is intended for local development and direct execution,
not Mac App Store distribution. A production version using cross-application
Accessibility inspection would need the appropriate direct-download signing,
permission, privacy, and notarization work.
