#!/bin/sh
# Build the pinned smartmontools source for both macOS architectures.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE_ARCHIVE="$REPO_ROOT/ThirdParty/smartmontools/smartmontools-7.5.tar.gz"
EXPECTED_SHA256=ef721052992f2f6a57b369da625abd8dc30417e7a1e7234857619f8fc43fd4bc
OUTPUT_ROOT="$REPO_ROOT/ThirdParty/smartmontools/build"
WORK_ROOT=$(mktemp -d /private/tmp/capricorn-smartctl-build.XXXXXX)

if [ ! -f "$SOURCE_ARCHIVE" ]; then
    echo "Missing source archive: $SOURCE_ARCHIVE" >&2
    exit 1
fi

ACTUAL_SHA256=$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{print $1}')
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo "smartmontools source checksum mismatch" >&2
    echo "expected: $EXPECTED_SHA256" >&2
    echo "actual:   $ACTUAL_SHA256" >&2
    exit 1
fi

for tool in autoconf autoheader automake aclocal; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing build prerequisite: $tool" >&2
        exit 1
    fi
done

tar -xzf "$SOURCE_ARCHIVE" -C "$WORK_ROOT"
SOURCE_ROOT="$WORK_ROOT/smartmontools-RELEASE_7_5/smartmontools"
cd "$SOURCE_ROOT"
AUTOMAKE=${AUTOMAKE:-automake-1.18} ./autogen.sh

mkdir -p "$OUTPUT_ROOT"
for architecture in arm64 x86_64; do
    BUILD_ROOT="$WORK_ROOT/build-$architecture"
    mkdir -p "$BUILD_ROOT"
    cd "$BUILD_ROOT"
    CFLAGS="-arch $architecture -mmacosx-version-min=14.0 ${CFLAGS:-}" \
    CXXFLAGS="-arch $architecture -mmacosx-version-min=14.0 ${CXXFLAGS:-}" \
    LDFLAGS="-arch $architecture ${LDFLAGS:-}" \
        "$SOURCE_ROOT/configure" \
        --disable-dependency-tracking \
        --prefix="$BUILD_ROOT/install" \
        --with-drivedbdir=no \
        --with-update-smart-drivedb=no
    make -j"$(sysctl -n hw.ncpu)" smartctl
    mkdir -p "$OUTPUT_ROOT/$architecture"
    install -m 755 smartctl "$OUTPUT_ROOT/$architecture/smartctl"
done

mkdir -p "$OUTPUT_ROOT/universal"
lipo -create \
    "$OUTPUT_ROOT/arm64/smartctl" \
    "$OUTPUT_ROOT/x86_64/smartctl" \
    -output "$OUTPUT_ROOT/universal/smartctl"
install -m 644 "$SOURCE_ROOT/drivedb.h" "$OUTPUT_ROOT/universal/drivedb.h"

echo "Built: $OUTPUT_ROOT/universal/smartctl"
echo "Architectures: $(lipo -archs "$OUTPUT_ROOT/universal/smartctl")"
