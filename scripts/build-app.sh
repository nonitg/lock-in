#!/bin/bash
# Builds dist/LockIn.app (release, signed). `--install` also replaces /Applications/LockIn.app and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
APP=dist/LockIn.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp .build/arm64-apple-macosx/release/LockIn "$APP/Contents/MacOS/LockIn"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/com.nonit.lockin.agent.plist "$APP/Contents/Library/LaunchAgents/"
# Stable signing identity so macOS permissions (Automation, notifications) survive rebuilds.
codesign --force --sign "${LOCKIN_SIGN_IDENTITY:-Apple Development}" "$APP"
echo "built $APP"

[[ "${1:-}" == "--install" ]] || exit 0
# Quit via URL scheme (exit 0) so the login agent doesn't respawn the old binary mid-copy.
if pgrep -x LockIn >/dev/null; then
  open -g "lockin://quit"
  for _ in {1..20}; do pgrep -x LockIn >/dev/null || break; sleep 0.25; done
fi
rm -rf /Applications/LockIn.app
cp -R "$APP" /Applications/LockIn.app
# Prefer launching through the login agent so launchd owns the process (crash -> relaunch).
launchctl kickstart "gui/$(id -u)/com.nonit.lockin.agent" 2>/dev/null || open -g /Applications/LockIn.app
echo "installed /Applications/LockIn.app"
