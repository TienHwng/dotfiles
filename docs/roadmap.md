# Roadmap

What exists today, what to build next, and what is still uncertain.
Status tags are defined in [README.md](README.md); designs are in [design.md](design.md).

---

## 1. Current state (`[Implemented]`)

| Area | What exists |
|---|---|
| Dotfiles | chezmoi source in `home/` (`.chezmoiroot`), templates for `~/.gitconfig` and `~/.ssh/config`, identity prompts in `home/.chezmoi.toml.tmpl` |
| Bootstrap (CachyOS/Arch) | `scripts/unix/bootstrap.sh` with `--dry-run`, `--non-interactive`, `--skip-*` options; installs prerequisites, chezmoi, packages via paru, fonts, shell; applies chezmoi; runs `chezmoi doctor` |
| Maintenance | `update.sh`, `backup.sh` (repo tarball + local chezmoi config), `cleanup.sh` (caches) |
| Package data | Manifest `home/.chezmoidata/packages.yaml` read through `scripts/package-list.tmpl`; `install-packages.sh --diff` report |
| Windows | `scripts/windows/*.ps1` counterparts; parse-checked in CI only, not runtime-tested |
| System config | `root/` snapshot (GRUB, pacman.conf, SDDM, Plymouth), applied by hand with `cmr` |
| Quality | Bats tests, template validation, ShellCheck, shfmt, PowerShell parse check, ownership tests, GitHub Actions |
| Commands | `just` / `make` recipes: `bootstrap-unix[-dry]`, `packages-*`, `update-*`, `bootstrap-windows`, `preview`, `doctor`, `test`, `lint`, `templates`, `validate` |

Known gaps in the current state:

- KDE `*rc` files are managed as whole files and always show drift.
- No secrets-manager integration; SSH keys are created on disk.

---

## 2. Phases

Each phase is one pull request and MUST keep `make validate` green. Primary platforms
(Windows 11, CachyOS) come first; other platforms follow in section 3.

| Phase | Content | Done when |
|---|---|---|
| **P0 Safety** ✅ | OS-aware `.chezmoiignore` (+ `tests/chezmoiignore.bats`); gitleaks pre-commit hook, `make secrets`, CI history scan; system instance config/state in `~/.config/chezmoi-root/`, `cmr` restores source ownership | Done: the managed set for Windows contains no Linux-only file; gitleaks scans pass |
| **P1 Manifest + `dots` (CachyOS)** | **(a) done:** manifest `home/.chezmoidata/packages.yaml` replaces `packages/*.txt`; install and font scripts read it through `scripts/package-list.tmpl`; `install-packages.sh --diff`; Fedora backend removed; `tests/manifest.bats`. **(b) next:** `dots` (Bash, gum) with `bootstrap`, `packages [--diff]`, `doctor`, `update`, `backup`, `cleanup`; archlinux CI container | A fresh CachyOS VM gets every package from the manifest through `dots bootstrap` |
| **P2 Windows parity** | chezmoi on Windows, `XDG_CONFIG_HOME`, PowerShell profile stub, winget + Scoop from the manifest, fonts, `dots.ps1`; Pester, PSScriptAnalyzer, `windows-latest` CI job | A fresh Windows VM/Sandbox completes L2–L3 through `dots.ps1 bootstrap` |
| **P3 Secrets** | `gh auth login` step, Bitwarden templates, Bitwarden SSH agent, rewrite `setup-accounts` | `ssh -T git@github.com` works with no private key on disk, on both primary OSes |
| **P4 Assets** | `TienHwng/wallpapers` (private, LFS), chezmoi external, `[filter "lfs"]` in the git template, set wallpaper on both OSes; tidy `home/Pictures`, `home/Documents` | Same wallpaper shows on Windows and CachyOS after bootstrap |
| **P5 Desktop + Windows system** | `kde.yaml` replaces whole `*rc` files; `windows.yaml` HKCU/HKLM; dual-boot fixes; Win11Debloat (pinned); G-Helper; NVIDIA; `dots system` on Windows | `git status` stays clean after a day of KDE use; Windows tweaks re-apply idempotently |
| **P6 Linux system** | Shared machine data for the system instance, drop-ins, GRUB template, Plymouth PKGBUILD, post-apply hooks, `dots system` on Linux; update `tests/ownership.bats` and `CLAUDE.md` for the new policy | `dots system` shows a correct diff and applies it; CI still never touches `root/` |
| **P7 Sync + capture** | systemd user timer, Windows Scheduled Task + BurntToast, `dots sync [--check]`, `dots status`, `dots capture`; retire the `chezmoi push` zsh wrapper | A KDE setting change reaches the repository in three commands or fewer, and the other OS is notified at next login |

---

## 3. Planned platforms

Start only after P7, unless the owner reorders.

| Platform | Main work |
|---|---|
| Arch Linux | Validate the CachyOS path without `chwd`; NVIDIA driver selection |
| Ubuntu desktop (KDE) | `apt`/`flatpak`/`snap` manifest keys; GRUB/initramfs differences; Bitwarden Snap/.deb; verify KDE keys on Plasma 6.6 |
| Ubuntu WSL | WSL step in the Windows flow; WSL detection (`.chezmoi.kernel.osrelease` contains `microsoft`); SSH agent bridge |
| macOS | `brew` manifest key; revive the brew backend |
| NixOS | `nix` manifest key; consider plasma-manager for KDE settings |

