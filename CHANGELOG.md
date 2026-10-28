# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-28

### Added

- `hostblockd`: root LaunchDaemon (Python stdlib) that owns a fenced section of
  `/etc/hosts`, accepts only `add`, `list` and `status`, and restores the fence
  within about 150 ms of any edit, replace, truncate or delete (kqueue).
- `hostblock` CLI: `add`, `list`, `status` (and `status --json`).
- Menu bar app: plain shield, type a site, preview the exact `127.0.0.1` / `::1`
  lines, confirm. Never shows the blocklist.
- `test.sh`: sandboxed end-to-end test via `HOSTBLOCK_TEST_ROOT`, no root needed.
- `build.sh`, `install.sh`, `install-root.sh` and launchd plists.

[Unreleased]: https://github.com/esoteric-frog/hostblock/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/esoteric-frog/hostblock/releases/tag/v0.1.0
