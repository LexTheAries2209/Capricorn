#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
REVIEW_DIR="$ROOT_DIR/DerivedData/HostPortReview"
APP_PATH="$REVIEW_DIR/Capricorn Port Review.app"
RESOURCES="$APP_PATH/Contents/Resources"
mkdir -p "$APP_PATH/Contents/MacOS" "$RESOURCES"
cp "$ROOT_DIR/script/fixtures/HostPortReview-Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/script/fixtures/host-port-review.json" "$RESOURCES/models.json"
cp "$ROOT_DIR/script/fixtures/host-port-review-additional.json" "$RESOURCES/additional-models.json"
cp "$ROOT_DIR/Capricorn/Assets.xcassets/MacBookPro14Top2023.imageset/macbook-pro-14-top.png" "$RESOURCES/mbp14-top.png"
cp "$ROOT_DIR/Capricorn/Assets.xcassets/MacBookPro16Top2023.imageset/macbook-pro-16-top.png" "$RESOURCES/mbp16-top.png"

swiftc -parse-as-library \
    "$ROOT_DIR/script/render_host_port_review.swift" \
    "$ROOT_DIR/Capricorn/Services/Inventory/StorageHostArtworkGeometry.swift" \
    "$ROOT_DIR/Capricorn/Services/Inventory/StorageHostPorts.swift" \
    "$ROOT_DIR/Capricorn/Services/Inventory/StorageHostArtwork.swift" \
    "$ROOT_DIR/Capricorn/Features/ConnectionTopology/StorageHostArtworkView.swift" \
    "$ROOT_DIR/Capricorn/Features/ConnectionTopology/TopologyConnectionLine.swift" \
    -framework AppKit -framework SwiftUI -framework IOKit \
    -o "$APP_PATH/Contents/MacOS/HostPortReview"

if (( ${@[(Ie)--render-only]} )); then
    "$APP_PATH/Contents/MacOS/HostPortReview" "$@"
else
    open -n "$APP_PATH" --args "$@"
fi
