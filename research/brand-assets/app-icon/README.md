# App-icon tile ("the button the logo sits on")

The Cockatoo Dock/⌘-tab icon is generated from original geometric paths. No
baked-in drop shadow — macOS draws that itself, which is why it looks native
next to every other icon.

## The recipe

1. **Canvas**: 1024×1024, fully transparent.
2. **Tile**: Apple's Big Sur icon-grid squircle — an **824×824 rounded
   rect centered on the canvas** (inset 100 on every side), corner radius
   **180** (≈ 0.218 × tile side). Respecting the 824/1024 grid is most of
   the trick: it makes the icon sit at exactly the same visual size as
   Finder, Safari, etc.
3. **Fill**: vertical graphite gradient, **#252527 (top) → #131314
   (bottom)**. The ~7% luminance drift is what reads as a softly lit
   convex button instead of a flat slab.
4. **Rim**: a **4px stroke of the brand gold #F2C53A at 18% opacity**,
   just inside the edge. Too faint to read as a border, but it catches
   the eye like a machined chamfer — this is the "clean" part.
5. **Glyph**: the colour compact-bust cockatoo mark centered at 69% of the
   tile. Its cream body, swept gold crest, rounded dark beak, and short neck
   remain legible down to the 16px app-icon source.

## Reusing it in another app

- `make-icon.swift` renders all ten `AppIcon.appiconset` PNGs directly from
  the checked-in paths: `swift make-icon.swift <AppIcon.appiconset>`. The
  16px and 32px outputs use optical sizing so Dock and Finder do not collapse
  the bill and head into a thin, generic bird shape.
- `cockatoo-mark.svg` is the colour brand mark for documentation and future
  web use.
- `cockatoo-mark-solid.svg` is the single-colour export for documentation and
  future template-icon contexts.
- `CockatooToolbar*Shape` in the app recreates the compact neck, domed head,
  spread crest, and tucked beak as a resolution-independent AppKit template.
  AppKit draws it at the display's backing scale and applies the current
  menu-bar foreground colour at runtime.
- To retint for the other app, change three constants at the top of the
  script: `fillTop`/`fillBottom` (keep the ~7% top-lighter drift) and
  `rimColor` (your accent at 15–20% opacity).
The bird is an original vector construction, not a trace of third-party
artwork.
