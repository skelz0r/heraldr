# Logo

"Voice and lanes": a voice wave that splits into three parallel lanes,
one request dispatched to several worktrees. 1024x1024 SVGs with a
full background and no rounded corners: iOS applies the squircle mask
itself.

- `voice-and-lanes-dark.svg`: default and dark app icon, and the logo
  shown in the app
- `voice-and-lanes-tinted.svg`: tinted app icon (greyscale)

`bin/render-ios-icon` renders the PNGs of `AppIcon.appiconset` and
`Logo.imageset` from these files, with a thicker stroke so the lanes
stay readable at 60 px.
