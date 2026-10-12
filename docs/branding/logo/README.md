# Logo: proposals

Symbols only, without a name (the name was not chosen yet). 1024x1024
SVGs with a full background and no rounded corners: iOS applies the
squircle mask itself. The motif stays within the central circle of
about 700 px to survive the mask and stay readable at 60 px.

Preview: open `index.html` (180 and 60 px on light and dark
backgrounds, 1024 px expandable).

Wave and prism were dropped after the first round. The second round
(below) develops voice and lanes and reworks the fan.

File names keep their original French words: `eventail` is the fan,
`voies` the lanes, `troupeau` the herd.

## 1. Fan (recommended)

`1-eventail.svg`, variants `1-eventail-dark.svg` and
`1-eventail-tinted.svg`.

A glass disc (the big voice button) from which three branches spread
towards three dots: one intent, several worktrees. The three colours
match the agent states on the main screen (blue working, green done,
orange blocked), which ties the icon to the UI. The translucent disc
with a light rim is the most direct Liquid Glass reference of the five.

Why first: it is the only one that says both the gesture (the button)
and the effect (one to many), it stays readable at 60 px and looks like
no known system icon. Risk: close to a graph or share pictogram, to
watch if the name does not anchor it.

## 5. Voice and lanes

`5-voies.svg`, variants `5-voies-dark.svg` and `5-voies-tinted.svg`.

A voice wave that splits into three parallel lanes. The voix/voies
(voice/lanes) pun only works in French. Monochrome, so very clean in
tinted mode. Less Liquid Glass than the fan, and the wave gets thin at
60 px (fixed in the second round).

## 4. Herd

`4-troupeau.svg`.

A glass-ringed leader and five dots in flight formation pointing
right: the whistle that sends the herd off, a direct nod to herdr. The
warmest, but reading it as "send" depends on the V formation, less
clear when small.

## iOS 26 variants

For the first two and for the two kept from each family in the second
round: `-dark` keeps the motif colours on a near-black background,
`-tinted` is a greyscale motif on black that the system colourises with
the chosen tint. In Icon Composer, background and motif layers will
need to be separated so the native Liquid Glass rendering (highlights,
depth) applies instead of the gradients drawn here.

## Second round

### Voice and lanes

Stroke raised from 60 to 72-80 px to hold at 60 and 40 px, and a short
straight trunk between the wave and the split so voice and dispatch
read as two distinct steps. The lanes split in a soft S (Bézier curves
with horizontal tangents).

- `voies-v2-a-epais.svg` (recommended, with `-dark` and `-tinted`):
  the original made thicker, simple sine wave, white on teal. The most
  readable when small and the cleanest when tinted.
- `voies-v2-b-statuts.svg` (with `-dark` and `-tinted`): a more
  speech-like wave (uneven amplitudes), each lane goes from white to its
  state colour; different lengths, the green one (done) goes all the
  way, the orange one (blocked) stops early. Night background.
- `voies-v2-c-clair.svg`: light background, ink wave, lanes in state
  colours taking over at the split point.
- `voies-v2-d-quatre.svg`: four thinner lanes with staggered lengths,
  on an orange-raspberry gradient. Busier at 40 px.
- `voies-v2-e-verre.svg`: glass tube motif (light rim, bluish core,
  drop shadow) on blue. The most Liquid Glass of the family, but the
  drawn rendering feels a bit skeuomorphic.

Dropped along the way: two lanes (reads as "wc"), a wave of growing
thickness, and three waves untangling (messy at the junction). Limit
shared by the whole family: the right part can read as an E or a €.

### Fan

The disc becomes a real button (mic, highlight on top, drop shadow) and
the branches lose their graph look: no more round dots at the end nor
constant-width strokes.

- `eventail-v2-b-lames.svg` (recommended, with `-dark` and `-tinted`):
  three coloured glass blades fanned out around the white button,
  overlapping through transparency. Literally a fan, the most readable
  at 40 px, the closest to Liquid Glass rendering.
- `eventail-v2-a-comete.svg` (with `-dark` and `-tinted`): blue button
  with a white mic, three tapered trails that start transparent and end
  solid in their state colour, as if thrown by the button.
- `eventail-v2-d-givre.svg`: the comet in monochrome, frosted glass
  button and white trails on bright blue. The most restrained and the
  most "Apple".
- `eventail-v2-e-givre-lames.svg`: the blades in white frosted glass on
  purple. Elegant but less contrast when small.
- `eventail-v2-c-aube.svg`: vertical fan, button at the bottom and
  blades going up, on a light background. More playful, borders on a
  hand or a bouquet.
