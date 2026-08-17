# mistral CLI

Standalone binaries for the `mistral` command-line tool.

This repository (`mistralai/cli`) hosts the compiled release assets only. The
source lives in the `mistralai/dashboard` monorepo under `ts/cli/mistral`, and
each release is built and published automatically from there.

This repository hosts `mistral` CLI releases exclusively. The installer fetches
the _latest_ release, so publishing any unrelated release here would break
installs.

## Install

While the repository is private, install with the GitHub CLI (`gh`), which uses
your existing GitHub authentication:

```sh
bash <(gh api -H "Accept: application/vnd.github.raw" repos/mistralai/cli/contents/install.sh)
```

The installer detects your platform, downloads the matching binary and
`checksums.txt` from the latest release, verifies the SHA-256 checksum, installs
to `~/.mistral/bin/mistral`, and prints PATH instructions if needed.

Override the install location with `MISTRAL_INSTALL_DIR`:

```sh
MISTRAL_INSTALL_DIR="$HOME/.local/bin" bash <(gh api -H "Accept: application/vnd.github.raw" repos/mistralai/cli/contents/install.sh)
```

## Upgrade

The installer always fetches the _latest_ release, so upgrading is the same
command as installing — re-run it and it overwrites the existing binary in
place:

```sh
bash <(gh api -H "Accept: application/vnd.github.raw" repos/mistralai/cli/contents/install.sh)
```

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
gh release download --repo mistralai/cli --pattern 'mistral-*' --pattern 'checksums.txt'
sha256sum -c checksums.txt        # Linux
shasum -a 256 -c checksums.txt    # macOS
```

`checksums.txt` catches incomplete or corrupted downloads. It ships in the same
release as the binaries, so it is not an independent guarantee against a
malicious publisher — publisher integrity rests on the private repo and your
`gh` authentication.

## Uninstall

```sh
rm -f ~/.mistral/bin/mistral
```

Then remove `~/.mistral/bin` from your PATH if you added it.
