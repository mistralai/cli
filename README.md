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
curl -fsSL https://mistral.ai/cli/install.sh | bash
```

The installer detects your platform, downloads the matching binary and
`checksums.txt` from the latest release, verifies the SHA-256 checksum, installs
to `~/.mistral/bin/mistral`, and prints PATH instructions if needed.

`mistral apps` needs `bun`. If `bun` is not on your PATH, the installer asks whether to run the official bun installer, pinned to the bun version the CLI is built with. If you decline, or no terminal is attached, it prints the bun install command instead.

`MISTRAL_INSTALL_BUN=0` never installs bun and only prints the command. To install bun without asking, for example in CI or from a coding agent, set `MISTRAL_INSTALL_BUN=1`:

```sh
curl -fsSL https://raw.githubusercontent.com/mistralai/cli/main/install.sh | MISTRAL_INSTALL_BUN=1 bash
```

Override the install location with `MISTRAL_INSTALL_DIR`:

```sh
curl -fsSL https://mistral.ai/cli/install.sh | MISTRAL_INSTALL_DIR="$HOME/.local/bin" bash
```

Pin a specific release with `MISTRAL_VERSION` (plain `X.Y.Z`); unset installs
the latest:

```sh
curl -fsSL https://mistral.ai/cli/install.sh | MISTRAL_VERSION=0.2.0 bash
```

## Upgrade

Upgrading is the same command as installing — re-run it and it overwrites the
existing binary in place:

```sh
curl -fsSL https://mistral.ai/cli/install.sh | bash
```

To roll back to a known-good release, re-run it with `MISTRAL_VERSION` set.
Releases are immutable, so a bad version is never republished under the same
number.

## Shell completions

The CLI prints a static completion script for your shell with `--completions`. The installer prints the command for your current shell when it finishes, but does not add completions to your shell profile itself. The bash line runs the installed CLI each time a shell starts, so it stays current; re-run the zsh or fish command after an upgrade so new commands complete.

Bash: add this line to `~/.bashrc`:

```sh
command -v mistral >/dev/null && eval "$(mistral --completions bash)"
```

Zsh: write the script to a directory on your `fpath`, then add that directory in `~/.zshrc` before `compinit` runs:

```sh
mkdir -p ~/.zsh/completions && mistral --completions zsh > ~/.zsh/completions/_mistral
```

```sh
fpath=(~/.zsh/completions $fpath)
```

If your `~/.zshrc` doesn't run `compinit` already (plain zsh, including the macOS default, doesn't), add this after the `fpath` line:

```sh
autoload -Uz compinit && compinit
```

Fish:

```sh
mkdir -p ~/.config/fish/completions && mistral --completions fish > ~/.config/fish/completions/mistral.fish
```

Open a new shell for the completions to load.

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

Run the installer in uninstall mode. If you installed to a custom directory,
pass the same `MISTRAL_INSTALL_DIR` you used then (it defaults to
`~/.mistral/bin`):

```sh
curl -fsSL https://mistral.ai/cli/install.sh | MISTRAL_UNINSTALL=1 bash
```

In order, it:

1. Runs `mistral logout`, which revokes your session and deletes the
   `mistral-cli` keychain item. This comes first because it needs the binary
   and the config directory. If it fails or takes a while offline (up to a
   minute), the uninstall carries on.
2. Removes the `mistral` binary.
3. Removes the `# >>> Mistral >>>` block from `~/.zshrc` (or
   `$ZDOTDIR/.zshrc`), `~/.bashrc`, `~/.bash_profile` and
   `~/.config/fish/config.fish`.
4. Deletes the completion files `~/.zsh/completions/_mistral` and
   `~/.config/fish/completions/mistral.fish`.
5. Asks before deleting the config directory (`$MISTRAL_CONFIG_DIR`, else
   `$XDG_CONFIG_HOME/mistral`, else `~/.config/mistral`). It holds your API
   key, feature-flag overrides, and caches. The default answer is no, and it
   keeps the directory when no terminal is attached, printing the `rm -rf`
   command instead. It never deletes your home directory or a directory
   containing it, and leaves a symbolic link in place.

It then lists, without deleting, what other tools or your own data may depend
on:

- bun in `~/.bun`, if the installer offered it, and any lines bun's installer
  added to your shell profile.
- `mistral apps dev` Postgres containers and volumes named `mistral-dev-*`. The
  volumes hold your local database data.
- Pulled skills and prompts in `~/.mistral/registry`.
- Remaining lines in your shell profile that mention the install directory,
  such as the bash completion line.
- Anything else left in the install directory.

Open a new shell afterwards. Running the command again is safe.

### By hand

Older installers ignore `MISTRAL_UNINSTALL`; if the one-liner starts
downloading, press Ctrl-C and use these steps instead:

```sh
mistral logout
rm -f ~/.mistral/bin/mistral
rm -f ~/.zsh/completions/_mistral ~/.config/fish/completions/mistral.fish
rm -rf ~/.config/mistral
```

Then delete the lines from `# >>> Mistral >>>` to `# <<< Mistral <<<` in your
shell profile (`~/.zshrc`, `~/.bashrc`, `~/.bash_profile` or
`~/.config/fish/config.fish`), and the `mistral --completions bash` line if you
added it to `~/.bashrc`. If you set `MISTRAL_INSTALL_DIR` or
`MISTRAL_CONFIG_DIR`, use those paths instead.

Optionally, remove the rest:

```sh
docker ps -a --filter 'name=^mistral-dev-'        # list, then: docker rm <container>
docker volume ls --filter 'name=^mistral-dev-'    # list, then: docker volume rm <volume>
rm -rf ~/.mistral/registry
rm -rf ~/.bun    # only if nothing else uses bun
```
