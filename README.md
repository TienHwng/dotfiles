# Dotfiles Framework

Reinstall your OS by hand, run one command, and get your working environment back
(apps, configs, desktop settings, system tweaks, wallpapers) on **Windows 11** and
**CachyOS**. Machines that are already running are notified when the repository changes.

Built on [chezmoi](https://www.chezmoi.io/), with a step-by-step terminal UI (`dots`)
that previews every change and asks before applying it.

> **Status:** under active development. This README describes the target design.
> Items marked *(planned)* do not exist yet. The entry point is `dots`: Bash on CachyOS,
> `dots.ps1` on Windows (not yet run on a fresh Windows install). See [docs/roadmap.md](docs/roadmap.md) for what is implemented.

## What it does

| Layer | What gets restored | Tooling |
|---|---|---|
| Identity & secrets | GitHub login (HTTPS via `gh`), SSH keys served from the vault; tokens *(when needed)* | `gh`, Bitwarden (vault + SSH agent) |
| Packages | Apps and CLI tools from one manifest (`home/.chezmoidata/packages.yaml`) | paru (CachyOS), winget for GUI apps + Scoop for CLI tools (Windows) |
| Dotfiles | Shell, git, Neovim, terminal, prompt, SSH config | chezmoi (`home/`) |
| Desktop settings | KDE Plasma keys (shortcuts, KWin, theme, splash); Windows user registry (HKCU) | `kwriteconfig6`, PowerShell |
| System settings | GRUB, SDDM, Plymouth, pacman options (drop-in), boot theme packages; Windows machine registry (UTC clock, Fast Startup off), OpenSSH agent service off, NVIDIA App; debloat *(planned)* | second chezmoi instance (`root/`), PowerShell |
| Assets | Wallpapers (private Git repo, set on KDE and Windows), Nerd Fonts | chezmoi external, `plasma-apply-wallpaperimage` / `SystemParametersInfo`, Scoop/paru |
| Sync & capture | "Repository changed" notifications with a *Sync now* button, `dots sync`; `dots capture` picks local changes and commits them to `main` | systemd user timer + `notify-send`, Scheduled Task + Windows toast, `dots capture` |

It does **not** install the OS, back up personal data, or replace app-native sync
(VS Code Settings Sync, browser sync, Steam Cloud, Discord).

## Platforms

| Platform | Status |
|---|---|
| Windows 11 | Primary |
| CachyOS (KDE Plasma 6) | Primary |
| Arch Linux, Ubuntu desktop (KDE), Ubuntu WSL, macOS, NixOS | Planned |
| Fedora | Not supported |

## Quick start

On a freshly installed OS, download the bootstrap script, read it, then run it.

**CachyOS**

```bash
curl -fsSLo /tmp/dots-bootstrap.sh https://raw.githubusercontent.com/TienHwng/dotfiles/main/scripts/unix/bootstrap.sh
less /tmp/dots-bootstrap.sh && bash /tmp/dots-bootstrap.sh
```

**Windows 11**

Run from a normal (not elevated) PowerShell window; Scoop refuses an administrator shell.

```powershell
irm https://raw.githubusercontent.com/TienHwng/dotfiles/main/scripts/windows/bootstrap.ps1 -OutFile $env:TEMP\dots-bootstrap.ps1
notepad $env:TEMP\dots-bootstrap.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\dots-bootstrap.ps1
```

A fresh Windows only has Windows PowerShell 5.1, so the command above uses `powershell`. If
PowerShell 7 is already installed, `pwsh -NoProfile -ExecutionPolicy Bypass -File ...` works
the same. The packages step installs PowerShell 7, and the shell step points its profile at
the shared `~/.config/powershell/profile.ps1`; use PowerShell 7 from then on.

The bootstrap installs `chezmoi` (plus `git`, `gum`, and `jq` on CachyOS), clones this
repository into the chezmoi source directory, and starts `dots bootstrap`. Each step shows a preview
and asks before running; you can skip any step. At the end it prints the manual checklist
(sign in to Bitwarden and to apps with their own sync).

Preview everything without changing the machine:

```bash
./scripts/unix/bootstrap.sh --dry-run
```

## Daily use

| Command | Purpose |
|---|---|
| `dots bootstrap` | Set up a fresh machine, or re-run safely on a configured one |
| `dots sync` | Pull repository changes, review the diff, apply |
| `dots capture` | Pick local changes (files, KDE keys, registry values, packages), review the diff, commit to `main` and push |
| `dots packages [--diff]` | Install missing packages / list packages not in the manifest |
| `dots system` | Review and apply system-level settings (sudo/admin) |
| `dots status` | Behind/ahead, drift count, sync timer state |
| `dots <step>` | Run one bootstrap step on its own, e.g. `dots desktop` (also repairs the Kuro splash) |
| `dots doctor` | Health checks |
| `dots update` | Upgrade installed packages and fonts |
| `dots backup` | Tarball of the repository plus the local, untracked chezmoi configs |
| `dots cleanup` | Clear package-manager and chezmoi caches |

`bootstrap`, `packages`, `sync`, `status`, `capture`, `doctor`, `update`, `backup`, and `cleanup` work
today on both OSes; `system` previews as you, then applies with sudo (Linux) or in an
administrator window (Windows). At login and every 6 hours a timer
(Linux) or Scheduled Task (Windows) runs `dots sync --check --notify`: it only fetches, and
notifies with a *Sync now* button when new commits arrived. On CachyOS `~/.local/bin/dots` is a
chezmoi-managed symlink to `scripts/unix/dots`. On Windows, `dots` is a function in the shared
PowerShell profile (`~/.config/powershell/profile.ps1`) that runs `scripts/windows/dots.ps1`,
with PowerShell-style options (`dots bootstrap -DryRun`, `dots packages`). `dots packages --diff`
(`dots packages -Diff` on Windows) lists packages installed outside the manifest. `just` / `make` recipes remain available (`make help` lists them).

## Configuration

What a machine gets is data, not code: the scripts and `dots` read these YAML files through
chezmoi, so changing a package, a KDE key or a registry value means editing one file. The
comment at the top of each file documents its fields.

| File | What it controls | Applied by |
|---|---|---|
| `home/.chezmoidata.yaml` | `features.*` switches (`installFonts`, `setupShell`, `desktop`, `wallpapers`: `false` skips that step), the wallpaper repository and current image, the SSH agent mode (`accounts.ssh`) | `dots bootstrap`; the `wallpaper` and `accounts` steps |
| `home/.chezmoidata/packages.yaml` | Packages per manager (`mapped` entries name the package for paru, apt, brew, winget, Scoop; plus per-manager lists; `gui: true` skipped on headless machines, `vendor: ASUS` only on ASUS hardware) and Nerd Fonts | `dots packages`, the `fonts` step |
| `home/.chezmoidata/kde.yaml` | KDE Plasma: global theme, one entry per key (`file`, `group`, `key`, `value`: shortcuts, KWin, splash, power, default browser), fcitx5 input methods, and per-machine keys under `machines.<hostname>` (touchpad, mouse) | the `desktop` step (`scripts/unix/setup-desktop.sh`) |
| `home/.chezmoidata/windows.yaml` | Registry values: `user` (HKCU) and `machine` (HKLM); `nvidia.app`: the pinned NVIDIA App installer (version, URL, SHA-256) | the `desktop` step on Windows; `dots system` (admin) |

For example, to keep Night Color on, add one line to `kde.yaml`:

```yaml
    - { file: kwinrc, group: [NightColor], key: Active, value: "true" }
```

Then preview and apply it (or re-run `dots bootstrap`, which runs the same step):

```bash
./scripts/unix/setup-desktop.sh --dry-run
./scripts/unix/setup-desktop.sh
```

- KDE `*rc` files and registry keys are managed **per key**, never as whole files: Plasma
  and Windows rewrite them constantly.
- Keys tied to one machine's hardware go under `kde.machines.<hostname>.settings`, where
  `<hostname>` is what `chezmoi execute-template '{{ .chezmoi.hostname }}'` prints. Only that
  machine applies them; an entry with the same file, group and key as a shared one replaces it
  there:

  ```yaml
  kde:
    machines:
      HwngPC:
        settings:
          - { file: kcminputrc, group: [Libinput, "1267", "12410", "ELAN1203:00 04F3:307A Touchpad"], key: NaturalScroll, value: "true" }
  ```

- Quote values that must stay strings (`"true"`, `"0.400"`, `"1267"`); unquoted, YAML reads
  them as booleans or numbers.
- Identity (name, emails, GitHub username) is not in these files: see the next section.

## Machine-specific values and secrets

`home/.chezmoi.toml.tmpl` asks once for Git name, Git email, GitHub username, and SSH email.
The answers stay in the local, untracked `~/.config/chezmoi/chezmoi.toml`. The repository is
public and never contains identity, keys, or tokens.

SSH keys live in the Bitwarden vault and the Bitwarden desktop app serves them as an SSH agent
(Settings > Enable SSH agent); no private key is written to disk. The `accounts`
bootstrap step logs in to GitHub with `gh` (git stays on HTTPS), checks that the agent holds a key
that GitHub accepts, and offers to add it. Headless machines can set
`accounts.ssh.agent: file` to use a passphrase-protected key file instead. Templates can read
secrets from Bitwarden through chezmoi's `bitwarden*` functions; none does yet.

`home/dot_gitconfig.tmpl` and `home/dot_ssh/private_config.tmpl` are the only writers of
`~/.gitconfig` and `~/.ssh/config`.

## Repository layout

```text
.
├── .chezmoiroot          # "home": chezmoi reads home/ as its source state
├── docs/                 # vision, design, roadmap (start with docs/README.md)
├── home/                 # user-level chezmoi source
├── root/                 # system-level chezmoi source (second instance, Linux)
├── kde/                  # Plasma packages (Kuro splash), installed by the desktop step
├── scripts/unix/         # Bash scripts and the dots CLI
├── scripts/windows/      # PowerShell scripts and dots.ps1 (Windows PowerShell 5.1 and 7)
├── tests/                # Bats, Pester (tests/windows), template validation
├── .github/workflows/    # CI
├── Justfile, Makefile    # identical convenience recipes
```

## Development

```bash
make validate   # syntax + lint + tests + template rendering + secret scan (the Ubuntu CI job, minus PowerShell parse)
make test-windows lint-windows   # Pester + PSScriptAnalyzer (needs pwsh; the Windows CI job)
make test       # bats tests
make lint       # shellcheck + shfmt -d -i 2 -ci -bn
make templates  # render chezmoi templates in a temporary HOME
make secrets    # gitleaks scan of the full history
make hooks      # enable the gitleaks pre-commit hook for this clone
make preview    # chezmoi apply --dry-run --verbose
```

Tests run in a temporary `$HOME` with mocked binaries and never provision the machine.
CI never installs packages, elevates privileges, or applies `root/`.

Design documents: [docs/README.md](docs/README.md).
