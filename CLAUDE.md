# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A chezmoi-based framework that restores the owner's working environment after they
reinstall an OS **by hand**: packages, dotfiles, desktop settings, system settings,
wallpapers, plus periodic "repository changed" notifications and capturing local changes
back into the repo. The single user-facing entry point is `dots`, a step-by-step TUI
(`scripts/unix/dots`, `scripts/windows/dots.ps1`) that previews and confirms every step.

Primary platforms: **Windows 11** and **CachyOS**. Planned: Arch Linux, Ubuntu desktop
(KDE), Ubuntu WSL, macOS, NixOS. Fedora is not supported (existing Fedora code is being removed).

**Read `docs/README.md` first**, then `docs/design.md` before changing behaviour.
Features are tagged `[Implemented]`, `[Planned: Pn]`, or `[Future]`; `docs/roadmap.md`
says what exists today. **If a document and a test disagree, the test wins** until the
roadmap phase that changes the behaviour is merged; update both in the same change.

## Commands

`just` and `make` expose identical recipes (`make help` lists them):

```bash
make validate          # syntax + lint + test + templates + secrets (everything CI runs except the PowerShell parse)
make test              # bats tests
make lint              # shellcheck + shfmt -d -i 2 -ci -bn scripts/unix tests .githooks
make templates         # ./tests/validate-templates.sh (renders chezmoi templates in a temp HOME)
make secrets           # gitleaks scan of the full Git history
make hooks             # enable .githooks/pre-commit (gitleaks on staged changes) for this clone
make preview           # chezmoi apply --dry-run --verbose
./scripts/unix/bootstrap.sh --dry-run   # safe preview of the full bootstrap
```

Run a single test file or test: `bats tests/common.bats`, or `bats tests/bootstrap.bats -f 'package dry-run'`.

Fix formatting with `shfmt -w -i 2 -ci -bn scripts/unix tests .githooks`. `tests/ownership.bats` requires `rg`; some tests skip when `chezmoi` is absent.

## Architecture (target, see docs/design.md)

Eight layers, all driven by chezmoi data:

| Layer | Owns |
|---|---|
| L0 `dots` | CLI/TUI (gum), orchestration, dry-run |
| L1 Identity | `gh auth`, Bitwarden templates and SSH agent |
| L2 Packages | `home/.chezmoidata/packages.yaml` manifest → paru / winget / Scoop |
| L3 Dotfiles | user chezmoi instance, source `home/` |
| L4 Desktop | KDE keys from `kde.yaml` via `kwriteconfig6`; Windows HKCU from `windows.yaml` |
| L5 System | system chezmoi instance, source `root/` (Linux); Windows HKLM, debloat, drivers |
| L6 Assets | private wallpaper repo (Git LFS) via `.chezmoiexternal`; fonts |
| L7 Sync | systemd user timer / Scheduled Task (notify only), `dots capture` |

Scripts read data with `chezmoi data --format json` + `jq` (Bash) or `ConvertFrom-Json`
(PowerShell). Do **not** create service/provider directories (`scripts/<service>/<os>.sh`).

## Layout and ownership boundaries

