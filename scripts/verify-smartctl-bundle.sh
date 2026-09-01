#!/bin/sh
# Verify the bundled executable before an app build or release audit.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SMARTCTL="$REPO_ROOT/Capricorn/Resources/Smartmontools/smartctl"
DRIVEDB="$REPO_ROOT/Capricorn/Resources/Smartmontools/drivedb.h"

if [ ! -x "$SMARTCTL" ]; then
    echo "Missing executable smartctl resource: $SMARTCTL" >&2
    exit 1
fi
if [ ! -s "$DRIVEDB" ]; then
    echo "Missing smartmontools drive database resource: $DRIVEDB" >&2
    exit 1
fi

ARCHITECTURES=$(lipo -archs "$SMARTCTL")
case " $ARCHITECTURES " in *" arm64 "*) ;; *)
    echo "smartctl must contain arm64 and x86_64 slices; found: $ARCHITECTURES" >&2
    exit 1
    ;; esac
case " $ARCHITECTURES " in *" x86_64 "*) ;; *)
    echo "smartctl must contain arm64 and x86_64 slices; found: $ARCHITECTURES" >&2
    exit 1
    ;; esac

VERSION=$(
    "$SMARTCTL" --version |
        sed -n '1s/^smartctl \([^ ]*\).*/\1/p'
)
if [ "$VERSION" != "7.5" ]; then
    echo "Expected smartctl 7.5; found: $VERSION" >&2
    exit 1
fi

echo "smartctl $VERSION ($ARCHITECTURES)"
echo "drive database: $DRIVEDB"
