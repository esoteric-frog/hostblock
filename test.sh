#!/bin/bash
# Runs the real daemon and CLI in a sandbox (HOSTBLOCK_TEST_ROOT): no root, no
# change to the real /etc/hosts. Checks add, refusal, and tamper reversion.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT="$(mktemp -d /tmp/hb.XXXXXX)"     # short path: AF_UNIX socket limit is 104 bytes
export HOSTBLOCK_TEST_ROOT="$ROOT"
mkdir -p "$ROOT/etc"
printf '127.0.0.1\tlocalhost\n' > "$ROOT/etc/hosts"

python3 -u daemon/hostblockd > "$ROOT/daemon.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null; rm -rf "$ROOT"' EXIT
for _ in $(seq 1 50); do [ -S "$ROOT/run/sock" ] && break; sleep 0.1; done

fail() { echo "FAIL: $1"; cat "$ROOT/daemon.log"; exit 1; }
HOSTS="$ROOT/etc/hosts"

python3 cli/hostblock add https://example.com/page >/dev/null
grep -q $'127.0.0.1\twww.example.com' "$HOSTS" || fail "add did not write www.example.com"
grep -q $'::1\texample.com' "$HOSTS" || fail "add did not write the IPv6 line"
grep -q $'127.0.0.1\tlocalhost' "$HOSTS" || fail "lines outside the fence were lost"

python3 cli/hostblock add 203.0.113.7 2>/dev/null && fail "an IP address was accepted"
python3 cli/hostblock remove example.com 2>/dev/null && fail "a remove verb exists"

sed -i '' '/example.com/d' "$HOSTS"                     # tamper: edit in place
sleep 0.6
grep -q $'127.0.0.1\texample.com' "$HOSTS" || fail "edit was not reverted"

rm "$HOSTS"                                             # tamper: delete the file
sleep 0.6
grep -q $'127.0.0.1\texample.com' "$HOSTS" || fail "delete was not reverted"
grep -q $'127.0.0.1\tlocalhost' "$HOSTS" || fail "localhost was not restored"

python3 cli/hostblock status --json | grep -q '"hostsInSync": true' || fail "status not in sync"
echo "PASS: add, refuse, no remove, revert edit, revert delete"
