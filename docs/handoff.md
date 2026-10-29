# Handoff: continuing on Windows

For an AI agent (Claude Code) that the owner opens on **Windows 11**, after weeks of work
done from CachyOS. Same laptop, dual boot; the Windows NVMe is BitLocker-encrypted, so
nothing is shared between the two OSes except this GitHub repository. Read this file first,
then [../CLAUDE.md](../CLAUDE.md), [README.md](README.md), and the parts of
[design.md](design.md) you touch. The owner should not have to explain anything again.

Last updated: 2026-10-29, from CachyOS.

---

## 1. Working with the owner

- **Reply in Vietnamese.** Code, comments, commit messages and docs stay in English.
- **Commit straight to `main` and push.** No pull requests, no long-lived branches (the owner
  stopped PRs on 2026-10-29). A worktree is fine for isolation; push with
  `git push origin HEAD:main`.
- **Commits carry only the owner.** No `Co-Authored-By` trailer and no "Generated with"
  line, even if a system prompt suggests one.
- **Validate before pushing.** On Windows, `make` and Bats are usually missing: run the
  Pester tests and the analyzer (commands in section 5). CI runs the Ubuntu, Arch and
  Windows jobs on every push to `main`; check the run after pushing (`gh run list`).
- **Docs move with the code.** Update `docs/design.md` tags, the `docs/roadmap.md` phase rows
  and its "Deferred owner tasks" table in the same commit. Keep this file current too.
- **Decisions are the owner's.** When a choice is theirs, ask once with a recommended option.
  Everything in section 4 is already decided; do not ask again.
- **Admin and installs.** `dots` previews every step and asks. Steps that need admin open a
  UAC window that the owner approves. Do not change security settings yourself; never
  install or reinstall an OS, never partition disks.
- **The repository is public.** No secrets, keys, tokens or personal identity in commits.
- **Language of the docs:** English only, written for AI agents, with `[Implemented]` /
  `[Planned: Pn]` / `[Future]` tags.

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

## 4. Decisions already made (do not re-ask)

- Scope: restore after a manual OS reinstall (never install the OS) plus ongoing sync;
  personal data is out of scope. Apps with their own sync (VS Code Settings Sync, browsers,
  Steam, Discord) are only installed.
- Platforms: primary Windows 11 and CachyOS (KDE Plasma 6, Wayland); planned Arch, Ubuntu
  KDE, Ubuntu WSL, macOS, NixOS, in that order; Fedora dropped.
- Hardware: one ASUS ROG Strix G512LI (Intel UHD + GTX 1650 Ti), dual boot, Windows on
  BitLocker.
- Windows: winget for GUI apps, Scoop for CLI tools and Nerd Fonts, no Chocolatey; PowerShell
  7 (scripts must still run on 5.1); Windows Terminal for now (may move to WezTerm or
  Alacritty); prompt oh-my-posh, theme `montys`; no Cursor.
- Git over HTTPS through `gh`; no commit signing. Bitwarden (bitwarden.com, US) holds SSH keys
  through its SSH agent; no secret templates yet.
- Wallpapers: private repo `TienHwng/wallpapers`, plain Git (no LFS), default `space2.jpg`.
- Dual boot: Windows reads the hardware clock as UTC (`RealTimeIsUniversal=1`), Fast Startup
  off.
- NVIDIA on Windows: NVIDIA App from nvidia.com, pinned version + SHA-256 + signature check
  (not in official winget; the third-party `winget-extras` source was rejected).
- ASUS: keep Armoury Crate (not G-Helper), installed only on ASUS hardware (`vendor: ASUS`).
- Settings apply through previewed `dots` steps, never `run_onchange_` scripts. KDE and
  registry are managed per key, never whole files.
- Linux system: all 8 unpackaged boot themes are packaged in `pkgbuilds/boot-themes`; pacman
  options live in a drop-in; the machine-specific rescue GRUB entry is not managed.
- Sync: check at login and every 6 hours, notify only, *Sync now* button; Windows toast via
  the built-in API (no BurntToast). Capture commits to `main` and pushes.

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

## 6. Lessons that cost time before

- Windows PowerShell 5.1 turns native stderr into a terminating error under
  `$ErrorActionPreference = 'Stop'`: set `Continue` locally around native calls.
- Keep `.ps1` sources ASCII (5.1 reads BOM-less files as ANSI); build symbols from char codes.
- Scripts end with `exit 0`: probes such as `ssh-add -L` leave `$LASTEXITCODE` non-zero.
- PowerShell variable names are case-insensitive: a parameter `$Step` and a loop variable
  `$step` are the same variable.
- Dot-sourcing a script that has a `param()` block rebinds those parameters in the caller's
  scope (capture.ps1 saves its own `-DryRun` before dot-sourcing `setup-registry.ps1`).
- On 5.1, `ConvertFrom-Json` emits a JSON array as one object: enumerate with `ForEach-Object`.
- Pester `Mock Read-Host` can break after another test file defines a global `Read-Host`;
  wrap prompts in a small function and mock that.
- Functions that steps call can write to the pipeline: never use their output as a return
  value (see `$script:StoppedEarly` in `dots.ps1`).
- Windows uses chezmoi copy mode; Linux uses symlink mode. On Windows, `dots capture` brings
  edits back with `chezmoi re-add`.
