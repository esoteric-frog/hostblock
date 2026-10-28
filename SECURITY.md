# Security policy

hostblock runs a root daemon that rewrites `/etc/hosts` and listens on a local
Unix socket, so security reports are taken seriously.

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | yes |

## Reporting a vulnerability

Please do **not** open a public issue. Use GitHub private vulnerability
reporting: go to the **Security** tab of this repository and click
**Report a vulnerability**.

Include what you found, how to reproduce it, and the impact (for example: a
non-admin user can talk to the socket, a crafted request writes outside the
fenced section, or a way to remove an entry through the daemon).

You can expect a first reply within 7 days. This is a one-maintainer project, so
fixes are best effort; you will be credited in the release notes unless you ask
not to be.

## In scope

- `daemon/hostblockd`, `cli/hostblock`, `menubar/main.swift`
- The install scripts and the launchd plists

## Out of scope

The bypasses listed under **Limitations** in the README (DNS-over-HTTPS, VPNs,
direct IP access, an admin with root who edits the state file) are known and by
design.
