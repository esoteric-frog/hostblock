#!/bin/bash
# User half of the install (macOS): runs the root half, then installs the
# menu bar LaunchAgent for the current user. Safe to re-run.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT=io.github.esoteric-frog.hostblock-menubar
UID_NUM="$(id -u)"

echo "==> root components (sudo)"
sudo "$SRC/install-root.sh"

echo "==> menu bar agent"
mkdir -p "$HOME/Library/LaunchAgents"
cp -f "$SRC/launchd/$AGENT.plist" "$HOME/Library/LaunchAgents/$AGENT.plist"
launchctl bootout "gui/$UID_NUM/$AGENT" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$HOME/Library/LaunchAgents/$AGENT.plist"
launchctl enable "gui/$UID_NUM/$AGENT"
sleep 1
launchctl print "gui/$UID_NUM/$AGENT" | grep -E "state =|pid =" || true

echo
echo "done. Try:  hostblock status"
echo "The shield icon is in the menu bar (top right)."
