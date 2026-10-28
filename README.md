# hostblock (macOS port)

An append-only website blocker with a menu bar shield. Click the shield, type a
site, confirm, and it is routed to `127.0.0.1` and `::1` in `/etc/hosts` for good.

Ported from the Linux/Omarchy version on 2026-09-08. Same four commitments:

1. **Append-only at the protocol level.** The daemon implements `add`, `list`,
   `status` and nothing else. There is no `remove` verb.
2. **Tamper reversion.** A root daemon watches `/private/etc` with kqueue and
   restores its fenced section within ~150 ms of any edit, replace, truncate or
   delete. Everything outside the fence is left alone.
3. **The GUI never shows what is blocked.** Plain shield, no count, tooltip
   never names a site, no list in the panel, and the panel never requests the
   blocklist. `hostblock list` in a terminal is the only place it is shown.
4. **Confirm before every add**, with the exact lines previewed.

## Use

From the menu bar: click the shield, type a domain, press Return, confirm.

From a terminal:

```sh
hostblock add reddit.com          # also blocks www.reddit.com, on 127.0.0.1 and ::1
hostblock add https://x.com/home  # pasted URLs are fine
hostblock list                    # the only place blocked sites are shown
hostblock status
```

Requires membership in the `admin` group (the control socket is `0660 root:admin`).

## What changed from Linux

| Linux | macOS |
| --- | --- |
| inotify on `/etc` | kqueue `EVFILT_VNODE` on the `/private/etc` directory AND on the current hosts inode (re-armed after every event) |
| systemd unit with sandboxing | `LaunchDaemon` (`launchctl bootstrap system`); the systemd hardening has no launchd equivalent and is simply gone |
| `resolvectl flush-caches` | `dscacheutil -flushcache; killall -HUP mDNSResponder` |
| `SO_PEERCRED` | `getpeereid(2)` via ctypes |
| `wheel` group | `admin` group |
| `/usr/bin/python3` (system) | `/usr/bin/python3` (Apple Command Line Tools shim, root-owned, Python 3.9) |
| Quickshell QML bar widget | Swift `NSStatusItem` + `NSPopover` app, run by a per-user `LaunchAgent` |
| GNU `install -D` | BSD `install -d` + `install -m` |

`HOSTBLOCK_TEST_ROOT` still relocates all paths and drops the root check, so the
watch/revert loop can be tested unprivileged. The socket path must stay short
(AF_UNIX limit is 104 bytes on macOS).

## Limitations

- **No wildcards.** `/etc/hosts` matches exact names.
- **`127.0.0.1` vs `0.0.0.0`.** A local webserver on port 80 will show its page.
- **Does not stop** direct-IP access, a VPN or proxy, a browser using
  DNS-over-HTTPS / secure DNS that skips the system resolver, or your phone. It
  does apply to private windows: it is system-level.
- **Open tabs keep working** until reloaded; browsers cache DNS themselves.
- **`.local` names** are Bonjour names on macOS and are rejected at input.
- **Screen Time** also blocks websites, but its limits are removable in a few
  clicks by the person who set them. That is the property this tool removes.
- Some VPN clients rewrite `/etc/hosts`; the daemon will fight them and the
  audit log is where that shows up.

## Undoing a block

There is no supported way from the UI or CLI. That is the feature. It takes
root, stopping the daemon, and hand-editing the daemon's JSON state, then
starting the daemon again. This is friction, not a lock.
