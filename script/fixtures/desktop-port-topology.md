# Desktop Port Topology

Run `./script/build_and_run.sh --review-desktop-topology --verify` to build
Capricorn and open seven Debug-only topology review windows. This is the actual
application view, with synthetic bridge/disk paths and explicit socket
assignments. Review assignments stay in memory and do not overwrite the user's
real assignments. PNG snapshots and the window count are exported to
`DerivedData/DesktopTopologyReview/`.

## Presentation

- Mini and Studio use official top photographs, front at the bottom and rear
  at the top. Rear-facing photographs are mirrored in X when projected onto
  this top view.
- iMac uses a cropped official rear photograph, with sockets at the lower-left
  of the back panel. The two-port variant removes the two unused openings using
  adjacent panel pixels; it is a derived diagram asset, not an unedited photo.
- Dots and lines use `StorageDesktopProfile.anchor`. Host-to-device lines have
  a short overlay above the artwork, so iMac lines are visible from the actual
  socket rather than disappearing under the opaque panel.
- Rear/front branches are laid out separately. Unassigned branches use a
  separate unresolved exit; they are not assigned an arbitrary socket.
- System disks remain excluded; selecting one highlights the host.

## Port Identity

`StorageHostPort.socketID` is a visual socket identity, separate from the
unverified built-in numeric ID that macOS reports. The desktop "Connection port"
menu assigns the selected path's shared root to a physical socket. All disks
downstream of that root use the same cable endpoint.

These confirmations are stored locally by host model, shared registry root, and
boot-session UUID. A reboot invalidates them, because registry IDs may be reused.
Returning to the unassigned/automatic entry removes the confirmation. The
application does not infer that a USB-C-shaped opening necessarily negotiates
Thunderbolt; link speeds continue to come from the actual disk path.

No automatic desktop registry-number mapping is claimed. Asahi's board
descriptions provide useful connector labels for some boards, but a mapping
between those controller indices and every macOS built-in port number has not
been field-verified.

## Official Artwork Sources

The preparer crops and masks these locally downloaded sources:

- `mini-top.jpg`: Apple Mac mini technical-specifications top photograph:
  `https://www.apple.com/v/mac-mini/specs/b/images/specs/size_top__fk2w78e5j662_large.jpg`
- `mini-classic-top.png`: Apple Mac mini guide top photograph:
  `https://ipcdn-web.apple.com/assets/v2/web/a992c2c7-71c3-443b-b455-935e265fc0a7`
- `studio-top.jpg`: Apple Mac Studio technical-specifications top photograph:
  `https://www.apple.com/v/mac-studio/specs/b/images/specs/size_and_weight_top__c38c13fpq4ae_large.jpg`
- `imac-color.jpg`: Apple iMac technical-specifications three-view photograph:
  `https://www.apple.com/v/imac/specs/c/images/specs/colors_blue__c0vwfnvu230i_large.jpg`

Use `swift script/prepare_desktop_artwork.swift <source-folder>
Capricorn/Assets.xcassets` to reproduce the cropped assets. The runtime uses
bundled PNGs and makes no network request.

Port source coordinates use the official side/rear references already linked
in `host-port-review-additional.json`; Studio references are in
`host-port-review.json`. The M6 iMac review uses an explicit synthetic model ID
and product name so that it can show the known rear-panel arrangement without
inventing a production model identifier.
