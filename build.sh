#!/bin/zsh
# Builds Rev Widget, installs it to ~/Applications and launches it.
# Free: signs with your Personal Team (a free Apple ID added in Xcode > Settings > Accounts).
set -euo pipefail
cd "${0:A:h}"

TEAM="${DEVELOPMENT_TEAM:-}"
if [[ -z "$TEAM" && -f Local.xcconfig ]]; then
  TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' Local.xcconfig)
fi

# Fall back to the first team Xcode knows about (your free Personal Team).
if [[ -z "$TEAM" ]]; then
  TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | sed -n 's/.*teamID = \([A-Z0-9]\{10\}\);.*/\1/p' | head -1 || true)
fi
if [[ -z "$TEAM" ]]; then
  echo "No signing team found."
  echo "Open Xcode > Settings > Accounts, click +, sign in with your Apple ID (free), then run ./build.sh again."
  exit 1
fi

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --quiet

echo "Signing with team $TEAM"
APP="build/Build/Products/Release/Rev Widget.app"
rm -rf "$APP"
build() {
  xcodebuild -project RevWidget.xcodeproj -scheme RevWidget -configuration Release \
    -derivedDataPath build DEVELOPMENT_TEAM="$TEAM" "$@" build 2>&1 | grep -E "error|BUILD" || true
}
# Automatic signing first (Xcode makes the free certificate if needed).
build CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates
if [[ ! -d "$APP" ]]; then
  # macOS doesn't need a provisioning profile for these entitlements, so sign directly with the certificate.
  echo "Retrying with your Apple Development certificate and no profile..."
  build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" PROVISIONING_PROFILE_SPECIFIER=
fi
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }

pkill -x "Rev Widget" 2>/dev/null || true
mkdir -p ~/Applications
rm -rf ~/Applications/"Rev Widget.app"
cp -R "$APP" ~/Applications/
open ~/Applications/"Rev Widget.app"
echo "Installed ~/Applications/Rev Widget.app. Log: ~/Library/Logs/RevWidget.log"
