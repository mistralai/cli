# mistral CLI

Standalone binaries for the `mistral` command-line tool.

This repository (`mistralai/cli`) hosts the compiled release assets only. The
source lives in the `mistralai/dashboard` monorepo under `ts/cli/mistral`, and
each release is built and published automatically from there.

This repository hosts `mistral` CLI releases exclusively. The installer fetches
the _latest_ release by default, so publishing any unrelated release here would
break installs.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/mistralai/cli/main/install.sh | bash
```

The installer detects your platform, downloads the matching binary and
`checksums.txt` from the latest release, verifies the SHA-256 checksum, installs
to `~/.mistral/bin/mistral`, and prints PATH instructions if needed.

Override the install location with `MISTRAL_INSTALL_DIR`:

```sh
curl -fsSL https://raw.githubusercontent.com/mistralai/cli/main/install.sh | MISTRAL_INSTALL_DIR="$HOME/.local/bin" bash
```

Pin a specific release with `MISTRAL_VERSION` (plain `X.Y.Z`); unset installs
the latest:

```sh
curl -fsSL https://raw.githubusercontent.com/mistralai/cli/main/install.sh | MISTRAL_VERSION=0.2.0 bash
```

## Upgrade

Upgrading is the same command as installing — re-run it and it overwrites the
existing binary in place:

```sh
curl -fsSL https://raw.githubusercontent.com/mistralai/cli/main/install.sh | bash
```

To roll back to a known-good release, re-run it with `MISTRAL_VERSION` set.
Releases are immutable, so a bad version is never republished under the same
number.

## Supported platforms

| OS    | Architecture    | Asset                  |
| ----- | --------------- | ---------------------- |
| macOS | Apple Silicon   | `mistral-darwin-arm64` |
| macOS | Intel           | `mistral-darwin-x64`   |
| Linux | x86_64          | `mistral-linux-x64`    |
| Linux | arm64 / aarch64 | `mistral-linux-arm64`  |

## Verify a download manually

Each release ships a `checksums.txt` with a SHA-256 line per binary:

```sh
base=https://github.com/mistralai/cli/releases/latest/download
curl -fsSLO "$base/mistral-darwin-arm64"   # your platform's asset
curl -fsSLO "$base/checksums.txt"
sha256sum --ignore-missing -c checksums.txt      # Linux
shasum -a 256 --ignore-missing -c checksums.txt  # macOS
```

`checksums.txt` catches incomplete or corrupted downloads. It ships in the same
release as the binaries, so it is not an independent guarantee against a
malicious publisher — publisher integrity rests on write access to the release
repository.

## Uninstall

```sh
rm -f ~/.mistral/bin/mistral
```

Then remove `~/.mistral/bin` from your PATH if you added it.
