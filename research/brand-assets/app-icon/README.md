# App-icon tile ("the button the logo sits on")

The Cockatoo Dock/⌘-tab icon is three layers, and the "button" look is the
first two. No baked-in drop shadow — macOS draws that itself, which is why
it looks native next to every other icon.

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
5. **Glyph**: your mark centered on top, ~55–65% of the tile width,
   in an off-white (Cockatoo uses #F2F2F2) so it never glares.

## Reusing it in another app

- `make-icon.swift` renders the whole thing:
  `swift make-icon.swift out/` (background only) or
  `swift make-icon.swift out/ myglyph.png 0.62` — emits all ten
  `AppIcon.appiconset` sizes plus a 1024 preview. Drop the PNGs into the
  appiconset, done.
- To retint for the other app, change three constants at the top of the
  script: `fillTop`/`fillBottom` (keep the ~7% top-lighter drift) and
  `rimColor` (your accent at 15–20% opacity).
- `icon-background.svg` is the same tile for design tools (rx is a
  circular approximation of Apple's continuous corner — visually
  indistinguishable at icon sizes).
- `icon-background-1024.png` is the rendered background, ready to layer
  under a glyph in any editor.

Sizes/verification: extracted 2026-07-14 by pixel-sampling the shipped
`icon_512@2x.png` (tile bounds 100→923, rim ≈4px, gold-over-graphite
alpha solves to 0.18); regenerated output diffs clean against it.