- `.chezmoiroot` contains `home`, so **`home/` is the user chezmoi source state** (`dot_*`, `private_*`, `empty_*`, `*.tmpl` naming). The repo root is the git working tree, cloned to `~/.local/share/chezmoi`.
- `home/.chezmoiignore` is OS-aware: Linux-only targets are ignored on non-Linux, Windows-only targets on non-Windows. Add every new OS-specific file to the matching list; `tests/chezmoiignore.bats` checks the managed set per OS.
- `root/` is the **system chezmoi source state** (target `/`, run with sudo), applied by a second instance whose config and state live in `~/.config/chezmoi-root/`. Target policy: `dots system` applies it as an opt-in, interactive step with a diff. It is never applied by CI, tests, or `NON_INTERACTIVE=1`. Currently `tests/ownership.bats` forbids any script or workflow from referencing `root.toml`/`chezmoi-root`; that changes only in roadmap phase P6. The `chezmoi-root`/`cmr` function in `home/dot_zshrc` is the manual path until then: `cmr` shows status + diff and asks before applying, `cmr edit` edits the repo copy as the user, `cmr capture` pulls files changed in `/` back into the repo, and it chowns `root/` back to the user after every command. Its config is rendered from `home/dot_config/chezmoi-root/chezmoi.toml.tmpl`.
- Prefer drop-ins under `/etc/*.d/` over owning whole system files; never write into `/usr` outside a package (`pkgbuilds/`).
- Lists live in data, never in scripts: packages in `home/.chezmoidata/packages.yaml` (replacing `packages/*.txt`), KDE keys in `kde.yaml`, Windows registry values in `windows.yaml`. Arch installs via `paru -S --needed`, never as root. Windows uses winget for GUI/system apps and Scoop for CLI tools and fonts; no Chocolatey.
- KDE `*rc` files and the Windows registry are managed **per key**, not as whole files.
- `temp/` and `misc/` are gitignored scratch areas.
- `docs/` holds `README.md` (index), `vision.md`, `design.md`, `roadmap.md`.

## Machine data, secrets, and config writers

- `home/.chezmoi.toml.tmpl` prompts for `gitName`, `gitEmail`, `githubUsername`, `sshEmail` and stores them only in the local untracked `~/.config/chezmoi/chezmoi.toml`. `home/.chezmoidata.yaml` holds empty defaults plus `features.*` and `accounts.ssh.*`.
- The repository is **public**: never commit secrets, keys, tokens, or identity. Secrets come from Bitwarden template functions; SSH keys are served by the Bitwarden SSH agent.
- `home/dot_gitconfig.tmpl` and `home/dot_ssh/private_config.tmpl` are the **only** writers of `~/.gitconfig` and `~/.ssh/config`. Setup scripts only validate/collect data; an ownership test fails if they call `git config` or write SSH config directly. Never run `git lfs install` or `gh auth setup-git`; the LFS filter and the `gh` credential helper belong in the git template.
- If you add a new template variable, update `.chezmoidata.yaml` defaults and the `--override-data` JSON / `--promptString` lists in `tests/validate-templates.sh` and `tests/ownership.bats`.

## Script conventions

- Every Bash script sources `scripts/unix/lib/common.sh` and supports `--dry-run`. All side effects go through `run_or_print` / `run_root_or_print`, which print `+ cmd` instead of executing under `DRY_RUN=1`. PowerShell scripts use `lib/Common.ps1` and `Invoke-NativeCommand -DryRun`. Dry-run must create/modify nothing — tests assert the isolated `$HOME` is unchanged.
- Every `dots` step previews (diff or list) and asks before changing anything.
- `NON_INTERACTIVE=1` must never prompt: `confirm` returns its default, sudo/doas get `-n`, and missing identity data or an absent SSH key is a hard failure (`--allow-unencrypted-key` is the explicit opt-in).
- `bootstrap.sh` ends with an `if [[ "${BASH_SOURCE[0]}" == "$0" ]]` guard around `main` so Bats can `source` it and call/mock individual functions (e.g. override `has`). Add the same guard to a script before unit-testing its functions.
- `DOTFILES_PLATFORM` overrides platform detection; tests use it.
- Tests use `setup_isolated_home` from `tests/test_helper.bash` and mock binaries on `PATH`; they must never provision the real machine.
- Logging: Bash `log_step`/`log_success`/`log_warn`/`log_error`/`die`; PowerShell `Write-Step`/`Write-Success`/`Write-ToolWarning`/`Stop-Tool`.
- Style: Bash, 2-space indent, `shfmt -ci -bn`, must pass ShellCheck. PowerShell uses 4 spaces.
- Never install/reinstall an OS, partition disks, or build `[Future]` items unless asked.
