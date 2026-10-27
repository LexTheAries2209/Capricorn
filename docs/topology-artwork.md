# Topology Host Artwork

The two keyboard views are original Apple product renders from the 2023
MacBook Pro Apple Store gallery. Product imagery is copyright Apple Inc.;
the source-code GPL notice does not apply to these images.

Sources retrieved on 2026-10-28:

- 14-inch keyboard view:
  https://store.storeimages.cdn-apple.com/4982/as-images.apple.com/is/mbp14-silver-gallery2-202301?wid=1000&hei=900&fmt=png-alpha
- 16-inch keyboard view:
  https://store.storeimages.cdn-apple.com/4982/as-images.apple.com/is/mbp16-silver-gallery2-202301?wid=1000&hei=900&fmt=png-alpha
- Corresponding side-profile references:
  https://store.storeimages.cdn-apple.com/4982/as-images.apple.com/is/mbp14-silver-gallery4-202301?wid=1000&hei=900&fmt=png-alpha
  https://store.storeimages.cdn-apple.com/4982/as-images.apple.com/is/mbp16-silver-gallery4-202301?wid=1000&hei=900&fmt=png-alpha

Only the studio backdrop and padding were removed. The laptop pixels,
proportions, and perspective were preserved. The matching 2021/2023 chassis
use the same keyboard artwork; other Mac families retain native macOS artwork.
There are no network requests at runtime.

At the source resolution of 1000 x 900, the 14-inch crop is (96, 225, 809, 479)
and the chassis is (171, 238, 658, 466). The 16-inch crop is
(54, 196, 893, 535) and the chassis is (127, 209, 747, 522). Coordinates use
a top-left origin. For the 2021 chassis, sockets 1 and 3 share the keyboard
number row, while socket 2 aligns with QWER. The corresponding source-image
row centers are Y=336/376 for 14-inch and Y=324/364 for 16-inch. Socket positions
are projections onto the chassis edge, not visible holes in the top view.

`StorageHostArtworkGeometry` owns the aspect-fit transform used by the
numbered markers and connection-line origins. The actual built-in socket
number is still read from IOKit, and physical side mapping remains restricted
to verified boards.
