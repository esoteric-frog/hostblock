#!/bin/bash
# Privileged half of the install (macOS). Run via sudo.
# Installs the daemon, the CLI, the menu bar binary, and the LaunchDaemon.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB=/usr/local/libexec/hostblock
STATE="/Library/Application Support/hostblock"
LOGS=/Library/Logs/hostblock
LABEL=io.github.esoteric-frog.hostblockd
SOCK=/var/run/hostblock/sock

# BSD install has no -D: make directories first.
install -d -o root -g wheel -m 755 /usr/local/bin "$LIB" "$LIB/src" "$STATE" "$LOGS"
install -o root -g wheel -m 755 "$SRC/daemon/hostblockd"        "$LIB/hostblockd"
install -o root -g wheel -m 755 "$SRC/cli/hostblock"            /usr/local/bin/hostblock
install -o root -g wheel -m 755 "$SRC/build/hostblock-menubar"  "$LIB/hostblock-menubar"
install -o root -g wheel -m 644 "$SRC/launchd/$LABEL.plist"     "/Library/LaunchDaemons/$LABEL.plist"

# Keep a root-owned copy of the source for later reference.
rsync -a --delete --exclude build "$SRC/" "$LIB/src/"
chown -R root:wheel "$LIB/src"

# One-time snapshot of the pristine file, before hostblockd ever touches it.
[ -f /private/etc/hosts.pre-hostblock ] || cp -p /private/etc/hosts /private/etc/hosts.pre-hostblock

# (Re)load the daemon. `launchctl load` is deprecated; bootstrap/bootout is the modern pair.
launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "$SOCK"          # stale socket from the old daemon; wait for the NEW one below
launchctl bootstrap system "/Library/LaunchDaemons/$LABEL.plist"
launchctl enable "system/$LABEL"

for i in $(seq 1 60); do [ -S "$SOCK" ] && break; sleep 0.5; done
launchctl print "system/$LABEL" | grep -E "state =|pid =" || true
[ -S "$SOCK" ] && echo "daemon socket up" || { echo "daemon socket missing; see $LOGS/hostblockd.log" >&2; tail -20 "$LOGS/hostblockd.log" >&2; exit 1; }
