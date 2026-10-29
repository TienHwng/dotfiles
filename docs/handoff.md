# Handoff: continuing on Windows

For an AI agent (Claude Code) that the owner opens on **Windows 11**, after weeks of work
done from CachyOS. Same laptop, dual boot; the Windows NVMe is BitLocker-encrypted, so
nothing is shared between the two OSes except this GitHub repository. Read this file first,
then [memory.md](memory.md) (also loaded through [../CLAUDE.md](../CLAUDE.md)),
[README.md](README.md), and the parts of [design.md](design.md) you touch. The owner should not have to explain anything again.

Last updated: 2026-10-29, from CachyOS.

---

## 1. Working with the owner

See [memory.md](memory.md) section 1 (loaded through `CLAUDE.md`): reply in Vietnamese,
commit straight to `main` and push, no co-author line, docs in the same commit, ask only for
the owner's decisions, the owner runs admin steps. On Windows, validate with the Pester and
analyzer commands in section 5 before pushing, then check the CI run (`gh run list`).

## 2. Where things stand

Every roadmap phase P0–P7 is written and tested in CI. What has run for real:

| Area | CachyOS | Windows |
|---|---|---|
| Bootstrap, packages, dotfiles (P1–P3) | Daily use | **Never run** |
| Wallpaper (P4) | Done | Not run |
| KDE keys / HKCU registry (P5a/P5b) | Done | Not run |
| `dots system` (P5b/P5c/P6) | Done 2026-10-29: 8 theme packages, pacman drop-in, broken `IgnorePkg` line gone, rescue GRUB entry removed, GRUB/Plymouth/SDDM fine after reboot | Not run (UTC clock, Fast Startup off, OpenSSH agent off, NVIDIA App) |
| Sync timer / task (P7a) | Timer enabled | Not registered |
| Capture (P7b) | Dry-run only | Not run |
| Kuro splash | Moved to `kde/plasma/look-and-feel/a2n.kuro`, copied as real files by the desktop step (Plasma refused the chezmoi symlinks, so the theme had vanished) | Not applicable |
| Bitwarden SSH agent (PoC-3) | Not installed yet | Not installed yet |

The authoritative list of open items is the "Deferred owner tasks" table in
[roadmap.md](roadmap.md). The Windows part of it is section 3 below.

## 3. What to do on Windows, in order

The owner starts from the README quick start in **Windows PowerShell 5.1** (downloads
`bootstrap.ps1`, which installs Git, chezmoi, gum, jq and PowerShell 7, clones this
repository to `%USERPROFILE%\.local\share\chezmoi`, and hands over to `dots.ps1 bootstrap`).
Then they open Claude Code in that folder. From there:

1. **Check the clone.** `git -C $env:USERPROFILE\.local\share\chezmoi status -sb` should be
   `main...origin/main`. If bootstrap stopped early, run it again; every step is idempotent.
2. **Walk `dots bootstrap` with the owner** (`pwsh`, then `dots bootstrap`; the `dots`
   function comes from the shared profile after the `shell` step, before that use
   `pwsh -File scripts\windows\dots.ps1 bootstrap`). Steps and what to check:
   - `packages`: winget then Scoop. Check that `Asus.ArmouryCrate` is not reinstalled when the
     BIOS already installed Armoury Crate (`winget list --id Asus.ArmouryCrate`); if winget
     does not see it, note it and decide with the owner.
   - `git`, `accounts`: `gh auth login` over HTTPS. Bitwarden is optional for now (PoC-3 is
     deferred); if the owner skips it, the accounts step warns and continues.
   - `fonts`, `shell` (`XDG_CONFIG_HOME`, profile stub), `apply`.
   - `desktop`: HKCU values from `home/.chezmoidata/windows.yaml` (file extensions, hidden
     files, dark apps); Explorer restarts.
   - `wallpaper`: clones the private `TienHwng/wallpapers` through the gh credential helper
     and sets `space2.jpg`.
   - `sync`: registers the Scheduled Task `\dots\dots-sync` and the `dots-sync:` protocol.
     Test with `Start-ScheduledTask -TaskPath '\dots\' -TaskName dots-sync` after a commit
     exists that Windows does not have yet: a toast with *Sync now* should appear and open
     Windows Terminal running `dots sync`.
   - `system` (UAC): HKLM `RealTimeIsUniversal=1` and `HiberbootEnabled=0`, OpenSSH
     Authentication Agent disabled, NVIDIA App from the pinned download.
3. **Run `dots system` a second time**: it must report nothing to change, and the NVIDIA App
   as installed. This also confirms the uninstall entry name `NVIDIA app` that
   `install-nvidia-app.ps1` looks for; if detection fails, find the real `DisplayName` with
   `Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* | ? DisplayName -like 'NVIDIA*'`
   and fix the pattern.
4. **PoC-4:** check whether OneDrive moved `Documents` (`[Environment]::GetFolderPath('MyDocuments')`);
   the profile stub follows that path, so only note the result.
5. **Clock:** after a reboot into CachyOS and back, both clocks must agree (UTC hardware clock).
6. **Win11Debloat (the last open P5c item).** Sit with the owner and go through the current
   Windows settings to pick the switches; they only remember "show hidden files" and "show
   file extensions", which are already HKCU values in `windows.yaml`. Facts already gathered:
   release tag `2026.08.24` (its only asset is `Get.ps1`, so pin the tag's source archive
   `https://github.com/Raphire/Win11Debloat/archive/refs/tags/2026.08.24.zip`, SHA-256
   `00d1487b2e9b9691653774cc781ed3844e4b2fd5b0d91c32f6f78aa8c7892bd4`), upstream defaults
   are 17 switches (`Config/DefaultSettings.json`), app removal is `-RemoveApps` with
   `Config/Apps.json`. Design rules: explicit switch list stored in the repository, plus
   `-Silent -CreateRestorePoint`; never `-RunDefaults`, never `irm | iex`; run it as step 4 of
   the Windows admin step (design L5). Tweaks that are plain registry values can go into
   `windows.yaml` instead.
7. **Capture once for real:** `dots capture -DryRun`, then `dots capture` if something should
   go back (winget/Scoop packages outside the manifest are offered too).
8. **Record the results:** update the deferred table and phase rows in `docs/roadmap.md`, and
   section 2 of this file; commit to `main` and push. Report to the owner in Vietnamese.

## 4. Decisions already made

See [memory.md](memory.md) section 3. Do not re-ask them.

## 5. Commands on Windows

```powershell
cd $env:USERPROFILE\.local\share\chezmoi
pwsh -NoProfile -File scripts\windows\dots.ps1 help
pwsh -NoProfile -File scripts\windows\dots.ps1 bootstrap -DryRun -NonInteractive
# Tests and lint (install once: Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser;
# Install-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -Scope CurrentUser)
pwsh -NoProfile -Command "Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester tests/windows"
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path scripts/windows -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"
```

## 6. Traps already hit

See [memory.md](memory.md) section 5 (PowerShell 5.1 stderr, ASCII sources, `exit 0`,
case-insensitive names, dot-sourced `param()` blocks, JSON arrays on 5.1, Pester and
`Read-Host`, WinRT toasts only on 5.1).
