# Design

Target design of the repository. Status tags are defined in [README.md](README.md).
Phases (`Pn`) are defined in [roadmap.md](roadmap.md).

---

## 1. Agreed requirements

These decisions were made with the owner. Do not change them without asking.

| Topic | Decision |
|---|---|
| Starting point | The owner installs the OS by hand. `dots` runs inside a freshly installed, networked OS. |
| Sync model | Restore after reinstall **and** periodic sync: a timer fetches, notifies, and the owner reviews a diff before applying. Nothing is applied silently. |
| Scope | Dotfiles/CLI, GUI app settings, desktop/OS settings, system-level settings. Personal data is out of scope. |
| Cross-OS sharing | Only cross-platform app configs: git, VS Code, Neovim, PowerShell 7, oh-my-posh, fonts, wallpapers. |
| Platforms | Primary: Windows 11, CachyOS. Planned: Arch Linux, Ubuntu desktop (KDE), Ubuntu WSL, macOS, NixOS. Fedora: dropped. |
| Machines | Today: one dual-boot laptop (see reference hardware). Later: more physical machines. Anything that differs per machine (GPU, laptop vs desktop, displays) comes from machine data (hostname, `hasNvidia`, `isLaptop`, …), never from hard-coded values. |
| Windows usage | Admin rights; also used for gaming. Game launchers (e.g. Steam) are installed from the manifest; signing in is a manual checklist item; game saves are personal data and out of scope. |
| Editors | VS Code only, with its own Settings Sync; its settings are not in the repository. Cursor is not used. |
| Prompt | oh-my-posh on zsh and PowerShell 7, one theme for both (today the built-in `montys`). |
| Terminal | Linux: kitty. Windows: Windows Terminal for now; its settings are not managed. A switch to WezTerm or Alacritty (one config for both OSes) is under consideration. |
| Packages | One manifest with per-OS name mapping for cross-platform apps; niche apps in per-manager lists. Windows uses **winget** (GUI/system apps) and **Scoop** (CLI tools, Nerd Fonts). No Chocolatey. |
| Windows OS settings | Registry tweaks, debloat/privacy, CLI tools and fonts, NVIDIA and ASUS tools. |
| Interaction | Step-by-step with confirmation, driven by a terminal UI (TUI). |
| Capturing local changes | A TUI lists drift and lets the owner pick what goes back into the repository. |
| Apps with their own sync | VS Code Settings Sync, browsers, Steam, Discord use their own sync. The repository only installs them. |
| Repository | One public GitHub repository (`TienHwng/dotfiles`). System-level config lives in the same repository under `root/` with its own chezmoi instance. |
| System-level apply | A separate `dots` step that always shows a diff and asks. |
| Secrets | Bitwarden. |
| Wallpapers | ~755 MB: a separate **private** repository, plain Git (no LFS: no file is near the 100 MB limit and the set rarely changes), pulled by chezmoi. |
| Backup | `dots backup` keeps a tarball of the repository working tree plus the untracked local chezmoi configs. Restoring a machine is `dots bootstrap`. |

### Reference hardware

ASUS ROG Strix G512LI laptop: Intel i7-10750H, 16 GB RAM, Intel UHD + NVIDIA GTX 1650 Ti
Mobile (Turing, hybrid graphics), two 1920×1080 displays at scale 1 (internal eDP 144 Hz,
external HDMI 200 Hz). Dual-boot with **each OS on its own NVMe and its own ESP**.
The Windows partition uses **BitLocker**, so Linux cannot read it. All shared content
must travel through git or the network, never through the disk.

---

## 2. Architecture

```text
                       ┌──────────────────────────────────┐
                       │ dots  (TUI: Bash + PowerShell 7) │  ← the only entry point
                       └────────────────┬─────────────────┘
   ┌───────────┬───────────┬────────────┼────────────┬────────────┬───────────┐
   ▼           ▼           ▼            ▼            ▼            ▼           ▼
 L1 Identity L2 Packages L3 Dotfiles  L4 Desktop   L5 System    L6 Assets   L7 Sync
 gh +        manifest →  chezmoi      user scope:  chezmoi-root wallpaper   timer +
 Bitwarden   paru/winget (home/)      KDE keys,    (root/),     repo,       capture
             /scoop/apt               HKCU         HKLM,        fonts
                                                   debloat
   └───────────┴───────────┴────────────┴────────────┴────────────┴───────────┘
              machine data: home/.chezmoidata/*.yaml + chezmoi built-ins + prompts
```

Layer `L0` is `dots` itself. Every layer reads the same machine data. chezmoi is the
data source for scripts too: scripts call `chezmoi data --format json` and parse it with
`jq` (Bash) or `ConvertFrom-Json` (PowerShell). No `yq` or extra PowerShell module is needed.

This replaces the earlier service/provider architecture. Do not create
`scripts/<service>/<provider>.sh` directories.

---

## 3. Layers

### L0 — `dots` CLI and bootstrap

| Item | Status |
|---|---|
| `scripts/unix/bootstrap.sh`: prerequisites, chezmoi, repository init, then `dots bootstrap` | `[Implemented]` |
| `scripts/unix/dots` (Bash) with gum prompts and a plain-prompt fallback (`DOTS_NO_GUM=1`); `~/.local/bin/dots` symlink from `home/dot_local/bin/symlink_dots.tmpl` | `[Implemented]` |
| `scripts/windows/bootstrap.ps1`: chezmoi, repository init, then `dots.ps1 bootstrap` | `[Implemented]` |
| `scripts/windows/dots.ps1` with the same commands and steps (gum or `Read-Host`); `dots` function in the shared PowerShell profile | `[Implemented]` |

