#!/bin/bash
# Builda, instala e roda o app no simulador. Uso:
#   ./scripts/run-sim.sh            # build + boot + install + launch
#   ./scripts/run-sim.sh shot NOME  # screenshot -> /tmp/ta-shots/NOME.png
set -e
cd "$(dirname "$0")/.."

SIM_NAME="iPhone 15 Pro"
SIM_OS="17.5"
BUNDLE_ID="com.ccypher.terapiaacolher"
UDID=$(xcrun simctl list devices "$SIM_OS" | grep "$SIM_NAME (" | head -1 | grep -oE '[A-F0-9-]{36}')

if [ "$1" = "shot" ]; then
  mkdir -p /tmp/ta-shots
  xcrun simctl io "$UDID" screenshot "/tmp/ta-shots/${2:-shot}.png"
  echo "/tmp/ta-shots/${2:-shot}.png"
  exit 0
fi

xcodegen generate > /dev/null
xcodebuild -project TerapiaAcolher.xcodeproj -scheme TerapiaAcolher \
  -destination "platform=iOS Simulator,name=$SIM_NAME,OS=$SIM_OS" \
  -derivedDataPath build build | tail -2

xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || xcrun simctl boot "$UDID"
open -a Simulator --background
APP_PATH="build/Build/Products/Debug-iphonesimulator/TerapiaAcolher.app"
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
echo "App rodando no simulador ($SIM_NAME)"
