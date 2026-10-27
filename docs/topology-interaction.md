# Topology Interaction

- `M` opens the shared storage topology.
- Pinch on the trackpad to magnify the graph; two-finger scrolling pans it.
- Drag a computer, controller, hub, or disk node to change its position.
  Connections follow the node, including the host's physical socket dots.
- `Z` clears manual positions, restores automatic arrangement, centers the
  graph, and fits it to the viewport. The fit button performs the same action.
- Clicking a disk still selects it in the sidebar and updates the inspector.
- USB port wrappers stay in the inspector instead of becoming graph nodes.
- Generic USB hub/port wrappers are folded into the direct dock branches;
  named docks and chip/controller hardware remain visible.
- Bare `Z` only applies on the topology page in the same window, outside
  editable text. Command-Z remains available to the normal responder chain.

SwiftUI owns node positions and selection. A scoped `NSScrollView` handles
native trackpad magnification and scrolling. Drag deltas use document
coordinates so their speed does not depend on magnification. Long USB chains
use individual vector connections instead of a single oversized canvas.

手势：双指捏合缩放，双指滚动平移；拖动节点调整位置。按 `Z` 重新整理并自适应显示。
