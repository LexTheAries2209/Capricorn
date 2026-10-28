# Host Port Review

Run `./script/preview_host_ports.sh` to open five independent native review
windows. `--render-only` exports PNGs without opening windows. Build products,
downloaded official artwork, exports, and status are under
`DerivedData/HostPortReview/`.

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
and checks explicit side/rear markers against dark socket pixels. Inspect the
exported PNGs to verify cropping, aspect ratio, and overlay alignment. This pixel
check alone does not establish the correspondence to macOS registry port IDs.

Official image URLs and specification links are retained per model in
`host-port-review.json`. Downloads happen only in this developer preview tool,
once per local asset; Capricorn's normal topology screen is unchanged.
