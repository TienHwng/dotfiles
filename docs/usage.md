# Using `dots`

`dots` is the one command for setting up and maintaining a machine from this repository.
This guide shows what to type for everyday jobs, then lists every command, step, data file
and environment variable. Design details are in [design.md](design.md).

---

## 1. Basics

| | CachyOS / Arch | Windows 11 |
|---|---|---|
| Where `dots` comes from | `~/.local/bin/dots`, a link to `scripts/unix/dots` | a function in the PowerShell 7 profile that runs `scripts\windows\dots.ps1` |
| Before the `shell` step made it available | `~/.local/share/chezmoi/scripts/unix/dots` | `pwsh -File $env:USERPROFILE\.local\share\chezmoi\scripts\windows\dots.ps1` |
| Option spelling | `--dry-run`, `--non-interactive`, `--skip STEP` | `-DryRun`, `-NonInteractive`, `-Skip step,...` |
| Repository | `~/.local/share/chezmoi` | `%USERPROFILE%\.local\share\chezmoi` |

Every command that changes something shows a preview (a list or a diff) and asks first.
`--dry-run` / `-DryRun` only shows the preview. `dots help` prints the short reference.
Prompts use `gum` when it is installed; `DOTS_NO_GUM=1` switches to plain prompts.

---

## 2. Everyday jobs

### A notification says the repository changed

At login and every 6 hours the machine checks GitHub (it never applies anything by itself).
Click **Sync now**, or run:

```bash
dots sync
```

It shows the new commits, asks before pulling, then runs only the steps whose files changed
(for example a new package runs `packages`, a KDE change runs `desktop`), each with its preview.
If it refuses because the repository has local changes, run `dots capture` first.

### See how this machine stands

```bash
dots status
```

Branch, commits behind or ahead of GitHub, files changed locally, chezmoi drift, timer or task.

```bash
dots doctor
```

Health checks: required tools, shell setup, the manifest, the SSH agent, the sync timer or task,
the Plasma packages (Kuro splash), Git hooks, `chezmoi doctor`.

### You changed something on this machine and want to keep it

```bash
dots capture
```

One list of everything that differs from the repository. Pick what to keep:

| Kind | What it is | What happens when picked |
|---|---|---|
| `file` | a file changed in the repository (on Linux dotfiles are links into it, so editing `~/.zshrc` lands here) | staged |
| `re-add` | a dotfile chezmoi copied and you edited (Windows, and templates or private files on Linux) | copied back with `chezmoi re-add` |
| `kde` | a KDE setting in `kde.yaml` whose value changed | the new value is written into `kde.yaml` |
| `kde-pkg` | the Kuro splash (or another Plasma package) changed, e.g. after *Get New* | the installed copy replaces `kde/…` |
| `registry` | a Windows registry value in `windows.yaml` that changed | the new value is written into `windows.yaml` |
| `packages` | apps installed outside the manifest | a second list: add them to the manifest, or uninstall them |

Then it shows the diff, asks for a commit message, commits to `main` and pushes. Answering no
leaves your edits in place and commits nothing. `dots capture --dry-run` only lists.

### You changed a KDE setting that the repository does not track yet

```bash
dots capture kde --discover
```

It takes a snapshot of the KDE config files, asks you to change the setting in System
Settings, takes a second snapshot, and lists every key that changed. Pick the ones to keep,
then choose "every machine" or "only this one".

### Install an app on every machine

Install it as usual, then run `dots capture` and add it from the `packages` list. Or edit
`home/.chezmoidata/packages.yaml` yourself and run `dots packages`. The other machines get it
at their next `dots sync`.

### Something on the desktop looks wrong

Run `dots doctor`, then the step it names, for example:

```bash
dots desktop
```

`dots <step>` runs one bootstrap step on its own, with its preview. `dots desktop` restores
the KDE settings (or Windows HKCU values) and reinstalls the Kuro splash if it is missing,
changed, or made of links that Plasma refuses.

### System settings (GRUB, Plymouth, SDDM, pacman; Windows clock, Fast Startup, NVIDIA App)

```bash
dots system
```