---

## 4. Future features (`[Future]`)

Do not build these unless the owner asks.

| Feature | Note |
|---|---|
| Theme switcher | One `theme.toml` as the single source of colours for kitty, tmux, fastfetch, btop, etc. |
| Scripted KDE panel layout | Plasma desktop scripting (`evaluateScript`) instead of manual panel setup |
| `winget configure` | Optional `.dsc.yaml` export of the Windows setup |
| Self-update and release automation | Only if the repository is used by others |

Dropped ideas: GUI installer, telemetry, plugin system, service/provider architecture,
Fedora support, Chocolatey.

---

## 5. Open decisions (ask the owner before the related phase)

| Decision | Options | Needed by |
|---|---|---|
| Cross-platform prompt | starship or oh-my-posh | P2 |
| Windows terminal | Windows Terminal (default) or WezTerm (one Lua config for both OSes; config already in `home/dot_config/wezterm`) | P2 |
| Editor | VS Code only, or also Cursor (changes whether editor settings live in the repository) | P2 |
| Machine data keys | Final names and values for `hasNvidia`, `isLaptop`, display-related keys once a second physical machine exists | Second machine |

## 6. Proofs of concept to run before the related phase

| ID | Question | How to check | Fallback |
|---|---|---|---|
| PoC-1 (P4) | Does a chezmoi `git-repo` external fetch LFS objects? It shells out to the system `git clone`, so it should once the LFS filter is configured. | Clone the wallpaper repo through the external | `run_onchange_` script that clones and runs `git lfs pull` |
| PoC-2 (P5) | Does `kwriteconfig6` take effect without logging out? | Try each managed key on CachyOS | Mark keys that need a re-login and print a notice |
| PoC-3 (P3) | Does the Bitwarden SSH agent work on CachyOS (native package) and Windows together with git? | `ssh-add -l`, `git push` | Render a key from Bitwarden to disk with mode 600 |
| PoC-4 (P2) | Does the PowerShell profile stub land in the right place when OneDrive redirects `Documents`? | Toggle Known Folder Move in a VM | Set the profile path via environment variable |
| PoC-5 (P5) | Are the pinned Win11Debloat parameters stable across releases? | Read release notes on every bump | Move the needed tweaks into `windows.yaml` |
| PoC-6 (P6) | Does the NVIDIA dGPU runtime-suspend at idle on Wayland with recent CachyOS kernels? | `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status` | Runtime PM options via `modprobe.d` in `root/` |

## 7. Risks

| Risk | Mitigation |
|---|---|
| LFS quota exceeded by repeated clones | Watch GitHub billing; fall back to rclone + cloud storage |
| A secret is committed to the public repository | gitleaks pre-commit and CI; Bitwarden-only secrets |
| `supergfxctl` breakage on new kernels | Not used; stay on hybrid mode with `asusctl` |
| Plasma updates rename keys | Capture compares managed keys and reports missing ones |
| Windows feature updates revert registry tweaks | `dots system` is idempotent and can be re-run |

---

## Sources

- chezmoi: [Bitwarden functions](https://chezmoi.io/reference/templates/bitwarden-functions), [Install packages declaratively](https://chezmoi.io/user-guide/advanced/install-packages-declaratively/), [Include files from elsewhere](https://www.chezmoi.io/user-guide/include-files-from-elsewhere/)
- Bitwarden: [SSH Agent](https://bitwarden.com/help/ssh-agent/)
- GitHub: [Git LFS billing](https://docs.github.com/en/billing/concepts/product-billing/git-lfs), [Repository limits](https://docs.github.com/en/enterprise-server@3.19/repositories/creating-and-managing-repositories/repository-limits)
- Windows: [WinGet Configuration](https://learn.microsoft.com/windows/package-manager/configuration), [DSC v3 Registry resource (proof of concept)](https://learn.microsoft.com/en-us/powershell/dsc/reference/tools/registry/config/get?view=dsc-3.0), [Win11Debloat automation](https://github.com/Raphire/Win11Debloat/wiki/Automation), [G-Helper](https://g-helper.com/armoury-crate-alternative/)
- KDE: [plasma-manager](https://github.com/pjones/plasma-manager), [kconfig-to-commands](https://deltona.readthedocs.io/en/latest/commands/admin/kconfig-to-commands.html), [Kubuntu 26.04 (Plasma 6.6)](https://ubuntuhandbook.org/index.php/2026/03/kubuntu-26-04-confirmed-lts/)
- ASUS Linux: [supergfxctl manual](https://asus-linux.org/manual/supergfxctl-manual/), [CachyOS forum: hybrid GPU](https://discuss.cachyos.org/t/fresh-install-kde-plasma-dual-amd-nvidia-graphics-laptop-how-to-switch-gpu/21521), [supergfxctl#178](https://gitlab.com/asus-linux/supergfxctl/-/issues/178)
