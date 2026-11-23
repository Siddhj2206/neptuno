# Neptuno logo kit

The logo is shared by the whole family (Neptuno + Mercury). Only the wordmark colour changes per edition.

## SVG masters
| File | Use |
|---|---|
| `neptuno-logo.svg` | Primary logo, full colour. Use at 64 px and up. |
| `neptuno-logo-mono.svg` | One colour, true transparency (black ink). Change the single `fill` on the `<rect>` to recolour. |
| `neptuno-wordmark.svg` | Logo + name, horizontal. Name colour follows the viewer's light/dark setting. Text is outlined, no font needed. |
| `distributor-logo.svg` | GNOME About / Settings, light theme. Dark-theme version in `extra/`. |

## extra/
- `neptuno-logo-small.svg`: simplified cut for **48 px and below** (no tiny stars/bands, thicker orbit). Rasterise small sizes from this one, not from the full logo.
- `neptuno-logo-small-mono.svg`: one-colour version of the small cut.
- `neptuno-logo-mono-white.svg`: one colour in white, for dark backgrounds.
- `neptuno-wordmark-on-dark.svg` / `-on-light.svg`: fixed-colour wordmarks for renderers that ignore light/dark mode (librsvg, Inkscape, most build tools).
- `distributor-logo-dark.svg`: GNOME dark theme.
- `neptuno-special-seal.svg` / `-mono.svg`: banded seal for special use (merch, stickers, release art).

## PNG (png/, transparent)
- 16, 24, 32, 48: from the small cut. 64, 128, 256, 512: from the full logo.
- `neptuno.png` (256) → `/usr/share/pixmaps/neptuno.png`
- `neptuno-plymouth-512.png` → boot splash
- `neptuno-256-mono.png` → splash low-contrast fallback (white)

## favicon/
- `favicon.ico` (16/32/48, each hand-rendered from the small cut), `apple-touch-icon.png` (180, solid #0B1230 bg)

## social/
- GitHub social preview 1280×640, PNG + SVG source

## Colours
| | Hex |
|---|---|
| Night sky (disc) | #1C3274 |
| Outline | #0A1236 |
| Cream (orbit, stars) | #F4EAD5 |
| Neptune blue | #3E6FD8 |
| Mercury amber | #E8A33D |
| Background | #0B1230 |
| Wordmark on light | #1C3274 |
| Wordmark on dark | #F4EAD5 |

Wordmark typeface: Space Grotesk Medium (SIL Open Font License), converted to outlines.
