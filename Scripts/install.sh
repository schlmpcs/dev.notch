#!/bin/sh
#
# Build Release, replace /Applications/boringNotch.app, restart it.
#
# Run by hand, or automatically by .git/hooks/pre-push. The installed copy is
# what runs day to day; never launch the DerivedData build directly or you end
# up with two notches drawing over each other.
#
set -e

cd "$(dirname "$0")/.."
APP=/Applications/boringNotch.app
PROJECT="-project boringNotch.xcodeproj -scheme boringNotch -configuration Release"

# shellcheck disable=SC2086
xcodebuild $PROJECT -jobs 2 build

# The DerivedData directory carries a per-machine hash, so ask xcodebuild where
# it put the app rather than hardcoding a path that breaks on another checkout.
# shellcheck disable=SC2086
BUILT=$(xcodebuild $PROJECT -showBuildSettings 2>/dev/null |
        awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')
[ -d "$BUILT/boringNotch.app" ] || { echo "no build product at $BUILT" >&2; exit 1; }

# The app ignores SIGTERM, so kill outright, and wait for the process to really
# be gone before swapping the bundle: open(1) reactivates a still-dying instance
# instead of launching the new build, which silently leaves the old one running.
# Nothing is lost to SIGKILL - settings and shelf items are written on change,
# not on quit.
pkill -9 -f "$APP/Contents/MacOS/boringNotch" || true
while pgrep -f "$APP/Contents/MacOS/boringNotch" >/dev/null; do sleep 0.2; done

if [ -d "$APP" ]; then
  BACKUP=$(mktemp -d "${TMPDIR:-/tmp/}boringnotch-backup.XXXXXX")
  mv "$APP" "$BACKUP/boringNotch.app"
  echo "previous app preserved at $BACKUP/boringNotch.app"
fi
ditto "$BUILT/boringNotch.app" "$APP"   # ditto, not cp: preserves the code signature
open -a "$APP"

echo "installed $(date '+%H:%M:%S')"
