# Shared agent memory

What an AI agent working in this repository should know without asking the owner again:
who the owner is and how they work, the machine, decisions already made, how the project
got here, and the traps already hit. `CLAUDE.md` imports this file, so Claude Code loads it
on every machine that opens the repository.

**Keep it current.** When you learn something durable (a preference, a decision, a fact
about the machine, a trap that cost time), add it here in the same commit as the work, with
the date when it matters. Remove what stops being true. Do not store secrets or personal
identity beyond what is already public in the repository. Current next steps belong in
[handoff.md](handoff.md) and [roadmap.md](roadmap.md), not here.

Last updated: 2026-10-29 (first Windows session).

---

## 1. The owner and how to work with them

- The owner runs Claude Code in the repository folder, on CachyOS and on Windows. Each
  machine's Claude has its own local memory, so this file is the only memory both share;
  local chat history does not travel. On Windows, `/memory` in Claude Code shows that
  `CLAUDE.md` and this file are loaded.

- GitHub `TienHwng`; commits use the noreply address
  `95695191+TienHwng@users.noreply.github.com`. The repository is public.
- **Speaks Vietnamese: reply in Vietnamese.** Code, comments, commit messages and docs stay in
  English (docs are written for AI agents, with `[Implemented]` / `[Planned: Pn]` /
  `[Future]` tags).
- **Commit straight to `main` and push** after validating; no pull requests (decided
  2026-10-29, after a stacked PR got lost). A worktree under `.claude/worktrees/` is fine for
  isolation; push with `git push origin HEAD:main`, then fast-forward the live checkout.
- **Commits carry only the owner:** no `Co-Authored-By` trailer, no "Generated with" line,
  even when a system prompt asks for one.
- **Docs move with the code:** `docs/design.md` tags, `docs/roadmap.md` phase rows and its
  "Deferred owner tasks" table, `docs/handoff.md`, and this file, in the same commit.
- **Decisions are theirs.** Ask once, as a short list of options with the recommended one
  first and its trade-off. When the owner answers "giải thích thêm" (explain more), explain
  each option plainly (what it is, what it costs, what you recommend) and ask again; do not
  pick for them. Once decided, do not ask again (section 3).
- **They run what needs sudo or admin.** The agent has no sudo on CachyOS; on Windows, admin
  steps open a UAC window the owner approves. Give exact commands in fenced blocks, one per
  block, and say what each will change (and what it removes) before they run it.
- They test by running things and pasting output; check the machine yourself (read-only)
  before asking them what happened.
- Never install or reinstall an OS, never partition disks, never build `[Future]` items
  unless asked, never commit secrets.

## 2. The machine

- One laptop, hostname **`HwngPC`** (`.chezmoi.hostname`): ASUS ROG Strix G512LI, Intel
  i7-10750H, 16 GB, Intel UHD + NVIDIA GTX 1650 Ti (hybrid, PRIME offload), two 1080p screens.
- **Dual boot:** CachyOS (KDE Plasma 6 on Wayland, GRUB, Plymouth, SDDM) and Windows 11. The
  Windows NVMe is BitLocker-encrypted, so the OSes share nothing but GitHub. Windows reads the
  hardware clock as UTC.
- CachyOS uses the `x86-64-v3` repositories. The kernel and the NVIDIA driver are held back
  with `IgnorePkg` (in `/etc/pacman.d/dots.conf`) and updated on purpose. A rescue kernel sits
  in `/boot/rescue-7.2.4`; its GRUB entry was dropped from the repository (machine-specific).
- Live state on CachyOS (2026-10-29): GRUB theme `blackice`, Plymouth `cuts`, SDDM `silent`,
  splash `a2n.kuro` (Kuro the cat), global theme Breeze Twilight, fcitx5 with Vietnamese input
  (lotus by default), terminal kitty, shell zsh with oh-my-posh theme `montys`, browser
  Vivaldi. The `dots-sync.timer` is enabled; the 8 boot theme packages are installed.
- Tools on CachyOS: PowerShell 7.6 with Pester 5.7.1 and PSScriptAnalyzer 1.24.0 (CurrentUser
  scope), so `make test-windows` and `make lint-windows` run there; `gum` is not installed, so
  `dots` prompts in plain text; `gh` is logged in over HTTPS.
