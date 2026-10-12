# Design

Reference for how the Heraldr app looks. The values live in
`ios/Heraldr/UI/Theme.swift` and in `AccentColor` in the asset catalog.

## Palette

"Graphite et gueules" (graphite and gules): everything is neutral
glass, almost monochrome, with a single bright color, the vermilion of
coats of arms ("gules"), reserved for voice. Selection does not take a
color, it takes light.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `accent` | `#C2321A` | `#FF5A3C` | Send, Stop, dictation wave, target arrow, links, checkmarks |
| `onAccent` | `#FFFFFF` | `#FFFFFF` | text and icons on the accent |
| `voiceInk` | `#C2321A` | `#FF7A5C` | microphone of the drop |
| `voiceGlow` | `#FF5A3C` | `#FF5A3C` | glow at the back of the drop, microphone halo |
| `selectedGlass` | white 92 % | white 20 % | glass tint of the target tile |
| `restingGlass` | `#8A8D96` at 12 % | none | tint of the other tiles, so the target stands out in light mode |
| `selectedGlow` | black 10 % | white 10 % | shadow of the target tile |
| `onStatus` | `#FFFFFF` | `#121214` | icon on a status dot (notices) |
| `macOnline` | `#1F8A4C` | `#6EDB8F` | Mac online dot, the only green in the app |
| `wallBase` | `#F1F1F3` | `#0B0B0D` | background of every screen |
| `wallBlobOne` | `#D8DAE0` | `#26282E` | blurred blob, top left |
| `wallBlobTwo` | `#E4E7EE` | `#1A1D24` | blurred blob, right |
| `wallBlobThree` | `#F4D3CB` | `#3A1712` | blurred blob, bottom: faint red glow under the drop |

Text stays the system's (`.primary`, `.secondary`).

Contrast (WCAG 2.1):

- `accent` as text on `wallBase`: 4.9:1 in light, 6.3:1 in dark
- `onAccent` on `accent`: 5.6:1 in light, 3.1:1 in dark; in dark, white
  only sits on large text (Send, bold title3) or an icon, where 3:1 is
  enough
- `voiceInk` microphone on `wallBase`: 4.9:1 in light, 7.7:1 in dark
- `onStatus` on status dots: at least 5.2:1

## Status colors

| Status | Light | Dark | On `wallBase` (light / dark) | Dot |
| --- | --- | --- | --- | --- |
| idle, unknown | `#6A6C73` | `#D7D8DD` | 4.6 / 13.8 | ring |
| done | `#6A6C73` | `#D7D8DD` | 4.6 / 13.8 | filled dot |
| working | `#0A63C9` | `#64C8FF` | 5.1 / 10.5 | dot, pulsing ring |
| blocked | `#8F5400` | `#FFC23D` | 5.4 / 12.2 | dot, steady halo |

Green is out of the statuses: idle and done both lead to "Ready", they
share the "ready" grey and only differ by shape (ring or dot). Only
working and blocked take a color, and nothing competes with them. Color
never carries the information alone: the status label is written under
the target.

Notices and history: sent in "ready" grey, queued in working blue,
failed in red (`#D70015`, `#FF453A` in dark).

## Typography

SF Pro, no embedded font.

| Element | Style |
| --- | --- |
| Target name | SF Pro Rounded heavy 44 pt for all, tracking -1 |
| "TARGET" label | caption heavy, uppercase, tracking 1.2 |
| Target status | callout semibold, then secondary footnote |
| Workspace tile | 15 pt semibold, two lines at most |
| Live dictation | SF Pro Rounded semibold 26 pt, provisional words in secondary |
| Preview | 19 pt medium |

## Sizes

- voice drop: 92 pt, in the middle of the bottom bar, between two 54 pt
  glass circles (Write, Paste), 16 pt apart; icons only, labels for
  VoiceOver. Before: a 104 pt orb sticking out of a 92 pt capsule,
  set apart by a `wallBase` ring
- drop microphone: 30 pt medium; `voiceGlow` radial glow from 55 % to
  0, centered under the bottom of the drop (115 % of its height),
  72 pt radius
- grid: two columns, 8 pt gap, 16 pt margin; the first workspace (Home)
  takes the full width above
- target: 38 % of the screen height, as a `safeAreaBar` at the top of
  the grid
- grid edges when scrolling: iOS 26 `.soft` edge effect at the top and
  bottom; at the top, tiles also fade out over the last 56 points of
  the target, so they never pass behind its text; at the bottom, they
  pass blurred under the drop and the circles
- tile: 58 pt minimum height, 20 pt corners; target in bold,
  `selectedGlow` shadow with a 13 pt radius offset by 6 pt
- dictation: Stop 112 pt, Cancel 64 pt
- preview: full-width Send, 64 pt high; Close 44 pt
- attached screenshots: 84 pt high thumbnails in the image's aspect
  ratio (width between 0.6 and 1.4 times the height, an iPhone
  screenshot stays portrait), 14 pt corners, 0.5 pt hairline at 20 %
  of the text color to set a screenshot apart from glass of the same
  tint; 20 pt glass cross in the corner, 40 pt tap area
- every tap target is at least 44 pt

## Liquid Glass

iOS 26 `glassEffect`, no imitation material.

- plain `.regular` glass: Write and Paste circles, Mac pill, target
  banner and preview text, notices
- clear `.clear` glass: voice drop, without tint or ring; the color is
  only in the glow at the back and the microphone
- `selectedGlass` tinted glass: target tile, denser and lighter than
  the others, without color (like the selected segment of a `Picker`)
- `restingGlass` tinted glass: other tiles
- accent tinted glass: Send, Stop; Stop differs from voice by its shape
  (stop square on a filled disc), not by its color
- `.interactive()` on everything that can be touched
- no glass: the background (`Wallpaper`, colors and blur), body text,
  system lists (target picker)
- Reduce Transparency: the system makes the glass opaque; the drop's
  glow and microphone, on top of it, stay colored and keep it easy to
  find. Increase Contrast: system borders

## Icon

"Voix et voies" (voice and lanes) logo, single source in
`docs/branding/logo/`:

- default and dark: `5-voies-dark.svg`, recolored for the palette:
  wave and top lane `#FFFFFF`, middle lane `#C9CBD1`, bottom lane
  `#FF5A3C`, on a graphite gradient `#1A1B1F` → `#08090A`
- tinted: `5-voies-tinted.svg`, unchanged (greyscale)
- stroke thickened from 60 to 80 px at render time, to stay readable at
  60 px; the path is not modified

`bin/render-ios-icon` produces the 1024 PNGs of the AppIcon and the
logo shown in the app.

## Not a standard native look

- no `NavigationStack` or `List` on the home screen: a full-page
  composition
- the background is always the blurred gradient, never a system grey
- the target reads from afar: very large name, status in one sentence
- everything that can be touched is in the bottom half, usable
  one-handed
- the voice button dominates, Write and Paste stay secondary
- secondary screens (target picker, original transcription) can stay
  system sheets
- a sheet is dismissed by swiping it down, without a Close button: the
  system's filled accent cross weighed more than the content; only the
  full input screen, which cannot be swiped, keeps its own
