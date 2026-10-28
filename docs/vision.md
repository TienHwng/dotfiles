# Vision

## Purpose

The owner periodically wipes a disk and reinstalls an operating system **by hand** to
get rid of accumulated junk. This repository exists so that, right after that manual
reinstall, one command brings the machine back to the owner's working environment
(apps, configuration, desktop settings, system tweaks, wallpapers) without manual
setup, so they can get back to work.

It also keeps machines that are already running in line with the repository: they are
told when the repository changes and can pull those changes after reviewing them.

## Problem statement

1. Reinstalling an OS is cheap. Re-creating the environment by hand is slow and error-prone.
2. The owner uses Windows and Linux on the same hardware (dual-boot) and wants the
   cross-platform parts (git, editors, shell prompt, fonts, wallpapers) to match.
3. Only what is declared in the repository should come back after a reinstall.
   That is how junk is kept out.

## Principles

| # | Principle | What it means in practice |
|---|---|---|
| 1 | **The repository is the single source of truth** | If it is not in the repository (or fetched by it), it is not restored. |
| 2 | **One command to start, a confirmation at every step** | `dots bootstrap` drives everything, but each step shows what it will change (diff/preview) and asks before acting. Steps can be skipped. |
| 3 | **Unavoidable manual steps are listed, not hidden** | Signing in to Bitwarden or to apps that have their own sync is manual by nature. `dots` prints them as a checklist. |
| 4 | **Idempotent** | Running any step twice is safe and reports "already done" instead of failing. |
| 5 | **Preview before change** | Every mutating command supports a dry run that creates or modifies nothing. |
| 6 | **Declarative data, small scripts** | Lists of packages, KDE keys, and registry values live in YAML data. Scripts only read data and apply it. |
| 7 | **Manage keys, not whole files, when an app rewrites its own files** | KDE `*rc` files and the Windows registry are managed key by key to avoid noisy diffs. |
| 8 | **A public repository never contains a secret** | Secrets come from Bitwarden at render time. Machine identity stays in untracked local config. |
| 9 | **Share across OSes only what is truly cross-platform** | OS-specific desktop and system settings stay separate. |
| 10 | **Readable over clever** | Scripts are read years later. Prefer clear names and small functions. |

## Platforms

| Platform | Status |
|---|---|
| Windows 11 | Primary (target of current work) |
| CachyOS (KDE Plasma 6, Wayland) | Primary (target of current work) |
| Arch Linux | Planned (shares the Arch backend with CachyOS) |
| Ubuntu desktop (KDE / Kubuntu) | Planned |
| Ubuntu on WSL | Planned |
| macOS | Planned |
| NixOS | Planned |
| Fedora | **Not supported.** Existing Fedora code is to be removed. |

## Scope

In scope:

- CLI and dotfile configuration (shell, git, Neovim, terminal, prompt, SSH config).
- GUI application settings, unless the app has its own sync (see below).
- Desktop and OS settings: KDE Plasma, Windows registry (user and machine), fonts, wallpapers.
- System-level configuration: `/etc`, bootloader, display manager, Windows debloat and drivers.
- Installing applications on every platform from one manifest.
- Periodic "repository changed" notifications and capturing local changes back into the repository.

## Non-goals

The project will **not**:

- Install or reinstall an operating system, partition disks, create install media,
  or perform unattended OS installs. The owner does that by hand; `dots` starts afterwards.
- Back up personal data (documents, projects, game saves, photos other than wallpapers).
- Replace application sync that already exists (VS Code Settings Sync, browser sync,
  Steam Cloud, Discord). The repository only installs those apps.
- Become a package manager. It orchestrates pacman/paru, apt, winget, Scoop, and others.
- Replace chezmoi, git, or Bitwarden.
- Silently apply changes on a running machine. Sync notifies; the owner applies.

## Success criteria

1. On a freshly installed primary OS, with network access, `dots bootstrap` plus the
   printed manual checklist is enough to be back at work. No other setup is needed.
2. Running `dots bootstrap` again on a configured machine changes nothing and reports success.
3. After a day of normal use on KDE, the repository shows no drift that the owner did not cause.
4. A change made on one OS reaches the other OS of the dual-boot machine through
   `dots capture` → push → notification → `dots sync`.
5. No secret ever appears in the repository history (enforced by gitleaks).
6. Adding a package to every platform is one manifest entry.