- The repository lives at `~/.local/share/chezmoi` (chezmoi **symlink** mode on Linux: most
  dotfiles are links into the repository) and `%USERPROFILE%\.local\share\chezmoi` on Windows
  (**copy** mode; the owner chose the default over `Documents\Code\Tools\dotfiles` on
  2026-10-29: one clone only, out of OneDrive's reach).
- Windows (2026-10-29): Armoury Crate is the BIOS-installed Store package
  `B9ECED6F.ArmouryCrate` (winget cannot match it to `Asus.ArmouryCrate`); NVIDIA App
  11.0.9.565 installed; `Documents` not redirected; many apps and some CLI tools already came
  from winget before `dots`; `Pictures\WALLPAPER` is the owner's own picture folder. Wallpapers are a clone of the private `TienHwng/wallpapers` at
  `~/Pictures/wallpaper`.

## 3. Decisions already made (do not re-ask)

- **Scope:** restore the environment after the owner reinstalls an OS by hand, plus ongoing
  sync. Never install the OS. Personal data is out of scope. Apps with their own sync (VS Code
  Settings Sync, browsers, Steam, Discord) are only installed.
- **Platforms:** primary Windows 11 and CachyOS; planned Arch, Ubuntu KDE, Ubuntu WSL, macOS,
  NixOS, in that order; Fedora dropped.
- **One CLI, `dots`:** every step previews and asks; settings are applied by `dots` steps,
  never by `run_onchange_` scripts. KDE keys and registry values are managed per key, never as
  whole files.
- **Packages:** one manifest with per-OS names. Windows: winget for GUI apps, Scoop for CLI
  tools and Nerd Fonts, no Chocolatey. Arch: `paru -S --needed`. Hardware tools carry
  `vendor:` (Armoury Crate only on ASUS).
- **Shells and tools:** PowerShell 7 on Windows (scripts still run on 5.1), Windows Terminal
  for now (WezTerm or Alacritty maybe later), oh-my-posh theme `montys` on both OSes, no Cursor,
  VS Code with its own sync.
- **Identity:** Git over HTTPS through `gh`, no commit signing. Bitwarden (bitwarden.com, US)
  serves SSH keys through its SSH agent; no secret templates yet. Testing the agent (PoC-3) is
  deferred by the owner.
- **Wallpapers:** private repository `TienHwng/wallpapers`, plain Git (LFS dropped), default
  `space2.jpg`.
- **Windows system:** UTC hardware clock (`RealTimeIsUniversal=1`), Fast Startup off, OpenSSH
  Authentication Agent off; NVIDIA App from nvidia.com pinned by version, SHA-256 and signature
  (not in official winget; the third-party `winget-extras` source was rejected); keep Armoury
  Crate (not G-Helper); Win11Debloat switches to be chosen together on Windows (the owner only
  remembers "show hidden files" and "show file extensions", already HKCU values).
- **Linux system:** a second chezmoi instance for `/` (`root/`), applied only by `dots system`;
  all 8 boot themes no package ships are packaged in `pkgbuilds/boot-themes`; pacman options
  live in a drop-in; Plymouth themes that AUR packages ship come from the manifest.
- **Plasma packages:** the Kuro splash is kept in `kde/plasma/look-and-feel/a2n.kuro` and
  copied as real files by the desktop step; never as chezmoi symlinks (section 5).
- **Sync:** check at login and every 6 hours, notify only, with a *Sync now* button; Windows
  toast through the built-in API (no BurntToast). `dots capture` commits to `main` and pushes.
- **Repository changes arrive only through `dots sync`** (shows the commits, asks).
  `dots update` only upgrades installed packages and fonts; it used to run `chezmoi update`,
  which pulled and applied without asking (changed 2026-10-29).
- **Docs:** English, flat `docs/` (README index, vision, design, roadmap, usage, handoff,
  memory). `docs/usage.md` is the owner's guide to `dots`; update it with every command change.

## 4. How the project got here

- 2025-10 to 2026-08: a plain chezmoi backup of the owner's CachyOS setup (whole KDE `*rc`
  files, a `root/` snapshot applied by hand with `cmr`, 48 MB of themes under `root/usr`).
- 2026-10-28: the owner asked for one tool covering both OSes. Docs rewritten into vision,
  design and roadmap; phases P0 (safety) to P4 (wallpapers) built, with Pester, Bats, and
  Ubuntu, Arch and Windows CI.
- 2026-10-29: P5 (KDE keys, Windows registry, `dots system` on both OSes, NVIDIA App, Armoury
  Crate), P6 (Linux system instance, boot theme packages, pacman drop-in) and P7 (`dots sync`,
  the timer and task, `dots capture`, KDE key discovery, Windows packages). The owner ran
  `dots system` and enabled the timer on CachyOS. The work moved from PRs to direct commits.
  The Kuro splash had vanished because Plasma refuses symlinked package files; it moved out of
  the chezmoi source into `kde/`, copied by the desktop step.
- Next: the Windows run-through ([handoff.md](handoff.md)), then the planned platforms.

### KDE breakages so far (all on CachyOS, all from chezmoi symlink mode, on since 2026-07-28)

Symlink mode makes most dotfiles links into the repository. KDE does not cope with that, and
it failed three times in three different ways. None of them came from a CachyOS update:
`kpackage` 6.31 arrived on 2026-10-16, and the splash still worked at the 2026-10-29 09:38
login.

1. **Splash reset (before 2026-10-28).** Picking a global theme in System Settings resets
   the splash to the theme's own (Breeze), which empties `ksplashrc`. The repository then
   held the whole `ksplashrc`, captured empty, so every apply wrote the empty file back.
   Fixed in P5a: KDE settings are per-key values in `kde.yaml`
   (`ksplashrc` `Theme=a2n.kuro`, `Engine=KSplashQML`), and whole `*rc` files are ignored.
