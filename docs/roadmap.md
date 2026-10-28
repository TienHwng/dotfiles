# Roadmap

What exists today, what to build next, and what is still uncertain.
Status tags are defined in [README.md](README.md); designs are in [design.md](design.md).

---

## 1. Current state (`[Implemented]`)

| Area | What exists |
|---|---|
| Dotfiles | chezmoi source in `home/` (`.chezmoiroot`), templates for `~/.gitconfig` and `~/.ssh/config`, identity prompts in `home/.chezmoi.toml.tmpl` |
| Bootstrap (CachyOS/Arch) | `scripts/unix/bootstrap.sh` installs prerequisites and chezmoi, then runs `dots bootstrap` (packages via paru, git, accounts, fonts, shell, apply, wallpaper, each previewed and confirmed) |
| Maintenance | `update.sh`, `backup.sh` (repo tarball + local chezmoi config), `cleanup.sh` (caches) |
| Package data | Manifest `home/.chezmoidata/packages.yaml` read through `scripts/package-list.tmpl`; `install-packages.sh --diff` report |
| Windows | `scripts/windows/bootstrap.ps1` → `dots.ps1 bootstrap` (winget for GUI apps, Scoop for CLI tools and Nerd Fonts, `XDG_CONFIG_HOME`, profile stub → `~/.config/powershell/profile.ps1` with oh-my-posh); Pester + PSScriptAnalyzer + `windows-latest` CI; not yet run on a real Windows install |
| System config | `root/` snapshot (GRUB, pacman.conf, SDDM, Plymouth), applied by hand with `cmr` |
| Quality | Bats and Pester tests, template validation, ShellCheck, shfmt, PSScriptAnalyzer, ownership tests, gitleaks, GitHub Actions (Ubuntu, Arch Linux container, Windows jobs) |
| Commands | `just` / `make` recipes: `bootstrap-unix[-dry]`, `packages-*`, `update-*`, `bootstrap-windows`, `preview`, `doctor`, `test`, `lint`, `templates`, `secrets`, `hooks`, `validate`, `test-windows`, `lint-windows` |

Known gaps in the current state:

- `.zshrc` enables three zsh plugins the repository does not provide (see design L3).
- No template reads a Bitwarden secret yet (none is needed).

Deferred owner tasks (the owner postponed these; ask before closing the related phase):

| Since | Task | Closes |
|---|---|---|
| 2026-10-28 | Run `dots.ps1 bootstrap` on a fresh Windows VM/Sandbox; check PoC-4 (OneDrive moving `Documents`) | P2 |
| 2026-10-28 | PoC-3: install Bitwarden desktop + `bw`, enable the SSH agent, `chezmoi apply`, run the accounts step, `ssh -T git@github.com` (CachyOS and Windows) | P3 |
| 2026-10-28 | On Windows, check that the `wallpaper` step clones `TienHwng/wallpapers` and sets `space2.jpg` | P4 |
| 2026-10-28 | On Windows, run the `desktop` step and `dots system` twice: the second run reports nothing to change; after a reboot into CachyOS and back, both clocks agree | P5b |
| 2026-10-28 | Delete the old upstream clone `~/Pictures/wallpaper.upstream` (about 1.5 GB) on CachyOS once the new clone is trusted | P4 cleanup |

---

## 2. Phases

Each phase is one pull request and MUST keep `make validate` green. Primary platforms
(Windows 11, CachyOS) come first; other platforms follow in section 3.

