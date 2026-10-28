# Contributing to hostblock

Thanks for considering a contribution. By participating, you agree to abide by
the [Code of Conduct](CODE_OF_CONDUCT.md).

## What will not be merged

hostblock is append-only on purpose. Pull requests that add a `remove` or
`unblock` verb, a list or count in the menu bar app, or any other way to undo a
block from the UI or CLI will be closed. Ideas that make the tamper reversion
stronger or the limitations smaller are very welcome.

## Reporting bugs

Open an issue with the bug report form. Include your macOS version, the output of
`hostblock status`, and the relevant lines of `/Library/Logs/hostblock/hostblockd.log`.
Do not paste your blocklist; it is not needed.

For **security issues**, do not open a public issue. See [SECURITY.md](SECURITY.md).

## Suggesting features

Open a feature request describing the use case before writing code.

## Development setup

You need macOS and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/esoteric-frog/hostblock.git
cd hostblock
./test.sh     # runs the real daemon + CLI in a sandbox, no root needed
./build.sh    # compiles the menu bar app into build/
```

`test.sh` sets `HOSTBLOCK_TEST_ROOT` to a temp directory under `/tmp`, which
relocates every path and drops the root check. Keep that path short: the AF_UNIX
socket path limit on macOS is 104 bytes. Never test against the real
`/etc/hosts`.

The daemon and CLI are Python 3.9 standard library only (the Apple Command Line
Tools shim). Do not add third-party packages.

## Branching and commits

- Work off **`main`**. Branches: `<type>/<short-name>`, e.g. `fix/kqueue-rearm`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `test:`, `chore:`.

## Pull requests

1. `./test.sh` passes and `./build.sh` compiles.
2. CI is green.
3. User-facing changes update the README and `CHANGELOG.md` under `[Unreleased]`.
4. New daemon behaviour gets a check in `test.sh`.

## License of contributions

By submitting a pull request, you agree your contribution is licensed under the
[MIT License](LICENSE).