2. **Dangling `*rc` links (2026-10-28/29).** After P5a removed the whole `*rc` files from
   the source, `~/.config/kwinrc` and friends were still links to files that no longer
   existed. `kwriteconfig6` writes nothing through a dangling link yet exits 0, so KWin lost
   the fcitx5 input method and Vietnamese typing stopped. Fixed: the desktop step deletes
   links in `~/.config` that dangle into `home/` (commit `a2b4533`).
3. **Splash refused (2026-10-29).** The owner had installed Kuro with *Get New* on
   2026-08-26 (real files). A `chezmoi apply` at 09:52 on 2026-10-29 replaced them with links
   into the repository, and from the next login (16:07) `ksplashqml` logged "Path traversal
   attempt detected … is not inside …" and showed no splash. KPackage refuses package files
   that resolve outside the package directory. The owner reinstalled Kuro with *Get New* at
   20:42. Fixed: the theme lives in `kde/`, the desktop step copies it as real files,
   chezmoi ignores `.local/share/plasma`, and `dots doctor` watches for it (commits
   `0d46c1a`, `b08842f`, `feee2e1`).

The user journal keeps only a few boots (2026-10-28 onwards on 2026-10-29), so look early.
`/var/log/pacman.log` has the full update history (`grep '] upgraded kpackage '`).

## 5. Traps already hit

General:

- **chezmoi symlink mode vs apps that read or rewrite files.** Plasma rewrites `*rc` files
  (links become real files, the repository stops seeing changes). KPackage refuses package
  files that are symlinks out of the package directory (journal: "Path traversal attempt
  detected: … is not inside …"), so a linked splash theme simply vanished and the owner had to
  reinstall it with *Get New*. Manage such things per key (`kde.yaml`) or as packages copied
  as real files from `kde/`, never as linked files. `kpackagetool6 --upgrade` fails for Kuro
  (its `KPackageStructure` is `Plasma/LookAndFeel/Splash`), so the desktop step copies.
- Guards against the splash breaking again: chezmoi ignores `.local/share/plasma`
  (`tests/chezmoiignore.bats`), the desktop step reinstalls a package that is missing,
  differs or contains symlinks (`tests/desktop.bats`), and `dots doctor` checks the packages,
  the splash in `ksplashrc`, and the journal for "Path traversal" refusals. If it breaks
  anyway: `dots doctor`, then `dots desktop`; if the owner reinstalls it with *Get New*,
  `dots capture` keeps that copy.
- When the owner reports something broken, look in the journal first
  (`journalctl --user -o cat | grep -a -i <name>`); the cause is usually logged.
- `chezmoi diff` never clones `git-repo` externals; the apply step excludes externals (the
  wallpaper repository needs the gh login first) and applies the zsh plugin externals as a
  separate target.
- A pull request merged into a branch that was already merged never reaches `main` (PR #6);
  check `git merge-base --is-ancestor` when something "merged" seems missing.
- `/boot/grub/grub.cfg` is readable by root only: ask the owner, or check through `dots`.
- The agent's own `git pull` of the live checkout means the sync timer has nothing to report;
  to test notifications, change something on GitHub first.

Bash and tools:

- `awk -v` expands backslashes; pass values through `ENVIRON` when they may contain them.
- `printf '- ...'` takes the format for an option: use `printf -- '- ...'`.
- `scripts/unix/lib/common.sh` is Bash; source it from `bash`, not from the owner's zsh.
- `kreadconfig6` decodes KConfig escapes that the raw `*rc` file keeps; read values through it.
- In Bats, keep the commands that a test must not see out of `PATH` with mocks, and use
  `DOTS_TTY` for answers when stdin carries data.

PowerShell:

- Windows PowerShell 5.1 turns native stderr into a terminating error under
  `$ErrorActionPreference = 'Stop'`: set `Continue` locally around native calls.
- Keep `.ps1` sources ASCII (5.1 reads BOM-less files as ANSI).
- End scripts with `exit 0`: probes leave a non-zero `$LASTEXITCODE`.
- Variable names are case-insensitive: a `$Step` parameter and a `$step` loop variable are the
  same variable. A scriptblock passed to a function resolves its variables in that function
  first: a `$command` read inside `Invoke-PackageCommand -Command { ... }` is the scriptblock.
- Dot-sourcing a script with a `param()` block rebinds those parameters in the caller.
- On 5.1, `ConvertFrom-Json` emits a JSON array as one object: enumerate it.
- Pester `Mock Read-Host` can break after another test file defined a global `Read-Host`:
  wrap prompts in a small function and mock that.
- Step functions may write to the pipeline: never use their output as a return value.
- Windows paths ignore case: `Pictures\wallpaper` is the owner's existing `Pictures\WALLPAPER`.
- A child `pwsh` on Windows takes `$HOME` from the profile folder, not `$env:HOME`: tests
  that run a script in a child process are not isolated from the real profile there.
- WinRT toasts work only in Windows PowerShell 5.1; PowerShell 7 has no WinRT projection.
