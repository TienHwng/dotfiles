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
| Cross-OS sharing | Only cross-platform app configs: git, VS Code, Neovim, PowerShell 7, starship/oh-my-posh, fonts, wallpapers. |
| Platforms | Primary: Windows 11, CachyOS. Planned: Arch Linux, Ubuntu desktop (KDE), Ubuntu WSL, macOS, NixOS. Fedora: dropped. |
| Machines | Today: one dual-boot laptop (see reference hardware). Later: more physical machines. Anything that differs per machine (GPU, laptop vs desktop, displays) comes from machine data (hostname, `hasNvidia`, `isLaptop`, …), never from hard-coded values. |
| Windows usage | Admin rights; also used for gaming. Game launchers (e.g. Steam) are installed from the manifest; signing in is a manual checklist item; game saves are personal data and out of scope. |
| Editors | VS Code uses its own Settings Sync. If Cursor is used, its settings and extension list are managed in the repository, because Cursor does not use VS Code Settings Sync. |
| Packages | One manifest with per-OS name mapping for cross-platform apps; niche apps in per-manager lists. Windows uses **winget** (GUI/system apps) and **Scoop** (CLI tools, Nerd Fonts). No Chocolatey. |
| Windows OS settings | Registry tweaks, debloat/privacy, CLI tools and fonts, NVIDIA and ASUS tools. |
| Interaction | Step-by-step with confirmation, driven by a terminal UI (TUI). |
| Capturing local changes | A TUI lists drift and lets the owner pick what goes back into the repository. |
| Apps with their own sync | VS Code Settings Sync, browsers, Steam, Discord use their own sync. The repository only installs them. |
| Repository | One public GitHub repository (`TienHwng/dotfiles`). System-level config lives in the same repository under `root/` with its own chezmoi instance. |
| System-level apply | A separate `dots` step that always shows a diff and asks. |
| Secrets | Bitwarden. |
| Wallpapers | ~1.5 GB: a separate **private** repository with **Git LFS**, pulled by chezmoi. |
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
 Bitwarden   paru/winget (home/)      KDE keys,    (root/),     repo (LFS), capture
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
| `scripts/unix/bootstrap.sh`, `scripts/windows/bootstrap.ps1` (current orchestrators) | `[Implemented]` |
| `dots` command with gum TUI | `[Planned: P1]` (Bash), `[Planned: P2]` (PowerShell) |