`dots` exists twice with the same interface: `scripts/unix/dots` (Bash) and
`scripts/windows/dots.ps1` (runs on Windows PowerShell 5.1, which a fresh Windows has, and
PowerShell 7; options are PowerShell-style: `-DryRun`, `-NonInteractive`, `-Skip a,b`). The TUI uses
[gum](https://github.com/charmbracelet/gum), available from pacman, winget, and Scoop.

#### Command reference

| Command | Behaviour | Status |
|---|---|---|
| `dots bootstrap` | Runs L1→L7 in order. Each step: describe → preview/diff → confirm → run. Each step can be skipped or the run stopped. Restoring a machine = this command. | `[Implemented]` (Bash and PowerShell): steps packages, git (also renders `~/.gitconfig`), accounts, fonts, shell, apply (everything except externals), desktop (KDE keys on Linux, HKCU values on Windows), wallpaper (fetches the wallpaper external, sets the wallpaper), and on Windows system (admin, last; skipped by `-NonInteractive`). The git step renders the gh credential helper so `gh auth login` in accounts does not offer to edit `~/.gitconfig`, and accounts comes before anything that clones a private repository; previews run the step with `--dry-run --non-interactive` (apply uses `chezmoi diff`); `--dry-run`, `--non-interactive`, `--skip STEP`; ends with `chezmoi doctor` and the manual checklist |
| `dots sync` | `git pull --ff-only` → `chezmoi diff` → confirm → `chezmoi apply`. Reports manifest changes and offers `dots packages`. | `[Planned: P7]` |
| `dots sync --check` | Fetch only; report how many commits the machine is behind. Used by the timer. | `[Planned: P7]` |
| `dots capture` | TUI listing drift (files, KDE keys, registry values, packages outside the manifest); the chosen items are written back to the repository, then commit and push. | `[Planned: P7]` |
| `dots packages` | Install missing packages from the manifest after showing the list. | `[Implemented]` (Bash) |
| `dots packages --diff` | List packages installed on the machine but absent from the manifest, and manifest packages not installed; later offer "add to manifest" or "uninstall". | `[Implemented]` (Bash, report only); interactive add/uninstall `[Planned: P7]` |
| `dots system` | System-level step (L5). Always shows a diff. Needs sudo (Linux) or admin (Windows). Never runs non-interactively. | `[Implemented]` (Windows): previews `setup-system.ps1 -DryRun` as the user, asks, then runs it in an administrator window (UAC) unless already elevated; also the last `bootstrap` step, skipped by `-NonInteractive` unless `-DryRun`. Linux `[Planned: P6]` |
| `dots status` | Commits ahead/behind, drift count, whether the sync timer is enabled. | `[Planned: P7]` |
| `dots doctor` | `chezmoi doctor` plus checks: required tools, Bitwarden agent reachable, sync timer enabled. | `[Implemented]` (Bash): required tools (git, chezmoi), optional tools (gum, gitleaks, fzf), manifest readable, Git hooks, system instance config, `chezmoi doctor` (warnings only). Bitwarden, LFS, and timer checks come with P3/P4/P7 |
| `dots update` | Upgrade installed packages (`paru -Syu`, `winget upgrade --all`, `scoop update *`) and fonts. | `[Implemented]` (Bash, runs `update.sh`) |
| `dots backup` | Tarball of the repository working tree (including uncommitted work) plus the user and system local chezmoi configs, to a chosen directory. The destination MUST survive the reinstall: an external drive or a cloud folder. Do not rely on the other OS's disk (the Windows disk is BitLocker-encrypted). `dots backup` warns when the destination is on the same disk as the running OS. Run it before wiping a machine. | `[Implemented]` (Bash, runs `backup.sh`; the system config is saved as `chezmoi-system.toml`) |
| `dots cleanup` | Remove package-manager and chezmoi caches. | `[Implemented]` (Bash, runs `cleanup.sh`) |

Every mutating command MUST accept `--dry-run` (Bash) / `-DryRun` (PowerShell).

#### First command on a new machine

The script is downloaded, reviewed, then run. It is never piped straight into a shell.

```bash
# CachyOS
curl -fsSLo /tmp/dots-bootstrap.sh https://raw.githubusercontent.com/TienHwng/dotfiles/main/scripts/unix/bootstrap.sh
less /tmp/dots-bootstrap.sh && bash /tmp/dots-bootstrap.sh
```

```powershell
# Windows 11 (Windows PowerShell 5.1 can run this first step)
irm https://raw.githubusercontent.com/TienHwng/dotfiles/main/scripts/windows/bootstrap.ps1 -OutFile $env:TEMP\dots-bootstrap.ps1
notepad $env:TEMP\dots-bootstrap.ps1; & $env:TEMP\dots-bootstrap.ps1
```

The Unix bootstrap script installs the prerequisites and chezmoi, runs `chezmoi init
TienHwng/dotfiles` (public, no auth needed), then hands over to `dots bootstrap`, passing
`--dry-run`, `--non-interactive`, and `--skip-*` through. gum arrives with the packages
step; until then `dots` uses plain prompts.

### L1 — Identity and secrets

| Item | Status |
|---|---|
| Git/SSH identity prompts stored in local chezmoi config | `[Implemented]` |
| `gh` credential helper rendered by `home/dot_gitconfig.tmpl` on every OS when `gh` is on `PATH` | `[Implemented]` |
| `accounts` step: `gh auth login` (HTTPS), Bitwarden SSH agent check, offer to add the key to GitHub, `bw` status | `[Implemented]` |
| `.accounts.ssh.agent`: `bitwarden` (default) or `file` (passphrase-protected key on disk, for headless machines) | `[Implemented]` |
| `~/.ssh/config` and `environment.d` point at the Bitwarden agent (Linux) | `[Implemented]` |
| Bitwarden CLI installed and `[bitwarden] unlock = "auto"` in the chezmoi config | `[Implemented]` |
| Templates that read secrets with `bitwarden*` functions | `[Future]`: no secret is needed yet |
| PoC-3: the agent with git/ssh on a real CachyOS and Windows install | Deferred by the owner (2026-10-28) |

- **GitHub access is HTTPS through `gh`** (owner's choice; remotes stay `https://`).
  `gh auth login --git-protocol https --web` (browser device flow). The git template renders
  `gh auth git-credential` as the credential helper for `https://github.com` and
  `https://gist.github.com` on every OS whenever `gh` is on `PATH` (forward slashes, quoted
  only when the path has spaces, as gh writes it; Windows keeps Git Credential Manager for
  other hosts). This lets git clone private repositories **before** any SSH key exists. Do
  **not** run `gh auth setup-git`: it writes `~/.gitconfig` directly, which the template owns.
  Because the helper is already gh's, `gh auth login` does not ask to set it up; that is why
  the `git` step renders `~/.gitconfig` before the `accounts` step logs in.
- **Commit signing:** off (owner's choice).
- **Tokens and API keys:** none are needed yet. When one is, a template calls
  `bitwardenFields` / `bitwarden` (`bitwarden.unlock = "auto"` already makes chezmoi run
  `bw unlock` only when `BW_SESSION` is not set). Account: bitwarden.com (US), the `bw`
  default. Before the first such template lands, the `bw login` check MUST move into a step
  that runs before `apply`, or apply fails on a fresh machine.
- **SSH keys live in the Bitwarden vault** and are served by the Bitwarden desktop SSH agent
  (desktop ≥ 2025.1.2). Private keys never touch the disk.
  - Windows: the *OpenSSH Authentication Agent* service must be disabled. The accounts step
    detects it and points to `dots system`, which disables it (L5).
    Windows OpenSSH (`ssh`, `ssh-add` on `PATH`) talks to Bitwarden's pipe; Git's bundled ssh
    is not used because git talks HTTPS.
  - Linux: the Flatpak build does not support the agent. Use the native package (`bitwarden`
    in the manifest). Socket: `~/.bitwarden-ssh-agent.sock`.
  - `home/dot_ssh/private_config.tmpl` sets `IdentityAgent` to that socket on Linux and lists
    no `IdentityFile`; `home/dot_config/environment.d/ssh-agent.conf.tmpl` sets `SSH_AUTH_SOCK`
    for `ssh-add` and other agent clients.
- `setup-accounts.sh/.ps1` (`--ssh-agent`/`-SshAgent` overrides the data): in `bitwarden` mode
  they check that the agent answers (`ssh-add -L`: 0 keys listed, 1 none, 2 no agent) and holds
  a key, then run `ssh -T git@github.com`; an unknown single key is offered for upload with
  `gh ssh-key add` (needs the `admin:public_key` scope). Interactive runs wait and retry;
  `NON_INTERACTIVE=1` fails when the agent is missing or empty. In `file` mode they keep the old
  behaviour; `--allow-unencrypted-key` stays as the explicit escape hatch.

### L2 — Packages

| Item | Status |
|---|---|
| Manifest `home/.chezmoidata/packages.yaml` (replaced `packages/*.txt`) | `[Implemented]` |
| `scripts/package-list.tmpl` renderer, `manifest_list` (Bash) / `Get-ManifestList` (PowerShell) | `[Implemented]` |
| `install-packages.sh` (paru, apt, brew) and `install-packages.ps1` (winget, then Scoop) read the manifest | `[Implemented]` |
| `install-packages.sh --diff` report (arch, apt, brew) | `[Implemented]` |
| Fonts (`nerdFonts` list) read from the manifest | `[Implemented]` |
| Fedora backend | Removed |
| Windows `--diff`, interactive "add to manifest / uninstall" | `[Planned: P7]` |

Manifest format (`home/.chezmoidata/packages.yaml`):

```yaml
packages:
  # Apps under several managers: one entry, one key per manager that installs it
  mapped:
    - name: neovim
      arch: neovim
      apt: neovim
      brew: neovim
      scoop: neovim             # Windows CLI tools come from Scoop
    - name: wezterm
      gui: true                 # skipped when DOTFILES_HEADLESS=1 (WSL, servers)
      brewCask: wezterm
      winget: wez.wezterm
  # Packages for one manager only
  arch: [paru, kitty, plymouth]
  apt: [build-essential]
  brew: []
  brewCask: []
  winget: [Microsoft.PowerShell]
  scoop: []                   # "bucket/app" adds the bucket first
  nerdFonts: [JetBrainsMono]    # Linux: release archive; Windows: Scoop nerd-fonts/<name>-NF
```

How a list is read:

- `scripts/package-list.tmpl` prints, for the list named by `DOTFILES_PACKAGE_LIST`, the
  matching key of every `mapped` entry, then the list of the same name. Run it with
  `chezmoi --source <repo> execute-template`, so scripts need chezmoi but no YAML/JSON
  parser, and PowerShell needs no JSON quoting. Bash wraps it in `manifest_list` (dedupes),
  PowerShell in `Get-ManifestList`.
- An unknown list name renders nothing; an unset `DOTFILES_PACKAGE_LIST` fails.
- In a dry run without chezmoi (fresh machine), the install scripts warn and stop instead of failing.

Rules:

- Manager per platform: CachyOS/Arch → `arch` (paru, `--needed`, never as root);
  Windows → `winget` for GUI/system apps, `scoop` for CLI tools and fonts. Both skip
  packages that are already installed; `-Upgrade` upgrades them instead. Scoop is installed
  per user on first use and refuses an elevated shell.
  Planned: Ubuntu → `apt` (+ `flatpak`/`snap` for GUI); macOS → `brew` + `brewCask`;
  NixOS → `nix`. A new manager is a new key, with no structural change.
- Put an app in `mapped` as soon as it is installed by two or more managers.
- Packages are **not** installed by chezmoi `run_onchange_` scripts, because every step
  must be confirmed.
- `install-packages.sh --diff` (`make packages-unix-diff`) is read-only. "Explicitly
  installed but not in the manifest" compares with `pacman -Qqe` / `apt-mark showmanual` /
  `brew leaves` + casks; "in the manifest but not installed" compares with every installed
  package (`pacman -Qq`, `dpkg-query`, `brew list`), so dependencies count as installed.
- `tests/manifest.bats` checks that every mapped entry has a unique name and at least one
  package, rendering, the headless filter, `--diff`, and the font list.

### L3 — Dotfiles (user instance, `home/`)

| Item | Status |
|---|---|
| chezmoi source in `home/` via `.chezmoiroot`, templates for git and SSH | `[Implemented]` |
| OS-aware `.chezmoiignore` | `[Implemented]` |
| Windows targets, `XDG_CONFIG_HOME`, PowerShell profile stub | `[Implemented]` |

- **One config path on both OSes:** on Windows, set the user environment variable
  `XDG_CONFIG_HOME=%USERPROFILE%\.config`. Neovim, oh-my-posh, WezTerm/Alacritty, and git then read
  `~/.config`, so `home/dot_config/nvim` etc. are shared unchanged.
- **`.chezmoiignore` is OS-aware** `[Implemented]`. Linux-only targets (`.zshrc`, `.oh-my-zsh`,
  kitty, hypr, tmux, fastfetch, KDE `*rc` files, `.local/share/plasma`, the system instance
  config) are ignored on every non-Linux OS; Windows-only targets (`AppData`,
  `Documents/PowerShell`, `.wslconfig`, `.config/powershell`) are ignored everywhere except Windows.
  `tests/chezmoiignore.bats` checks the managed set per OS by overriding `.chezmoi.os`
  (`chezmoi --override-data '{"chezmoi":{"os":"windows"}}' managed`). New OS-specific files
  MUST be added to the matching list.

- **Windows copies files.** `home/.chezmoi.toml.tmpl` sets `mode = "symlink"` everywhere
  except Windows, where symlinks need Developer Mode or admin rights.
- **PowerShell profile:** OneDrive "Known Folder Move" can relocate `Documents`, so the repo
  does not hard-code `Documents/PowerShell`. The `shell` step (`setup-shell.ps1`) sets
  `XDG_CONFIG_HOME` and writes a small stub to the real `$PROFILE.CurrentUserAllHosts`
  (`[Environment]::GetFolderPath('MyDocuments')\PowerShell\profile.ps1`) that dot-sources the
  chezmoi-managed `~/.config/powershell/profile.ps1`. A different existing file there is moved
  to `profile.ps1.bak-<timestamp>` first. The shared profile defines the `dots` function. That profile starts oh-my-posh with the same theme
  name as `.zshrc` (`OMP_THEME_NAME`, default `montys`).
- Windows-only app configs, when one is managed, live under `home/AppData/…`.
- Apps with their own sync are not configured here. `dots bootstrap` ends by printing
  "sign in to sync" reminders for them.
- zsh plugins: `.zshrc` enables `zsh-autosuggestions`, `zsh-syntax-highlighting` (both in
  `home/dot_oh-my-zsh/custom/plugins`), and `zsh-history-substring-search`, `auto-notify`
  (MichaelAquilina/zsh-auto-notify), `you-should-use` (MichaelAquilina/zsh-you-should-use),
  which the repository does not provide yet. Open gap: add them (e.g. as chezmoi externals).

### L4 — Desktop settings, user scope

#### KDE Plasma `[Implemented]` (P5a)

Plasma rewrites its `*rc` files constantly, so managing them whole made the repository show
noise. They are now managed **per key from data**; the whole files left the chezmoi source
and are listed in `home/.chezmoiignore` on every OS so nobody adds them back.

```yaml
# home/.chezmoidata/kde.yaml
kde:
  lookAndFeel: org.kde.breezetwilight.desktop      # plasma-apply-lookandfeel --apply
  settings:                                        # one entry per key, every machine
    - { file: kwinrc, group: [NightColor], key: Active, value: "true" }
    - { file: kglobalshortcutsrc, group: [services, kitty.desktop], key: _launch, value: "Meta+T" }
  machines:                                        # keyed by .chezmoi.hostname
    HwngPC:
      settings:                                    # this machine only
        - { file: kcminputrc, group: [Libinput, "1267", "12410", "ELAN1203:00 04F3:307A Touchpad"], key: NaturalScroll, value: "true" }
```

- Current keys (owner's picks): custom global shortcuts (Meta+U shut down, Meta+A /
  Meta+Shift+A activities, Meta+T kitty, Tiles editor unbound), KWin (fcitx5 Wayland input
  method, Night Color, one desktop), look (Breeze Twilight, contrast, Vivaldi as browser and as
  the `mimeapps.list` handler for http/https/html), touchpad and mouse (`kcminputrc`, per
  device, only on `HwngPC`), power (display stays on while on AC), the Kuro splash
  (`ksplashrc`; theme files in `home/dot_local/share/plasma`), and the fcitx5 input methods (`kde.fcitx5`: layout, list,
  default).
- Choosing a global theme in System Settings resets the splash to the theme's own (Breeze,
  the default, so `ksplashrc` ends up empty). Whole-file capture once saved that empty file;
  per key, the `desktop` step applies the theme first and then sets the splash back.
- fcitx5 rewrites `fcitx5/profile` from memory, so a running fcitx5 gets the list over D-Bus
  (`org.fcitx.Fcitx.Controller1.SetInputMethodGroupInfo`, then `SetCurrentIM` for the
  default), as fcitx5-configtool does; without one the step writes the profile keys.
- `scripts/kde-settings.tmpl` renders one line per key (file, groups joined by the ASCII unit
  separator, key, value), like `package-list.tmpl` does for packages.
- Machine-specific keys `[Implemented]`: keys tied to one machine's hardware (a laptop's
  touchpad, a mouse by vendor and product id) go under `kde.machines.<hostname>.settings`,
  keyed by `.chezmoi.hostname`. The template renders the shared `kde.settings` first, then the
  current machine's entries; a machine entry with the same file, groups and key replaces the
  shared one, so a machine can also change a shared value. Other machines never see them.
  `setup-desktop.sh` reads only the rendered lines and does not know about machines. Tests
  set the hostname with `[data.chezmoi] hostname` in the isolated chezmoi config.
- The `desktop` step of `dots` (`scripts/unix/setup-desktop.sh`, after `apply` so the splash
  theme exists, before `wallpaper`) reads each key with `kreadconfig6`, prints
  `file [group] key: current -> new` for the ones that differ, then applies the global theme
  first (it rewrites colors) and writes each key with `kwriteconfig6 --notify` (nested groups:
  repeated `--group`). It reloads KWin with `qdbus6 org.kde.KWin /KWin reconfigure` when a
  `kwinrc` key changed. Global shortcuts, input devices and power settings take effect after
  the next login (Plasma 6 runs kglobalaccel inside KWin, with no service to restart). Without Plasma 6 the step does nothing.
  First it removes links in `~/.config` that dangle into `home/` (whole `*rc` files that
  chezmoi symlinked before P5a): `kwriteconfig6` writes nothing through them yet exits 0.
  The owner chose a dots step over a `run_onchange_` script so every change is previewed and
  confirmed. Gate: `features.desktop`.
- `dots capture kde` compares managed keys (`kreadconfig6`) with the YAML.
  `dots capture kde --discover` diffs snapshots of `~/.config/*rc` taken before and after a
  change in System Settings, so new keys can be picked.
- Panel/widget layout (`plasma-org.kde.plasma.desktop-appletsrc`) is screen-specific and stays
  manual. Scripted layouts are `[Future]`.
- Display layout (KScreen: arrangement, refresh rate, scale) is per machine and per monitor,
  so it is not synced. Values that must be fixed per machine go into machine data
  (`kde.machines` for KDE keys).
- Themes, icons, cursors (~11 MB) stay in the repository or come from packages.

#### Windows user registry (HKCU) `[Implemented]`

```yaml
# home/.chezmoidata/windows.yaml
windows:
  registry:
    user:      # HKCU, applied in L4, no admin
      - { path: 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', name: HideFileExt, type: DWord, value: 0 }
      - { path: 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', name: Hidden, type: DWord, value: 1 }
      - { path: 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', name: AppsUseLightTheme, type: DWord, value: 0 }
    machine:   # HKLM, applied in L5, admin
      - { path: 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation', name: RealTimeIsUniversal, type: DWord, value: 1 }
      - { path: 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power', name: HiberbootEnabled, type: DWord, value: 0 }
```

The Windows side of the `desktop` step is `scripts/windows/setup-registry.ps1 -Scope user`
(`-Scope machine` serves `dots system`). It reads the list with
`chezmoi execute-template '{{ .windows.registry.<scope> | toJson }}'` from the checkout,
prints `path name: current (kind) -> new (kind)` for every value whose data or kind differs,
then writes each with `New-ItemProperty -Force` (creating the key if needed), so a value
stored with another kind is replaced. Types: `DWord`, `QWord`, `String`, `ExpandString`.
Explorer restarts when a key under `\Explorer\` changed. Gate: `features.desktop`. Do
**not** use the DSC v3
`Microsoft.Windows/Registry` resource: Microsoft documents it as a proof of concept, not for
production.

### L5 — System level

#### Linux: system instance (`root/`)

| Item | Status |
|---|---|
| `root/` source, applied manually via `chezmoi-root`/`cmr` in `home/dot_zshrc` | `[Implemented]` |
| Separate config/state directory, root cache, source ownership restored after each `cmr` | `[Implemented]` |
| System config rendered by the user instance from `home/dot_config/chezmoi-root/chezmoi.toml.tmpl` | `[Implemented]` |
| `cmr` review flow (status + diff + confirm), `cmr edit` (edit repo copy as the user, diff, confirm), `cmr capture` (fzf pick of files changed in `/`, `re-add`, templates listed for manual edit) | `[Implemented]` |
| Machine data copied into the system config, templates per distro, drop-ins, hooks, PKGBUILD, `dots system` | `[Planned: P6]` |

1. **Separate state.** chezmoi keeps `chezmoistate.boltdb` next to its config file, so the
   system config lives in its own directory, `~/.config/chezmoi-root/chezmoi.toml`. `cmr`
   runs plain `sudo` (not `sudo -E`, preserving only `EDITOR`/`VISUAL`) with
   `--cache=/var/cache/chezmoi-root`, so nothing root-owned lands in the user's home.
   Because `add`/`edit`/`re-add` run as root and create root-owned files in `root/`, `cmr`
   chowns the source back to the user after every command; git does not track ownership and
   chezmoi sets target ownership from the process that writes it, so this is safe.
   `cmr cd` changes directory in the current shell instead of spawning a root shell.
2. **Shared machine data.** The user instance already renders `~/.config/chezmoi-root/chezmoi.toml`
   from `home/dot_config/chezmoi-root/chezmoi.toml.tmpl`. Planned: copy machine data into its
   `[data]` table, so both instances read the same values.
   Read-only lookups that `cmr` runs as the user (`source-path`) pass a throwaway
   `--persistent-state`, because the real state file is root-owned.
   Note: with an empty state file (first run after the move), chezmoi cannot tell that `/` was
   edited by hand and reports ` M` instead of `MM`; review `cmr diff` before the first apply.
3. **Templates per distro/machine.** `root/.chezmoiignore` gates files by distro, so planned
   distros (e.g. Ubuntu, which uses `update-grub`) can be added later.
4. **Prefer drop-ins** (`/etc/sddm.conf.d/`, `/etc/mkinitcpio.conf.d/`, `sysctl.d`,
   `modprobe.d`, systemd `*.d/`). For pacman, add `Include = /etc/pacman.d/custom.conf`
   instead of owning `pacman.conf`. This avoids `.pacnew` conflicts.
5. **Never write to `/usr`.** The Plymouth theme `motion` (~48 MB) becomes
   `pkgbuilds/plymouth-theme-motion/PKGBUILD`, installed with `makepkg -si`.
6. **Post-apply hooks:** `run_onchange_after_*.sh.tmpl` with a hash of the source file runs
   `grub-mkconfig`, `mkinitcpio -P`, or `plymouth-set-default-theme`.
7. **Policy:** `dots system` is an opt-in bootstrap step, interactive only, always with a diff.
   It MUST NOT run in CI or with `NON_INTERACTIVE=1`. Until P6 is merged, `tests/ownership.bats`
   still forbids any script from referencing the system instance, and that test wins.

#### Linux: hardware (reference laptop)

- NVIDIA driver: `chwd` on CachyOS. The GTX 1650 Ti (Turing) supports the open kernel modules.
- Keep **hybrid (PRIME offload)** mode. Use `asusctl` + `rog-control-center` for power
  profiles, fans, and LEDs. Do not depend on `supergfxctl` (reported as being phased out,
  with regressions on recent kernels).
- NVIDIA kernel parameters live in the GRUB template behind a `hasNvidia` data flag.

#### Windows: admin step `[Implemented: P5b]`, NVIDIA App `[Implemented: P5c]`, debloat and ASUS tools `[Planned: P5c]`

Order inside `dots system` on Windows:

1. HKLM values from `windows.registry.machine`. Two of them exist for dual-boot:
   - `RealTimeIsUniversal=1`: Windows reads the hardware clock as UTC, like Linux (owner's
     choice; Linux keeps the default UTC clock).
   - Fast Startup off (`HiberbootEnabled=0`): avoids a half-hibernated Windows.
   `RealTimeIsUniversal` is a DWord (an earlier draft said QWord; DWord is what Windows 10/11
   read). Both take effect after a restart.
2. Disable the OpenSSH Authentication Agent service so the Bitwarden agent works (L1); only
   when `.accounts.ssh.agent` is `bitwarden`.

3. NVIDIA App, only when a GPU with PCI vendor `10DE` is present and no NVIDIA App is
   installed (uninstall entry `NVIDIA app`). Microsoft's winget repository does not carry it
   (its validation runs in Windows Sandbox, which has no NVIDIA GPU), and the owner rejected
   the third-party `winget-extras` source. So `windows.nvidia.app` in `windows.yaml` pins
   version, URL (`us.download.nvidia.com`) and SHA-256; `install-nvidia-app.ps1` downloads,
   checks the hash and a valid `NVIDIA Corporation` Authenticode signature, then runs the
   installer with its own window. The app then updates itself and the driver, so the pin
   only matters for fresh machines.

Steps 1–3 are `scripts/windows/setup-system.ps1`. `dots system` runs it with `-DryRun` as the
user (reading HKLM and the service needs no admin), asks, then starts it elevated with
`Start-Process -Verb RunAs -Wait` (`-PauseOnExit` keeps that window open) unless the shell is
already elevated. Steps 4–6 are planned.

4. Debloat/privacy with [Win11Debloat](https://github.com/Raphire/Win11Debloat), **pinned to a
   release, checksum-verified**, run with an explicit parameter list stored in the repository
   plus `-Silent -CreateRestorePoint`. Never `-RunDefaults` blindly; never `irm | iex`. The
   release has no asset besides `Get.ps1`, so the pin is the tag's source archive
   (`archive/refs/tags/<tag>.zip`) and its SHA-256. The owner picks the switches after looking
   at the Windows machine; the two they named (hidden files, file extensions) are already HKCU
   values in `windows.yaml`.
5. ASUS tools: G-Helper instead of Armoury Crate is being weighed by the owner (G-Helper:
   `seerge.g-helper`; needs .NET 8 and the ASUS System Control Interface driver).
6. WSL `[Planned: platform]`: `wsl --install -d Ubuntu`, then run the Unix bootstrap inside;
   `home/dot_wslconfig` is applied on Windows only.

### L6 — Assets

| Item | Status |
|---|---|
| Nerd Fonts via the manifest `nerdFonts` list (Linux: release archives; Windows: Scoop) | `[Implemented]` |
| Wallpaper repository + chezmoi external + `wallpaper` step that sets it (KDE, Windows) | `[Implemented]` |
| Repository `TienHwng/wallpapers` created (private) and filled; `~/Pictures/wallpaper` on CachyOS is now its clone (old upstream clone kept as `~/Pictures/wallpaper.upstream`) | Done (2026-10-28) |

- Private repository `TienHwng/wallpapers` (owner's choice over using the public upstream or a
  public fork). The images come from the public `mylinuxforwork/wallpaper` repository
  (GPL-2.0), so its `LICENSE` and a source note stay in the repository.
- Plain Git, **no Git LFS** (owner's decision): 223 images, 754 MB, 3.4 MB on average, the
  largest 26.6 MB. Nothing is near GitHub's 100 MB file limit, the set rarely changes, and LFS
  would add a bandwidth quota (10 GiB/month on Free, about 0.75 GB per clone), storage that
  keeps counting deleted objects, and a `git-lfs` + filter prerequisite on every machine.
  Revisit only if a file approaches 100 MB or images are replaced often (history growth).
- Data (`home/.chezmoidata.yaml`): `features.wallpapers`, `wallpapers.repo`, `wallpapers.dir`
  (`Pictures/wallpaper`), `wallpapers.current` (`space2.jpg`).
- `home/.chezmoiexternal.toml.tmpl` declares a `git-repo` external at `wallpapers.dir`
  (`clone --depth 1`, `pull --ff-only`, `refreshPeriod = "168h"`) when `features.wallpapers`
  is on. The `apply` step of `dots` excludes externals (`--exclude externals`); the
  `wallpaper` step (`setup-wallpaper.sh/.ps1`) runs `chezmoi apply <dir>` after `accounts`,
  so the private clone has gh's credentials. A plain `chezmoi apply` also fetches it.
- chezmoi runs `git pull` in whatever repository already sits at that path. The wallpaper step
  therefore stops when the directory is a clone of another repository and asks the owner to
  move it away.
- Authentication comes from the `gh` credential helper in the git template (L1).
- Setting the wallpaper: the file name lives in data (`wallpapers.current`). KDE uses
  `plasma-apply-wallpaperimage`. Windows calls `SystemParametersInfo`
  (`SPI_SETDESKWALLPAPER`, saved to the profile) from PowerShell. Hyprland (hyprpaper) is not
  handled. The SDDM login background and the lock screen are part of L5.
- Fonts: Scoop bucket `nerd-fonts` on Windows (per-user, no admin); packages on Arch.

### L7 — Sync and capture `[Planned: P7]`

**Repository → machine:**

- Linux: a systemd **user** timer `dots-sync.timer` (every 6 h and at login) runs
  `dots sync --check` and sends `notify-send` when the repository has new commits.
  Unit files live in `home/dot_config/systemd/user/`.
- Windows: a Scheduled Task (at logon and periodically) runs `dots.ps1 sync -Check` and shows a
  toast via the BurntToast module.
- Neither applies anything. On the dual-boot machine the other OS learns about changes at its
  next login.

**Machine → repository (`dots capture`):** one `gum choose --no-limit` screen with four sources.

| Source | Detected by | Action when chosen |
|---|---|---|
| Managed files | `chezmoi status` / `chezmoi diff` | `chezmoi re-add <file>` |
| KDE keys | `kreadconfig6` vs `kde.yaml` | Update the YAML value |
| Windows registry | `Get-ItemProperty` vs `windows.yaml` | Update the YAML value |
| Packages | `dots packages --diff` | Add to manifest, or uninstall |

Then show `git diff`, ask for a commit message, commit, and push. This replaces the
`chezmoi push` wrapper function in `home/dot_zshrc`.

---

## 4. Repository layout

`[Implemented]` paths exist today; the rest are `[Planned]`.

```text
.
├── .chezmoiroot                    # contains "home"           [Implemented]
├── .github/workflows/validate.yml  # CI                         [Implemented]
├── CLAUDE.md                       # agent guide                [Implemented]
├── docs/                           # this documentation         [Implemented]
├── home/                           # user chezmoi source        [Implemented]
│   ├── .chezmoi.toml.tmpl          # identity prompts           [Implemented]
│   ├── .chezmoidata.yaml           # defaults, features.*       [Implemented]
│   ├── .chezmoidata/               # packages.yaml, kde.yaml, windows.yaml [Implemented]
│   ├── .chezmoiexternal.toml.tmpl  # wallpaper repo             [Implemented]
│   ├── .chezmoiignore              # OS-aware                   [Implemented]
│   ├── .chezmoiscripts/            # run_onchange_ scripts      [Planned]
│   ├── dot_config/                 # nvim, kitty, wezterm, ...  [Implemented]
│   │   ├── chezmoi-root/           # system instance config     [Implemented]
│   │   └── systemd/user/           # dots-sync timer            [Planned: P7]
│   ├── dot_config/powershell/      # shared pwsh profile (Windows) [Implemented]
│   ├── AppData/                    # Windows-only configs       [Planned, when one is managed]
│   └── dot_wslconfig               # Windows-only               [Planned: platform]
├── root/                           # system chezmoi source      [Implemented, manual]
├── pkgbuilds/                      # local Arch packages        [Planned: P6]
├── scripts/
│   ├── package-list.tmpl           # renders one manifest list [Implemented]
│   ├── unix/                       # bootstrap.sh, install-*.sh, setup-*.sh, update.sh,
│   │                               # backup.sh, cleanup.sh, lib/common.sh  [Implemented]
│   │                               # dots [Implemented]; system.sh, capture.sh [Planned]
│   └── windows/                    # dots.ps1, *.ps1 steps, lib/Common.ps1 [Implemented]
│                                   # system.ps1, capture.ps1               [Planned]
├── tests/                          # bats, template validation, windows/*.Tests.ps1 (Pester) [Implemented]
├── PSScriptAnalyzerSettings.psd1   # analyzer rules for scripts/windows [Implemented]
├── Justfile, Makefile              # identical recipes          [Implemented]
└── temp/, misc/                    # gitignored scratch
```

---

## 5. Flows

### 5.1 Freshly installed Windows 11 (owner already installed the OS and signed in)

1. Download and run `bootstrap.ps1` → installs `Git.Git`, `twpayne.chezmoi`,
   `charmbracelet.gum`, `jqlang.jq`, `Microsoft.PowerShell` → `chezmoi init TienHwng/dotfiles`
   → open `pwsh` → `dots bootstrap`.
2. L1: `gh auth login`; install Bitwarden desktop → **manual step with instructions**: sign in,
   enable the SSH agent.
3. L2: winget + Scoop: list → confirm → install.
4. L3: `chezmoi diff` → confirm → `chezmoi apply` (sets `XDG_CONFIG_HOME`, writes the profile stub).
5. L4: HKCU values (diff table → confirm).
6. L6: pull wallpapers, install fonts, set the wallpaper.
7. L5 (admin, UAC window): HKLM values, Fast Startup off, UTC clock, disable OpenSSH agent
   service, NVIDIA App; later Win11Debloat and the ASUS tools (P5c).
8. L7: register the Scheduled Task.
9. Print the manual checklist: VS Code Settings Sync, browser, Steam, Discord.

### 5.2 Freshly installed CachyOS

Same order. L2 uses paru; L4 applies KDE keys; L5 is `dots system` → system instance diff →
apply → hooks (GRUB, initramfs, Plymouth), PKGBUILD theme, `asusctl`; L7 enables the systemd
user timer.

### 5.3 Planned platforms

| Platform | Differences |
|---|---|
| Arch Linux | Same as CachyOS; NVIDIA driver chosen without `chwd`. |
| Ubuntu desktop (KDE) | `apt` + `flatpak`/`snap`; Bitwarden from Snap or .deb (not Flatpak); `update-grub`, `update-initramfs -u`; `ubuntu-drivers install`. Kubuntu 26.04 ships Plasma 6.6: verify KDE keys. |
| Ubuntu WSL | Started from the Windows flow. Only L2 (skip `gui: true`), L3 (ignore GUI files), L7. SSH through the Windows agent (`npiperelay`/`wsl-ssh-agent`) or `ssh.exe`. |
| macOS | `brew` key in the manifest; existing best-effort brew backend. |
| NixOS | `nix` key in the manifest; KDE settings may move to plasma-manager. |

---

## 6. Security

- The repository is **public**. It MUST NOT contain secrets, private keys, tokens, Wi-Fi/VPN
  credentials, or machine identity. Identity stays in the untracked local chezmoi config.
- Sensitive values are rendered from Bitwarden at apply time.
- gitleaks runs as a pre-commit hook (`.githooks/pre-commit`, enabled with `make hooks`) and
  scans the full history in CI and in `make validate` (`make secrets`) `[Implemented]`.
- Third-party scripts and installers are pinned to a version and checksum-verified. No
  `irm | iex` or `curl | sh` inside automated flows.
- Review `root/` before committing: no network configuration or credentials.

---

## 7. Testing and CI

| Check | Status |
|---|---|
| Bats tests with isolated `$HOME` and mocked binaries | `[Implemented]` |
| ShellCheck, shfmt (`-i 2 -ci -bn`), Bash syntax | `[Implemented]` |
| Template rendering in a temporary HOME (`tests/validate-templates.sh`) | `[Implemented]` |
| PowerShell parse check | `[Implemented]` |
| Ownership tests (`tests/ownership.bats`) | `[Implemented]` |
| gitleaks (pre-commit hook, `make secrets`, CI history scan) | `[Implemented]` |
| Manifest tests (`tests/manifest.bats`): unique names, at least one package per mapped entry, rendering, headless filter, `--diff` | `[Implemented]` |
| Pester (`tests/windows`, `make test-windows`) + PSScriptAnalyzer (`make lint-windows`) for `scripts/windows` | `[Implemented]` |
| `windows-latest` job: config rendered with fake prompt values, analyzer, Pester, `bootstrap.ps1 -DryRun -NonInteractive` on Windows PowerShell 5.1 and PowerShell 7 | `[Implemented]` |
| `archlinux` container job, as a regular user: Bats tests, template render, `bootstrap.sh --dry-run --non-interactive` (every step) with fake prompt values, HOME unchanged | `[Implemented]` |
| Ownership test: no script runs `git lfs install` or `gh auth setup-git` | `[Implemented]` |
| Ownership test update for the system step | `[Planned: P6]` |

Tests MUST never provision the real machine.

---

## 8. Rules for contributors and AI agents

MUST:

- Read [README.md](README.md) (index), then this file, before changing behaviour.
- Keep every mutating path behind `run_or_print` / `run_root_or_print` (Bash) or
  `Invoke-NativeCommand -DryRun` (PowerShell, `lib/Common.ps1`), so a dry run creates or
  modifies nothing.
- Keep `NON_INTERACTIVE=1` prompt-free: `confirm` returns its default, sudo/doas get `-n`,
  missing identity or SSH key is a hard failure.
- Keep templates as the only writers of `~/.gitconfig` and `~/.ssh/config`.
- When adding a template variable, update `home/.chezmoidata.yaml` defaults and the
  `--override-data` / `--promptString` lists in `tests/validate-templates.sh` and
  `tests/ownership.bats`.
- Put lists (packages, KDE keys, registry values) in `home/.chezmoidata/*.yaml`, never inside scripts.
- Add the `if [[ "${BASH_SOURCE[0]}" == "$0" ]]` main guard before unit-testing a script's functions.
- Pass ShellCheck and `shfmt -i 2 -ci -bn`. PowerShell uses 4-space indentation.
- Use the shared logging helpers: Bash `log_step`, `log_success`, `log_warn`, `log_error`, `die`;
  PowerShell `Write-Step`, `Write-Success`, `Write-ToolWarning`, `Stop-Tool`.
- Update the status tag in these documents in the same change that implements a feature.

MUST NOT:

- Install or reinstall an operating system, partition disks, or touch other OS partitions.
- Apply the system instance from CI, tests, or non-interactive runs.
- Run paru/makepkg as root.
- Write into `/usr` outside a package.
- Run `git lfs install`, `gh auth setup-git`, `git config --global`, or anything else that writes files owned by templates.
- Add Chocolatey, Fedora support, or service/provider directories.
- Build `[Future]` items unless the owner asks.
