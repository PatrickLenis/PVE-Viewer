#!/bin/zsh
set -euo pipefail

APP_NAME="PVE Viewer"
PROJECT="PVEViewer.xcodeproj"
SCHEME="PVEViewer"
CONFIGURATION="Debug"
DERIVED_DATA=".build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

pkill -x "$APP_NAME" 2>/dev/null || true

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

/usr/bin/open -n "$APP_PATH"

if [[ "${1:-}" == "--verify" ]]; then
  sleep 2
  pgrep -x "$APP_NAME" >/dev/null
fi
