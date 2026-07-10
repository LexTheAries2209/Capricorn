#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
DERIVED_DATA="$ROOT_DIR/DerivedData"
CONFIGURATION="Debug"
SHOW_LOGS=0
TELEMETRY=0
VERIFY=0

for argument in "$@"; do
    case "$argument" in
        --debug) CONFIGURATION="Debug" ;;
        --logs) SHOW_LOGS=1 ;;
        --telemetry) TELEMETRY=1 ;;
        --verify) VERIFY=1 ;;
        *)
            print -u2 "Unknown option: $argument"
            exit 2
            ;;
    esac
done

pkill -x Capricorn 2>/dev/null || true

xcodebuild build \
    -project "$ROOT_DIR/Capricorn.xcodeproj" \
    -scheme Capricorn \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Capricorn.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/Capricorn"

if [[ ! -x "$EXECUTABLE" ]]; then
    print -u2 "Built application executable was not found."
    exit 1
fi

if (( TELEMETRY )); then
    CAPRICORN_TELEMETRY=1 "$EXECUTABLE" >/dev/null 2>&1 &
else
    open "$APP_PATH"
fi

if (( VERIFY )); then
    for _ in {1..50}; do
        if pgrep -x Capricorn >/dev/null; then
            print "Capricorn launched successfully."
            break
        fi
        sleep 0.1
    done
    if ! pgrep -x Capricorn >/dev/null; then
        print -u2 "Capricorn did not remain running after launch."
        exit 1
    fi
fi

if (( SHOW_LOGS )); then
    log stream --style compact --predicate 'subsystem == "lex.Capricorn"'
fi