`dots` exists twice with the same interface: `scripts/unix/dots` (Bash) and
`scripts/windows/dots.ps1` (PowerShell 7). The TUI uses
[gum](https://github.com/charmbracelet/gum), available from pacman, winget, and Scoop.

#### Command reference

| Command | Behaviour | Status |
|---|---|---|
| `dots bootstrap` | Runs L1→L7 in order. Each step: describe → preview/diff → confirm → run. Each step can be skipped or the run stopped. Restoring a machine = this command. | `[Planned: P1]` |
| `dots sync` | `git pull --ff-only` → `chezmoi diff` → confirm → `chezmoi apply`. Reports manifest changes and offers `dots packages`. | `[Planned: P7]` |
| `dots sync --check` | Fetch only; report how many commits the machine is behind. Used by the timer. | `[Planned: P7]` |
| `dots capture` | TUI listing drift (files, KDE keys, registry values, packages outside the manifest); the chosen items are written back to the repository, then commit and push. | `[Planned: P7]` |
| `dots packages` | Install missing packages from the manifest after showing the list. | `[Planned: P1]` |
| `dots packages --diff` | List packages installed on the machine but absent from the manifest, and manifest packages not installed; later offer "add to manifest" or "uninstall". | `[Planned: P1]` (report available now: `install-packages.sh --diff`) |
| `dots system` | System-level step (L5). Always shows a diff. Needs sudo (Linux) or admin (Windows). Never runs non-interactively. | `[Planned: P5/P6]` |
| `dots status` | Commits ahead/behind, drift count, whether the sync timer is enabled. | `[Planned: P7]` |
| `dots doctor` | `chezmoi doctor` plus checks: required tools, Bitwarden agent reachable, Git LFS configured, sync timer enabled. | `[Planned: P1]` (current: `just doctor`) |
| `dots update` | Upgrade installed packages (`paru -Syu`, `winget upgrade --all`, `scoop update *`) and fonts. | `[Planned: P1]` (current: `update.sh`, `update.ps1`) |
| `dots backup` | Tarball of the repository working tree (including uncommitted work) plus the user and system local chezmoi configs, to a chosen directory. The destination MUST survive the reinstall: an external drive or a cloud folder. Do not rely on the other OS's disk (the Windows disk is BitLocker-encrypted). `dots backup` warns when the destination is on the same disk as the running OS. Run it before wiping a machine. | `[Planned: P1]` (current: `backup.sh`, `backup.ps1`) |
| `dots cleanup` | Remove package-manager and chezmoi caches. | `[Planned: P1]` (current: `cleanup.sh`, `cleanup.ps1`) |

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

The bootstrap script installs only `git`, `chezmoi`, `gum`, `jq` (plus `pwsh` on Windows),
runs `chezmoi init TienHwng/dotfiles` (public, no auth needed), then hands over to
`dots bootstrap`.

### L1 — Identity and secrets

| Item | Status |
|---|---|
| Git/SSH identity prompts stored in local chezmoi config | `[Implemented]` |
| Passphrase-protected SSH key creation in `setup-accounts.sh` | `[Implemented]` (to be replaced in P3) |
| `gh` credential helper rendered by `home/dot_gitconfig.tmpl` (Linux, when `gh` is on `PATH`) | `[Implemented]` |
| `gh auth login` step in `dots bootstrap` | `[Planned: P3]` |
| Bitwarden templates and SSH agent | `[Planned: P3]` |

- **GitHub access:** `gh auth login` (browser device flow). The git template already renders
  `gh auth git-credential` as the credential helper for `https://github.com` and
  `https://gist.github.com` whenever `gh` is on `PATH` (Linux; Windows uses Git Credential
  Manager). This lets git clone the private wallpaper repository over HTTPS **before** any SSH
  key exists, which breaks the "need a key to fetch the key" loop. Do **not** run
  `gh auth setup-git`: it writes `~/.gitconfig` directly, which the template owns.
- **Tokens and API keys:** chezmoi templates call `bitwardenFields` / `bitwarden`, with
  `bitwarden.unlock = "auto"` so chezmoi unlocks only when `BW_SESSION` is not set.
- **SSH keys live in the Bitwarden vault** and are served by the Bitwarden desktop SSH agent
  (desktop ≥ 2025.1.2). Private keys never touch the disk.
  - Windows: the *OpenSSH Authentication Agent* service must be disabled (done in L5).
  - Linux: the Flatpak build does not support the agent. Use the native package on CachyOS.
  - `home/dot_ssh/private_config.tmpl` sets `IdentityAgent` to the Bitwarden socket on Linux.
- `setup-accounts.sh/.ps1` change from "create a key" to "verify the agent holds a key".
  `--allow-unencrypted-key` stays as the explicit escape hatch for headless machines.

### L2 — Packages

| Item | Status |
|---|---|
| Manifest `home/.chezmoidata/packages.yaml` (replaced `packages/*.txt`) | `[Implemented]` |
| `scripts/package-list.tmpl` renderer, `manifest_list` (Bash) / `Get-ManifestList` (PowerShell) | `[Implemented]` |
| `install-packages.sh` (paru, apt, brew) and `install-packages.ps1` (winget) read the manifest | `[Implemented]` |
| `install-packages.sh --diff` report (arch, apt, brew) | `[Implemented]` |
| Fonts (`nerdFonts` list) read from the manifest | `[Implemented]` |
| Fedora backend | Removed |
| Scoop installs, Windows `--diff`, interactive "add to manifest / uninstall" | `[Planned: P2]` / `[Planned: P7]` |

Manifest format (`home/.chezmoidata/packages.yaml`):

```yaml
packages:
  # Apps under several managers: one entry, one key per manager that installs it
  mapped:
    - name: neovim
      arch: neovim
      apt: neovim
      brew: neovim
      winget: Neovim.Neovim
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
  scoop: []
  nerdFonts: [JetBrainsMono]    # Nerd Fonts release archives, installed per user
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
  Windows → `winget` for GUI/system apps, `scoop` for CLI tools and fonts (P2).
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
| Windows targets, `XDG_CONFIG_HOME`, PowerShell profile stub | `[Planned: P2]` |

- **One config path on both OSes:** on Windows, set the user environment variable
  `XDG_CONFIG_HOME=%USERPROFILE%\.config`. Neovim, starship, WezTerm, and git then read
  `~/.config`, so `home/dot_config/nvim`, `starship.toml`, etc. are shared unchanged.
- **`.chezmoiignore` is OS-aware** `[Implemented]`. Linux-only targets (`.zshrc`, `.oh-my-zsh`,
  kitty, hypr, tmux, fastfetch, KDE `*rc` files, `.local/share/plasma`, the system instance
  config) are ignored on every non-Linux OS; Windows-only targets (`AppData`,
  `Documents/PowerShell`, `.wslconfig`) are ignored everywhere except Windows.
  `tests/chezmoiignore.bats` checks the managed set per OS by overriding `.chezmoi.os`
  (`chezmoi --override-data '{"chezmoi":{"os":"windows"}}' managed`). New OS-specific files
  MUST be added to the matching list.

- **PowerShell profile:** OneDrive "Known Folder Move" can relocate `Documents`, so the repo
  does not hard-code `Documents/PowerShell`. A `run_onchange_` script writes a small stub to
  the real `$PROFILE.CurrentUserAllHosts` that dot-sources the chezmoi-managed
  `~/.config/powershell/profile.ps1`.
- Windows-only app configs (e.g. Windows Terminal `settings.json`) live under `home/AppData/…`.
- Apps with their own sync are not configured here. `dots bootstrap` ends by printing
  "sign in to sync" reminders for them.
- Cursor `[Planned: P2]`, only if the owner uses it: `settings.json` and `keybindings.json`
  are managed under its per-OS config path, and an extension list in the manifest is
  installed with `cursor --install-extension`.
- `home/Documents/Setup Scripts` and `home/Pictures/Wallpapers/.keep` are leftovers to move
  or remove in P4.

### L4 — Desktop settings, user scope

#### KDE Plasma `[Planned: P5]`

Problem: `kdeglobals`, `kwinrc`, `kglobalshortcutsrc`, `plasmashellrc` are currently managed
as whole files `[Implemented]`. Plasma rewrites them constantly, so the repository always shows
noise.

Target: manage individual keys from data.

```yaml
# home/.chezmoidata/kde.yaml
kde:
  kdeglobals:
    General: { ColorScheme: "BreezeDark" }
  kwinrc:
    Plugins: { blurEnabled: "true" }
    Desktops: { Number: "4", Rows: "1" }
  kglobalshortcutsrc:
    kwin: { "Window Close": "Meta+Q,Alt+F4,Close Window" }
```

- `run_onchange_after_kde-settings.sh.tmpl` (Linux with KDE only) renders one
  `kwriteconfig6 --file F --group G --key K V` per key (nested groups: repeat `--group`),
  then reloads KWin (`qdbus6 org.kde.KWin /KWin reconfigure`). It embeds a hash of
  `kde.yaml` so it re-runs only when the data changes.
- The whole `*rc` files leave the chezmoi source and go into `.chezmoiignore`.
- `dots capture kde` compares managed keys (`kreadconfig6`) with the YAML.
  `dots capture kde --discover` diffs snapshots of `~/.config/*rc` taken before and after a
  change in System Settings, so new keys can be picked.
- Panel/widget layout (`plasma-org.kde.plasma.desktop-appletsrc`) is screen-specific and stays
  manual. Scripted layouts are `[Future]`.
- Display layout (KScreen: arrangement, refresh rate, scale) is per machine and per monitor,
  so it is not synced. Values that must be fixed per machine go into machine data.
- Themes, icons, cursors (~11 MB) stay in the repository or come from packages.

#### Windows user registry (HKCU) `[Planned: P5]`

```yaml
# home/.chezmoidata/windows.yaml
windows:
  registry:
    user:      # HKCU, applied in L4, no admin
      - { path: 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', name: HideFileExt, type: DWord, value: 0 }
      - { path: 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', name: Hidden, type: DWord, value: 1 }
      - { path: 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', name: AppsUseLightTheme, type: DWord, value: 0 }
    machine:   # HKLM, applied in L5, admin
      - { path: 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation', name: RealTimeIsUniversal, type: QWord, value: 1 }
      - { path: 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power', name: HiberbootEnabled, type: DWord, value: 0 }
```

One idempotent PowerShell script reads current values, prints a diff table, asks, applies
with `Set-ItemProperty`, and restarts Explorer when needed. Do **not** use the DSC v3
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

#### Windows: admin step `[Planned: P5]`

Order inside `dots system` on Windows:

1. HKLM values from `windows.registry.machine`. Two of them exist for dual-boot:
   - `RealTimeIsUniversal=1`: Windows reads the hardware clock as UTC, like Linux.
   - Fast Startup off (`HiberbootEnabled=0`): avoids a half-hibernated Windows.
2. Disable the OpenSSH Authentication Agent service so the Bitwarden agent works (L1).
3. Debloat/privacy with [Win11Debloat](https://github.com/Raphire/Win11Debloat), **pinned to a
   release, checksum-verified**, run with an explicit parameter list stored in the repository
   plus `-Silent -CreateRestorePoint`. Never `-RunDefaults` blindly; never `irm | iex`.
4. Drivers and ASUS tools: NVIDIA via winget (NVIDIA App) or Windows Update; replace Armoury
   Crate with G-Helper (`seerge.g-helper`; needs .NET 8 and the ASUS System Control Interface
   driver) and stop Armoury Crate services if present.
5. WSL `[Planned: platform]`: `wsl --install -d Ubuntu`, then run the Unix bootstrap inside;
   `home/dot_wslconfig` is applied on Windows only.

### L6 — Assets

| Item | Status |
|---|---|
| Nerd Fonts from release archives via the manifest `nerdFonts` list | `[Implemented]` |
| Wallpaper repository + chezmoi external + setting the wallpaper | `[Planned: P4]` |

- Private repository `TienHwng/wallpapers`, with `.gitattributes`
  `*.jpg *.jpeg *.png *.webp filter=lfs diff=lfs merge=lfs -text`.
- GitHub Free includes 10 GiB of LFS storage and 10 GiB of bandwidth per month. 1.5 GB fits
  (about six full clones per month). Deleted LFS objects keep counting until the repository is
  deleted, so avoid churn.
- Pulled by a chezmoi external, gated by `features.wallpapers`:

  ```toml
  # home/.chezmoiexternal.toml.tmpl
  {{ if .features.wallpapers }}
  ["Pictures/wallpaper"]
      type = "git-repo"
      url = "https://github.com/TienHwng/wallpapers.git"
      refreshPeriod = "168h"
      [pull]
          args = ["--ff-only"]
  {{ end }}
  ```

- Prerequisites: `git-lfs` installed (bundled with Git for Windows; package `git-lfs` on
  Arch). The LFS filter MUST be added to `home/dot_gitconfig.tmpl` (`[filter "lfs"]`), because
  that template owns `~/.gitconfig`. Never run `git lfs install`, which writes to the file
  directly. Authentication comes from the `gh` credential helper in the git template (L1).
- Setting the wallpaper: the file name lives in data (`desktop.wallpaper`). KDE uses
  `plasma-apply-wallpaperimage`. Windows calls `SystemParametersInfo`
  (`SPI_SETDESKWALLPAPER`) from PowerShell. The SDDM login background is part of L5.
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
│   ├── .chezmoidata/               # packages.yaml [Implemented]; kde.yaml, windows.yaml [Planned]
│   ├── .chezmoiexternal.toml.tmpl  # wallpaper repo             [Planned: P4]
│   ├── .chezmoiignore              # OS-aware                   [Implemented]
│   ├── .chezmoiscripts/            # run_onchange_ scripts      [Planned]
│   ├── dot_config/                 # nvim, kitty, wezterm, ...  [Implemented]
│   │   ├── chezmoi-root/           # system instance config     [Implemented]
│   │   └── systemd/user/           # dots-sync timer            [Planned: P7]
│   ├── AppData/                    # Windows-only configs       [Planned: P2]
│   └── dot_wslconfig               # Windows-only               [Planned: platform]
├── root/                           # system chezmoi source      [Implemented, manual]
├── pkgbuilds/                      # local Arch packages        [Planned: P6]
├── scripts/
│   ├── package-list.tmpl           # renders one manifest list [Implemented]
│   ├── unix/                       # bootstrap.sh, install-*.sh, setup-*.sh, update.sh,
│   │                               # backup.sh, cleanup.sh, lib/common.sh  [Implemented]
│   │                               # dots, system.sh, capture.sh           [Planned]
│   └── windows/                    # *.ps1 counterparts, lib/Common.ps1    [Implemented, parse-checked]
│                                   # dots.ps1, system.ps1, capture.ps1     [Planned]
├── tests/                          # bats, template validation  [Implemented]; Pester [Planned: P2]
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
5. L6: pull wallpapers, install fonts, set the wallpaper.
6. L4: HKCU values (diff table → confirm).
7. L5 (admin): HKLM values, Fast Startup off, UTC clock, disable OpenSSH agent service,
   Win11Debloat, G-Helper, NVIDIA.
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
| Pester + PSScriptAnalyzer for `scripts/windows` | `[Planned: P2]` |
| `windows-latest` job: `chezmoi init --apply --dry-run` with fake prompt values, `dots.ps1 bootstrap -DryRun` | `[Planned: P2]` |
| `archlinux` container job: template render, `dots bootstrap --dry-run` | `[Planned: P1]` |
| Ownership test update for the system step and for `[filter "lfs"]` in the git template | `[Planned: P4/P6]` |

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
