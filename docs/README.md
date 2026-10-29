# Documentation index

Read this file first. It tells you which document answers which question.

| If you need to… | Read |
|---|---|
| Know the owner's preferences, decisions, the machine, and traps already hit (shared agent memory) | [memory.md](memory.md) |
| Pick up the work on another machine (current state, next steps on Windows) | [handoff.md](handoff.md) |
| Understand what the project is for, its principles, and what it will never do | [vision.md](vision.md) |
| Implement or change anything (architecture, data model, `dots` commands, file layout, rules) | [design.md](design.md) |
| Know what exists today, what to build next, open questions, and risks | [roadmap.md](roadmap.md) |
| Run, lint, or test the repository | [../CLAUDE.md](../CLAUDE.md) and [../README.md](../README.md) |

## Status tags

Every feature in these documents carries one tag:

| Tag | Meaning |
|---|---|
| `[Implemented]` | Exists in the repository today and is covered by tests or CI. |
| `[Planned: Pn]` | Designed and scheduled for roadmap phase `Pn`. Not present yet. |
| `[Future]` | Accepted idea with no phase yet. Do not build it unless asked. |

If a document and a test disagree, **the test is the source of truth** until the
roadmap phase that changes the behaviour is merged. Update the test and the
document in the same change.

## Glossary

| Term | Meaning |
|---|---|
| `dots` | The single user-facing CLI (`scripts/unix/dots` for Bash, `scripts/windows/dots.ps1` for PowerShell 7). |
| User instance | The normal chezmoi instance. Source `home/`, target `$HOME`. |
| System instance / `chezmoi-root` | A second chezmoi instance. Source `root/`, target `/`, run with sudo. Linux only. |
| Manifest | `home/.chezmoidata/packages.yaml`: the single package list with per-OS name mapping. |
| Machine data | Values chezmoi knows about the current machine: built-ins (`.chezmoi.os`, hostname) plus prompted values stored in the untracked local chezmoi config. |
| Drift | Any difference between the repository and the live machine: changed managed files, KDE keys, registry values, or packages installed outside the manifest. |
| Capture | Moving chosen drift from the machine back into the repository (`dots capture`). |
| Primary platform | Windows 11 and CachyOS. Everything else is planned. |