Shows a preview as you, then asks; on Linux it applies with `sudo`, on Windows in an
administrator window (UAC). It never runs without you at the keyboard.

### Before reinstalling an OS

```bash
dots backup --destination /run/media/$USER/<drive>
```

A tarball of the repository (with uncommitted work) and the local chezmoi configs, which hold
your Git name and email. Put it somewhere that survives the reinstall. Everything committed is
already on GitHub.

### Set up a freshly installed OS

- **CachyOS / Arch:** download and read `scripts/unix/bootstrap.sh`, then run it. It installs
  the prerequisites and chezmoi, clones the repository, and starts `dots bootstrap`.
- **Windows:** in Windows PowerShell:

  ```powershell
  irm https://raw.githubusercontent.com/TienHwng/dotfiles/main/scripts/windows/bootstrap.ps1 -OutFile $env:TEMP\dots-bootstrap.ps1
  notepad $env:TEMP\dots-bootstrap.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\dots-bootstrap.ps1
  ```

`dots bootstrap` walks through the steps in section 4. For each one: preview, then
**run / skip / quit**. Running it again on a configured machine is safe; finished steps report
nothing to change.

---

## 3. Command reference

| Command | Linux | Windows | What it does | Changes things? |
|---|---|---|---|---|
| `bootstrap` | `--dry-run --non-interactive --skip STEP` | `-DryRun -NonInteractive -Skip a,b` | All steps in order, each previewed and confirmed. Non-interactive runs skip `system`. | yes, per step |
| `<step>` | `dots desktop [--dry-run]` | `dots desktop [-DryRun]` | One step on its own (section 4). | yes, asks |
| `sync` | `--check [--notify]` | `-Check [-Notify]` | Pull new commits after showing them, then the steps their files need. `--check` only fetches and prints `behind N, ahead M`; `--notify` adds the desktop notification (the timer uses it). | yes, asks |
| `status` | | | Branch, behind/ahead, local edits, chezmoi drift, timer or task. | no |
| `capture` | `--dry-run`, `kde --discover` | `-DryRun` | Write chosen local changes back into the repository, commit to `main`, push. | yes, asks |
| `packages` | `--dry-run`, `--diff` | `-DryRun`, `-Diff` | Install missing packages from the manifest; `--diff` lists packages installed outside it and listed but missing. | yes, asks |
| `system` | `--dry-run` | `-DryRun` | System-level settings with sudo / admin (section 2). | yes, asks |
| `doctor` | | | Health checks; exits non-zero when a required check fails. | no |
| `update` | `--packages --fonts --dry-run` | `-Packages -Fonts -Upgrade -DryRun` | `chezmoi update` (pull and apply **without asking**), then optionally install missing packages (Windows `-Upgrade` upgrades them) and reinstall fonts. Prefer `dots sync` for repository changes. | yes |
| `backup` | `--destination DIR --dry-run` | `-Destination PATH -DryRun` | Tarball of the repository and local chezmoi configs (default `~/dotfiles-backups`, or `DOTFILES_BACKUP_DIR`). | writes the backup |
| `cleanup` | `--yes --dry-run` | `-Yes -DryRun` | Clear package-manager and chezmoi caches (Linux also the chezmoi binary in `~/.local/bin`). | yes, asks unless `--yes` |
| `help` | | | Short reference. | no |

---

## 4. Bootstrap steps

In this order; `dots <step>` runs one of them alone, except `packages`, `sync` and `system`,
which are commands of their own (`dots sync` pulls; the `sync` step itself is
`scripts/unix/setup-sync.sh` / `scripts\windows\setup-sync.ps1`).

