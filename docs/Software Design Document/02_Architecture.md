# 02 - ARCHITECTURE.md

> Architecture Design Document
>
> Version 1.0

---

# Overview

This document describes the internal architecture of the Dotfiles Framework.

The project is designed around modular components rather than monolithic scripts.

Every component has a single responsibility.

Every module communicates through stable interfaces.

The architecture prioritizes:

- Maintainability
- Readability
- Extensibility
- Testability

---

# Design Philosophy

The repository should behave like a software project rather than a collection of shell scripts.

Every responsibility belongs to exactly one module.

Instead of writing one large script, the project is divided into multiple layers.

```
CLI

↓

Bootstrap

↓

Services

↓

Providers

↓

Operating System

↓

Machine
```

---

# High-Level Architecture

```
                +----------------------+
                |      install.sh      |
                +----------+-----------+
                           |
                           |
                           v
                +----------------------+
                |    bootstrap.sh      |
                +----------+-----------+
                           |
      +--------------------+--------------------+
      |                    |                    |
      v                    v                    v

 Package Service      Font Service      Shell Service

      |                    |                    |

      v                    v                    v

 Package Backend      Font Backend      Shell Backend

      |                    |                    |

      +--------------------+--------------------+

                           |

                           v

                     Operating System
```

No service should directly communicate with another service.

Everything goes through bootstrap.

---

# Repository Layout

```
scripts/

├── bootstrap.sh
├── lib.sh
│
├── package/
│   ├── install.sh
│   ├── update.sh
│   ├── detect.sh
│   ├── arch.sh
│   ├── ubuntu.sh
│   ├── macos.sh
│   └── windows.sh
│
├── font/
│   ├── install.sh
│   └── verify.sh
│
├── shell/
│   ├── setup.sh
│   └── verify.sh
│
├── doctor/
│   ├── run.sh
│   ├── packages.sh
│   ├── fonts.sh
│   ├── shell.sh
│   └── chezmoi.sh
│
├── backup/
│
├── cleanup/
│
└── update/
```

Every directory represents one subsystem.

---

# Layered Architecture

The project consists of five logical layers.

Layer 1

CLI

Responsible for user interaction.

Examples

```
install.sh

update.sh
```

---

Layer 2

Orchestrators

Responsible for workflow.

Examples

```
bootstrap.sh

doctor.sh
```

Never implement business logic here.

---

Layer 3

Services

Responsible for one feature.

Examples

```
install packages

install fonts

backup

theme
```

Services should not know which operating system is being used.

---

Layer 4

Providers

Responsible for platform-specific implementation.

Examples

```
Arch

Ubuntu

macOS

Windows
```

Providers implement the same interface.

---

Layer 5

Operating System

Real machine.

---

# Dependency Rules

Allowed

```
CLI

↓

Bootstrap

↓

Service

↓

Provider

↓

Operating System
```

Forbidden

```
Provider

↓

Bootstrap
```

Forbidden

```
Package Service

↓

Theme Service
```

Forbidden

```
Doctor

↓

Package Backend
```

Dependencies always point downward.

---

# Bootstrap Flow

```
User

↓

install.sh

↓

bootstrap.sh

↓

detect_os()

↓

install_package_manager()

↓

install_git()

↓

install_chezmoi()

↓

install_packages()

↓

chezmoi apply

↓

install_fonts()

↓

setup_shell()

↓

done()
```

Each step should be independent.

---

# Service Architecture

Every service follows the same layout.

```
feature/

install.sh

verify.sh

remove.sh

update.sh
```

Example

```
font/

install.sh

verify.sh
```

Example

```
package/

install.sh

update.sh

detect.sh
```

Consistency is more important than optimization.

---

# Shared Library

All reusable logic belongs in

```
scripts/lib.sh
```

Examples

```
Logging

Error handling

OS detection

Prompt

Confirmation

Retry

Spinner

Color

Validation

Download

Temporary files
```

No duplicated helper functions are allowed.

---

# Logging Layer

Every script must use

```
info()

success()

warning()

error()

fatal()
```

Never use

```
echo "Installing..."
```

directly.

---

# Error Layer

Every failure should terminate gracefully.

Bad

```
Git failed.
```

Good

```
Git installation failed.

Reason:

Network unavailable.

Suggested action:

Check internet connection.
```

Errors should be actionable.

---

# Configuration Layer

Configurations are divided into two groups.

Managed

```
chezmoi
```

Generated

```
theme

cache

runtime
```

Never manually edit generated files.

---

# Package Layer

Package installation is abstracted.

Example

```
install_package git
```

should internally call

Arch

```
paru
```

Ubuntu

```
apt
```

macOS

```
brew
```

Windows

```
winget
```

The caller never knows.

---

# Theme Layer

Future architecture

```
theme.toml

↓

Theme Service

↓

kitty

↓

tmux

↓

fastfetch

↓

btop

↓

rofi

↓

waybar
```

Single source of truth.

---

# Extension Points

Future modules should plug into existing architecture.

Possible modules

```
Plugin Manager

Wallpaper Manager

Secrets Manager

Docker

SSH

VPN

Terminal

Desktop Environment

Window Manager
```

No existing code should require modification.

Only registration.

---

# Script Size Guideline

Ideal

<100 lines

Good

100–200

Acceptable

200–300

Review Required

300–500

Forbidden

>500

Split the script.

---

# Naming Convention

Directories

snake_case

Scripts

verb_object.sh

Examples

```
install_packages.sh

verify_shell.sh

backup_files.sh
```

Functions

snake_case

Variables

snake_case

Constants

UPPER_CASE

---

# State Management

The framework should avoid storing mutable state.

If state is necessary, store it inside

```
~/.local/share/dotfiles/
```

Never inside repository.

---

# Testing Strategy

Every major module should support

Verification

Example

```
doctor

↓

verify packages

↓

verify fonts

↓

verify shell
```

Installation should never be the only way to test.

---

# Future Architecture

Version 2

```
CLI

↓

Bootstrap

↓

Services

↓

Plugin System

↓

Providers
```

Version 3

```
CLI

↓

Service Registry

↓

Dynamic Modules

↓

Providers
```

No architectural rewrite should be necessary.

---

# AI Instructions

AI contributors must preserve the architecture.

Never bypass layers.

Never duplicate helper functions.

Never write monolithic scripts.

Every new feature should become a service.

Every platform-specific implementation belongs inside providers.

Never hardcode operating-system logic into shared services.

If a feature requires changes in multiple layers, update documentation first.

---

# Summary

The Dotfiles Framework follows a layered architecture.

Each layer has a clear responsibility.

Business logic is separated from operating-system implementation.

Shared functionality lives inside a common library.

The architecture is intentionally over-engineered for a personal project because long-term maintainability is prioritized over short-term convenience.

The repository should continue to scale without becoming harder to understand.