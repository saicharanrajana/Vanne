# Curated collection covers

The four first-install collections ship with bundled 400×400 JPEG covers in
`assets/collections/`. They are square crops encoded at quality 5, so the
whole set adds about 125 KiB to the APK. Cards draw them with
`BoxFit.cover`; the rounded M3E square is the only clip.

| File | Collection | Source | Licence |
| --- | --- | --- | --- |
| `art.jpg` | Art | [Vincent van Gogh, *Cypresses* (1889), The Met](https://commons.wikimedia.org/wiki/File:Cypresses_MET_DP130999.jpg) | CC0 1.0; the Met API reports the object as public domain |
| `nature.jpg` | Nature | [David Marcu, *Alone in the unspoilt wilderness*](https://commons.wikimedia.org/wiki/File:Alone_in_the_unspoilt_wilderness_(Unsplash).jpg) | CC0 1.0, Commons licence-review category |
| `abstract.jpg` | Abstract | [Samuel Zeller, *Abstract spiral pattern*](https://commons.wikimedia.org/wiki/File:Abstract_spiral_pattern_(Unsplash).jpg) | CC0 1.0 tag; uploaded to Commons in May 2017 before Unsplash’s licence change. No separate licence-review confirmation was found. |
| `minimal.jpg` | Minimal | [NPS Photo, *Hazy day in the dune field*, White Sands National Park](https://commons.wikimedia.org/wiki/File:Hazy_day_in_the_dune_field_(fe918074-155d-451f-67c3-9ae106cb2164).JPG) | Public domain (`PD-USGov-NPS`) |

CC0 and public-domain works require no attribution; this record is kept for
provenance. The Abstract entry is the least independently verified of the
four, as noted above.

Covers for user-created collections are not bundled. They are a stable
snapshot of the first wallpaper thumbnail fetched for that query when the
collection is bookmarked.

## Cover palettes

Each collection also stores a small `coverColors` palette so Search's *By
tag* row can tint a selected cover's stroke with its own artwork instead of a
fixed theme colour. It is presentation metadata and is deliberately separate
from `colors`, which is part of the saved search.

- **User collections:** the palette of the wallpaper that supplied the cover,
  taken from that listing entry's `colors` field when the collection is
  bookmarked. No extra request and no image decoding: the snapshot and its
  palette always describe the same wallpaper, are capped at five normalized
  `#RRGGBB` values, and are never refreshed by sorting or reopening.
- **Legacy rows:** a cover saved before the field existed gains its palette on
  a grid visit that returns that same cover — the stored image is never
  replaced. A cover that never reappears keeps an empty palette, and the card
  falls back to the theme's neutral outline.
- **Curated seeds:** measured from the bundled JPEGs above (400×400 decode,
  histogram on the top four bits per channel, mean RGB of the four fullest
  buckets), recorded in `seedCoverColors`. Installs that predate the field read
  those constants instead of being rewritten.

Selection strokes are derived from a palette entry at a moderate tone — pale
or deep depending on the artwork, and never the text-grade 4.5:1 tone used for
labels. The stroke is also theme-aware: light mode brightens pale strokes and
keeps deep strokes closer to the artwork, while dark mode keeps pale strokes as
they were and deepens deep strokes. A 3:1 contrast floor is only a minimum.