| Step | Linux | Windows | Reads |
|---|---|---|---|
| `packages` | paru (repositories and AUR) | winget, then Scoop | `packages.yaml` |
| `git` | checks Git name and email, renders `~/.gitconfig` | same | local chezmoi config |
| `accounts` | `gh auth login` over HTTPS; Bitwarden SSH agent check | same | `.chezmoidata.yaml` (`accounts.ssh`) |
| `fonts` | Nerd Fonts from the release archives | Scoop `nerd-fonts` | `packages.yaml` (`nerdFonts`) |
| `shell` | zsh as login shell | `XDG_CONFIG_HOME` and the PowerShell 7 profile stub | `.chezmoidata.yaml` |
| `apply` | chezmoi diff, then apply (`home/`), then the zsh plugin repositories | chezmoi diff, then apply | `home/` |
| `desktop` | Kuro splash (copied from `kde/`), global theme, KDE keys, fcitx5 input methods | HKCU registry values, Explorer restart | `kde.yaml` / `windows.yaml` |
| `wallpaper` | clone or update `TienHwng/wallpapers`, set it on Plasma | same, set it on Windows | `.chezmoidata.yaml` (`wallpapers`) |
| `sync` | enable `dots-sync.timer` | register the `\dots\dots-sync` task and the *Sync now* protocol | |
| `system` | boot theme packages, then `/etc` from `root/` with sudo (GRUB, Plymouth, SDDM, pacman), GRUB and initramfs hooks | HKLM values (UTC clock, Fast Startup off), OpenSSH agent off, NVIDIA App, in an admin window | `root/`, `windows.yaml` |

---

## 5. Where settings live

Change the data, commit (or let `dots capture` do it), and the matching step applies it.

| To change | Edit | Applied by |
|---|---|---|
| Apps and CLI tools | `home/.chezmoidata/packages.yaml` | `packages` |
| Dotfiles (zsh, nvim, kitty, git, …) | files under `home/` (on Linux, editing `~/…` edits them directly) | `apply` |
| KDE settings, Plasma packages, fcitx5 | `home/.chezmoidata/kde.yaml`, `kde/` | `desktop` |
| Windows registry, NVIDIA App pin | `home/.chezmoidata/windows.yaml` | `desktop` (HKCU), `system` (HKLM) |
| Wallpaper repository and current picture | `home/.chezmoidata.yaml` (`wallpapers`) | `wallpaper` |
| Steps to turn off on this machine | `home/.chezmoidata.yaml` (`features`) | |
| GRUB, Plymouth, SDDM themes | `root/.chezmoidata/boot.yaml` | `system` |
| pacman options | `root/etc/pacman.d/dots.conf` | `system` |
| Your Git name and email | `~/.config/chezmoi/chezmoi.toml` (local, never committed) | `git` |

---

## 6. Environment variables

| Variable | Effect |
|---|---|
| `DOTS_NO_GUM=1` | Plain prompts instead of `gum`. |
| `NON_INTERACTIVE=1` | Never prompt (CI); `sync`, `capture` and `system` refuse to run. |
| `DOTFILES_HEADLESS=1` | Skip `gui: true` packages (WSL, servers). |
| `DOTFILES_VENDOR` | Override the detected hardware maker (`vendor:` packages). |
| `DOTFILES_PLATFORM` | Override the detected package platform (`arch`, `apt`, `brew`). |
| `DOTFILES_BACKUP_DIR` | Default destination of `dots backup`. |
| `TERMINAL` | Terminal the *Sync now* button opens on Linux (default kitty, then konsole). |

---

## 7. When something goes wrong

| Symptom | Do this |
|---|---|
| `dots sync` refuses: local changes | `dots capture` (or `git -C ~/.local/share/chezmoi stash`), then `dots sync` |
| `dots sync`: cannot fast-forward | the repository has local commits; push them or rebase by hand |
| Kuro splash missing | `dots doctor`, then `dots desktop`; the journal says why (`journalctl --user -o cat \| grep -a -i kuro`) |
| Vietnamese typing or another KDE setting lost | `dots desktop` |
| No notification about new commits | `dots doctor`; re-enable with `~/.local/share/chezmoi/scripts/unix/setup-sync.sh` (Windows: `scripts\windows\setup-sync.ps1`) |
| `dots capture` says "Captures commit to main" | `git -C ~/.local/share/chezmoi switch main` |
| A step failed halfway | run `dots <step>` again; every step is safe to repeat |
| Not sure what a command would do | add `--dry-run` / `-DryRun` |
