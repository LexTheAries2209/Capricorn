# Host Port Review

Run `./script/preview_host_ports.sh` to open five independent native review
windows. `--render-only` exports PNGs without opening windows. Build products,
downloaded official artwork, exports, and status are under
`DerivedData/HostPortReview/`.

Run `./script/preview_host_ports.sh --additional` for the second review batch
without reopening the previously accepted MacBook previews. Combine this with
`--render-only` to validate and export before opening windows. The native Window
menu lists each review window.

The fixture identifies a specific generation for every family. It does not
change the production model whitelist or infer IOKit port numbers:

- MacBook Air M2 (2022): left-side pair, projected onto the official top view.
- MacBook Pro 13 M1 (2020): left-side pair, projected onto the official top view.
- Mac mini M2 (2023): rear pair of Thunderbolt sockets and pair of USB-A sockets.
- Mac Studio M2 Max (2023): rear Thunderbolt/USB-A and front USB-C sockets.
- MacBook Pro 14 M2 Pro/Max (2023): uses the production
  `StorageHostArtworkGeometry.anchor` coordinates on the bundled official asset.

The Air and 13-inch Pro top views use a linear projection of socket depth from
official side views. These are visual candidates, not a measurement from CAD.
The 13-inch Pro fixture excludes four-port Intel models; the mini excludes the
four-Thunderbolt-port M2 Pro; the Studio identifies Max because Ultra has
different front-port capabilities.

Before opening windows, the renderer checks every marker against image bounds
and checks explicit side/rear markers against a neighborhood of dark socket
pixels, allowing for colored iMac connector tongues. Inspect the
exported PNGs to verify cropping, aspect ratio, and overlay alignment. This pixel
check alone does not establish the correspondence to macOS registry port IDs.

Official image URLs and specification links are retained per model in
`host-port-review.json`. Downloads happen only in this developer preview tool,
once per local asset; Capricorn's normal topology screen is unchanged.

## Additional Review Batch

The additional manifest covers:

- Mac mini M4 and M4 Pro (2024), separately: identical positions, different rear
  Thunderbolt generations.
- iMac M1, M3, and M4: two-port and four-port layouts per generation. The M1/M3
  four-port fixtures distinguish USB 3 from Thunderbolt; M4's four-port fixture
  has four Thunderbolt sockets.
- MacBook Pro 14 M3, 14 M3 Pro/Max, and 16 M3 Pro/Max: the base M3 has no
  right-hand Thunderbolt port. Top views use the accepted matching-size chassis
  templates; they do not enable production registry mappings.
- Three current-production desktop endpoint windows for mini, Studio, and iMac,
  each showing the host artwork without and with system-disk selection.

The endpoint previews compile the production `StorageHostArtwork`,
`StorageHostArtworkView`, and `TopologyConnectionLine` sources directly. Their
only localization substitute is the accessibility label for "This Mac". They
therefore show this computer's actual system device-model artwork, including its
fallback if macOS lacks a declared image. Product names in these fixtures are
explicit labels; a real host obtains its name from IOKit.

Desktop physical port mapping is still unverified in production. Those endpoint
windows retain the existing abstract node-center connection; selecting the
system disk highlights the host without creating an internal-disk node.

## Acceptance

On October 28, 2026, the user accepted the previously shown MacBook Air M2,
MacBook Pro 13 M1, and MacBook Pro 14 M2 chassis previews. This records visual
acceptance only; it does not establish the IOKit port numbering of other models.
The additional M3 MacBook and desktop previews remain pending user review.

## October 2026 Review Batch

Run `./script/preview_host_ports.sh --2026`, optionally with `--render-only`,
for the October 28, 2026 batch. Sources are linked in
`host-port-review-2026.json`:

- Mac mini M5 Pro and M6, as listed in Apple's 2026 specification. The front and
  rear reference artwork uses the same official enclosure view as the 2024
  fixture; capabilities come from the 2026 specification.
- iMac M6 two-port and four-port variants, using the current official port
  photographs from Apple's specification page.
- 14-inch MacBook Pro M6, using current official side photographs and the
  accepted matching-size keyboard template as a candidate top projection.
- Unknown-model handling, displaying the actual system-artwork lookup for
  Apple's published mini identifiers and a clearly named synthetic unknown ID.

These are visual review fixtures, not additional verified IOKit port layouts.
M6 iMac and MacBook Pro registry identifiers are not guessed. The old-coordinate
fallback in `StorageHostArtworkGeometry.anchor` has been removed: a socket
coordinate now requires both a verified board layout and a matching top-view
profile. Unverified hosts retain abstract connections.

For unlisted models, production artwork first uses a declared macOS device-model
type. If the local OS does not know that identifier, the existing generic desktop
computer symbol is shown, with blue selection coloring for the system disk.
An OS artwork entry is independent of physical socket mapping; it never grants
permission to reuse a different model's port coordinates.
