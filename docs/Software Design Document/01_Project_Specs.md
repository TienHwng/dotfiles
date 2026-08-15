# 01 - PROJECT_SPEC.md

> Project Specification
>
> Version: 1.0
> Status: Draft
> Audience:
>
> - Project owner
> - AI coding assistants
> - Future contributors

---

# 1. Introduction

## 1.1 Purpose

This document defines the technical specification of the Dotfiles Framework.

Unlike a traditional dotfiles repository, this project is designed as a complete Development Environment Framework capable of provisioning and maintaining an entire workstation.

The repository must support:

- Machine bootstrap
- Environment configuration
- Package management
- Application configuration
- Health checking
- Updating
- Backup
- Cross-platform support

This document acts as the source of truth for all future development.

---

# 2. Project Goals

The project should satisfy the following goals.

## Functional Goals

✓ Install a complete development environment.

✓ Configure applications automatically.

✓ Support multiple operating systems.

✓ Be safe to run repeatedly.

✓ Be modular.

✓ Be maintainable.

✓ Be easy to extend.

---

## Non-functional Goals

✓ Fast

✓ Reliable

✓ Readable

✓ Testable

✓ Documented

✓ Production quality

---

# 3. Supported Platforms

Current

- Arch Linux
- CachyOS

Planned

- Ubuntu
- Fedora
- Debian
- macOS
- Windows

Experimental

- WSL

Platform-specific code must be isolated.

---

# 4. Repository Structure

The repository should follow this structure.

```text
dotfiles/

├── install.sh
│
├── docs/
│
├── scripts/
│
├── packages/
│
├── fonts/
│
├── themes/
│
├── wallpapers/
│
├── assets/
│
├── tests/
│
├── home/
│
├── dot_config/
│
├── .chezmoi.toml
│
└── README.md
```

---

# 5. Directory Responsibilities

## docs/

Contains documentation only.

Never place executable code here.

Examples

- Architecture
- Roadmap
- Bootstrap
- Contribution Guide

---

## scripts/

Contains executable scripts.

Each script must have one responsibility.

Good

```
bootstrap.sh
```

Good

```
doctor.sh
```

Bad

```
everything.sh
```

---

## packages/

Contains package definitions.

No Bash logic.

Examples

```
arch.txt

ubuntu.txt

brew.txt

winget.json
```

---

## fonts/

Contains font installers.

No package management logic.

---

## themes/

Stores reusable themes.

Examples

- Catppuccin
- Tokyo Night
- Gruvbox

---

## assets/

Stores project assets.

Examples

- screenshots
- logos
- icons

---

## tests/

Stores automated tests.

Examples

Bootstrap validation

Script tests

Smoke tests

---

## home/

Chezmoi managed files.

---

## dot_config/

Chezmoi configuration files.

---

# 6. High-Level Components

The project consists of six independent components.

```
Bootstrap

↓

Package Manager

↓

Chezmoi

↓

Configuration

↓

Maintenance

↓

Automation
```

Every component should be replaceable.

---

# 7. Component Responsibilities

## Bootstrap

Responsible for

- first installation
- dependency checks
- provisioning

Must NOT contain package definitions.

---

## Package Manager

Responsible for

- installing packages
- updating packages

Must NOT configure applications.

---

## Chezmoi

Responsible for

- dotfiles
- templates
- secrets
- machine-specific config

Must NOT install software.

---

## Maintenance

Responsible for

- update
- doctor
- cleanup
- backup

Must NOT modify bootstrap.

---

## Automation

Responsible for

- CI
- formatting
- linting
- release

---

# 8. Bootstrap Flow

```
User

↓

install.sh

↓

bootstrap.sh

↓

Detect OS

↓

Install package manager

↓

Install Git

↓

Install chezmoi

↓

Install packages

↓

chezmoi apply

↓

Install fonts

↓

Configure shell

↓

Done
```

---

# 9. Functional Requirements

The framework shall provide the following commands.

## install

Purpose

Provision a new machine.

---

## doctor

Purpose

Verify system health.

Checks

- Git
- Shell
- Package manager
- Fonts
- Required applications

---

## update

Purpose

Update the entire environment.

---

## backup

Purpose

Backup important data.

---

## restore

Purpose

Restore backups.

---

## cleanup

Purpose

Remove unused files.

---

## theme

Purpose

Switch themes.

---

# 10. Configuration Philosophy

Every configuration must have a single source of truth.

Example

```
Theme

↓

theme.toml

↓

kitty

↓

fastfetch

↓

tmux

↓

btop
```

Never duplicate configuration.

---

# 11. Logging Standard

Every script should produce readable logs.

Example

```
[INFO]

[WARNING]

[SUCCESS]

[ERROR]
```

No raw echo spam.

---

# 12. Error Handling

Scripts should never silently fail.

Bad

```
command
```

Good

```
command

↓

Check exit code

↓

Handle failure

↓

Display useful message
```

---

# 13. Coding Standards

Language

Bash

Shell

POSIX where possible.

Use Bash only when necessary.

Indentation

4 spaces

Variable naming

snake_case

Function naming

snake_case

Constants

UPPER_CASE

Private helper functions

_prefix

---

# 14. Forbidden Practices

Never

Duplicate code.

Never

Hardcode usernames.

Never

Hardcode paths.

Never

Use magic numbers.

Never

Modify package lists inside scripts.

Never

Mix package installation and configuration.

Never

Write giant scripts.

---

# 15. Script Design Rules

Every script should

Have one purpose.

Be idempotent.

Return useful exit codes.

Use shared logging.

Use shared helper functions.

Avoid duplicated logic.

---

# 16. Dependencies

Preferred

```
curl

git

chezmoi
```

Optional

```
gum

fzf

jq

yq
```

Never require unnecessary tools.

---

# 17. Quality Requirements

Every script should pass

- shellcheck

Formatting should pass

- shfmt

Documentation must be updated with every feature.

---

# 18. Repository Lifecycle

```
Clone

↓

Bootstrap

↓

Daily usage

↓

Update

↓

Backup

↓

Upgrade

↓

Repeat
```

---

# 19. Future Features

Planned

- Windows support
- macOS support
- Theme manager
- Secrets manager
- Plugin manager
- Wallpaper manager
- GUI installer
- TUI installer
- GitHub Actions
- Self-update
- Rollback
- Telemetry (disabled by default)

---

# 20. AI Development Guidelines

When implementing features, AI assistants must follow these rules.

Do not redesign the architecture.

Do not rename directories without reason.

Do not merge unrelated scripts.

Always reuse helper functions.

Always prefer modularity.

Always document public functions.

Always preserve backward compatibility.

Every new feature should be implemented as an independent module whenever possible.

Large refactors must be proposed before implementation.

---

# 21. Acceptance Criteria

The project is considered successful when:

A new machine can be configured using a single command.

Bootstrap can be executed multiple times safely.

Adding a new operating system requires only implementing a new package backend.

All scripts remain under a reasonable size.

Documentation remains synchronized with implementation.

No secrets are committed.

Every important action is automated.

The repository remains understandable by someone reading it for the first time.

---

# End of Specification