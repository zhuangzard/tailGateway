#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/Applications/TailGateway.app"
SUPPORT_DIR="$HOME/Library/Application Support/TailGateway"
ENGINE_DIR="$SUPPORT_DIR/Engine"
SUPPORT_BIN_DIR="$SUPPORT_DIR/bin"

cd "$ROOT"
swift build -c release

mkdir -p "$BIN_DIR"
install -m 0755 "$ROOT/.build/release/TailGateway" "$BIN_DIR/TailGateway"

mkdir -p "$ENGINE_DIR" "$SUPPORT_BIN_DIR" "$SUPPORT_DIR/State" "$SUPPORT_DIR/Archive"
install -m 0755 "$ROOT/Support/bin/tailgatewayctl" "$SUPPORT_BIN_DIR/tailgatewayctl"
install -m 0755 "$ROOT/Support/bin/tailgateway-auto" "$SUPPORT_BIN_DIR/tailgateway-auto"

for script in "$ROOT"/Support/Engine/*.zsh; do
  install -m 0755 "$script" "$ENGINE_DIR/${script:t}"
done

for data in "$ROOT"/Support/Engine/*.txt; do
  target="$ENGINE_DIR/${data:t}"
  if [[ ! -e "$target" ]]; then
    install -m 0644 "$data" "$target"
  fi
done

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
install -m 0755 "$ROOT/.build/release/TailGateway" "$APP_DIR/Contents/MacOS/TailGateway"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TailGateway</string>
  <key>CFBundleIdentifier</key>
  <string>com.taisen.tailgateway</string>
  <key>CFBundleName</key>
  <string>TailGateway</string>
  <key>CFBundleDisplayName</key>
  <string>TailGateway</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Installed TailGateway to $BIN_DIR/TailGateway"
echo "Installed app bundle to $APP_DIR"
echo "Installed TailGateway support files to $SUPPORT_DIR"
echo "Run it with:"
echo "  TailGateway"
echo "or:"
echo "  open $APP_DIR"