| Phase | Content | Done when |
|---|---|---|
| **P0 Safety** ✅ | OS-aware `.chezmoiignore` (+ `tests/chezmoiignore.bats`); gitleaks pre-commit hook, `make secrets`, CI history scan; system instance config/state in `~/.config/chezmoi-root/`, `cmr` restores source ownership | Done: the managed set for Windows contains no Linux-only file; gitleaks scans pass |
| **P1 Manifest + `dots` (CachyOS)** ✅ | **(a) done:** manifest `home/.chezmoidata/packages.yaml` replaces `packages/*.txt`; install and font scripts read it through `scripts/package-list.tmpl`; `install-packages.sh --diff`; Fedora backend removed; `tests/manifest.bats`. **(b) done:** `dots` (Bash, gum with plain fallback) with `bootstrap`, `packages [--diff]`, `doctor`, `update`, `backup`, `cleanup`; `bootstrap.sh` hands its steps to `dots bootstrap`; `~/.local/bin/dots` symlink; `tests/dots.bats`; archlinux container CI job | A fresh CachyOS VM gets every package from the manifest through `dots bootstrap` |
| **P2 Windows parity** (code done) | **Done:** chezmoi copy mode on Windows, `XDG_CONFIG_HOME`, PowerShell profile stub + shared profile (oh-my-posh, `dots`), winget (GUI) + Scoop (CLI, Nerd Fonts) from the manifest, `dots.ps1` (`bootstrap.ps1` hands over to it), Pester, PSScriptAnalyzer, `windows-latest` CI job. **Left:** the acceptance run on a fresh Windows VM/Sandbox, PoC-4 | A fresh Windows VM/Sandbox completes L2–L3 through `dots.ps1 bootstrap` |
| **P3 Secrets** (code done) | **Done:** `accounts` step: `gh auth login` over HTTPS, gh credential helper on every OS, Bitwarden SSH agent check and key upload, `bw` status; `.accounts.ssh.agent` (`bitwarden`/`file`); ssh config and `environment.d` point at the agent; Bitwarden desktop and CLI in the manifest; `[bitwarden] unlock = "auto"`. **Left:** PoC-3 on real CachyOS and Windows installs (deferred by the owner on 2026-10-28, to revisit later); secret templates when a secret is needed | `ssh -T git@github.com` works with no private key on disk, on both primary OSes |
| **P4 Assets** (code done) | **Done:** wallpaper data and `git-repo` external (plain Git, no LFS), `wallpaper` step (`setup-wallpaper.sh/.ps1`: fetch, refuse a foreign clone, set the wallpaper on KDE and Windows), `git` step renders `~/.gitconfig` and `accounts` moved before `apply`, `home/Documents` and `home/Pictures` leftovers removed. private `TienHwng/wallpapers` created and filled, CachyOS clone migrated. **Left:** the acceptance run on Windows (same wallpaper after `dots.ps1 bootstrap`) | Same wallpaper shows on Windows and CachyOS after bootstrap |
| **P5a KDE settings** (code done) | `home/.chezmoidata/kde.yaml` + `desktop` step (`setup-desktop.sh`: current → new per key, `plasma-apply-lookandfeel`, `kwriteconfig6 --notify`, KWin reconfigure); whole `*rc` files removed from the source and ignored; `tests/desktop.bats` | `git status` stays clean after a day of KDE use |
| **P5b Windows registry + admin step** (code done) | **Done:** `home/.chezmoidata/windows.yaml`; `setup-registry.ps1` (current → new per value, `New-ItemProperty -Force`, Explorer restart) as the Windows `desktop` step (HKCU: file extensions, hidden files, dark apps); `setup-system.ps1` + `dots system` and a last `system` bootstrap step (HKLM `RealTimeIsUniversal=1` DWord, `HiberbootEnabled=0`; OpenSSH Authentication Agent stopped and disabled in `bitwarden` mode); previews as the user, applies in a UAC window, skipped by `-NonInteractive`; `tests/windows/Registry.Tests.ps1`. **Left:** the acceptance run on Windows | Windows tweaks re-apply idempotently |
| **P5c Windows debloat + drivers** | Win11Debloat (pinned, checksum-verified, explicit parameters); G-Helper instead of Armoury Crate; NVIDIA | A fresh Windows install ends up debloated with G-Helper and the NVIDIA driver |
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
| Windows terminal | Stay on Windows Terminal, or move both OSes to WezTerm (config already in `home/dot_config/wezterm`) or Alacritty | When the owner decides to switch |
| Machine data keys | Final names and values for `hasNvidia`, `isLaptop`, display-related keys once a second physical machine exists | Second machine |

## 6. Proofs of concept to run before the related phase

| ID | Question | How to check | Fallback |
|---|---|---|---|
| PoC-1 (P4) | ~~Does a chezmoi `git-repo` external fetch LFS objects?~~ Dropped: the wallpaper repository does not use LFS. | — | — |
| PoC-2 (P5) | Does `kwriteconfig6` take effect without logging out? | Partly answered: KWin keys reload with `qdbus6 org.kde.KWin /KWin reconfigure`; global shortcuts need a new login (no kglobalaccel service in Plasma 6). Still to watch: look-and-feel and `kdeglobals` keys live | The step prints a notice for shortcuts |
| PoC-3 (P3) | Does the Bitwarden SSH agent work on CachyOS (native package) and Windows together with git? | `ssh-add -l`, `git push`. **Deferred** by the owner (2026-10-28); steps in README "Machine-specific values and secrets" | Render a key from Bitwarden to disk with mode 600 |
| PoC-4 (P2) | Does the PowerShell profile stub land in the right place when OneDrive redirects `Documents`? | Toggle Known Folder Move in a VM | Set the profile path via environment variable |
| PoC-5 (P5) | Are the pinned Win11Debloat parameters stable across releases? | Read release notes on every bump | Move the needed tweaks into `windows.yaml` |
| PoC-6 (P6) | Does the NVIDIA dGPU runtime-suspend at idle on Wayland with recent CachyOS kernels? | `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status` | Runtime PM options via `modprobe.d` in `root/` |

## 7. Risks

| Risk | Mitigation |
|---|---|
| Wallpaper repository grows if images are replaced often (plain Git keeps history) | Shallow clones keep machines small; move to LFS only if a file nears 100 MB or churn grows |
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
