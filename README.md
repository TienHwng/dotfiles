# dotfiles

A personal Linux dotfiles repository managed with [GNU Stow](https://www.gnu.org/software/stow/).

This repository contains my configuration files for terminal-based development tools such as 
[Neovim](https://github.com/neovim/neovim), 
[tmux](https://github.com/tmux/tmux), 
[WezTerm](https://github.com/wez/wezterm), 
and [Zsh](https://github.com/zsh-users/zsh).

The main purpose of this repository is to make my development environment reproducible, portable, and easy to restore across different Linux distributions.

## Table of Contents

* [Overview](#overview)
* [Structure](#structure)
* [Requirements](#requirements)
* [Installation](#installation)
* [Usage](#usage)
* [Why GNU Stow?](#why-gnu-stow)
* [Adding New Dotfiles](#adding-new-dotfiles)
* [Removing Dotfiles](#removing-dotfiles)
* [Troubleshooting](#troubleshooting)
* [Recommended Tools](#recommended-tools)
* [License](#license)

## Overview

This repository follows a package-based dotfiles structure for [GNU Stow](https://www.gnu.org/software/stow/).

Each top-level directory is treated as an individual Stow package.
When a package is stowed, GNU Stow creates symbolic links from this repository to the correct locations inside the home directory.

For example:

```text
dotfiles/
└── nvim/
    └── .config/
        └── nvim/
```

will be linked to:

```text
~/.config/nvim
```

This allows all configuration files to stay version-controlled in one place while still appearing in the correct locations on the system.

## Structure

```text
dotfiles/
├── nvim/
│   └── .config/
│       └── nvim/
├── tmux/
│   └── .tmux.conf
├── wezterm/
│   └── .config/
│       └── wezterm/
├── zshrc/
│   └── .zshrc
└── README.md
```

Current packages:

| Package   | Target              | Description                                                 |
| --------- | ------------------- | ----------------------------------------------------------- |
| `nvim`    | `~/.config/nvim`    | [Neovim](https://github.com/neovim/neovim) configuration    |
| `tmux`    | `~/.tmux.conf`      | [tmux](https://github.com/tmux/tmux) configuration          |
| `wezterm` | `~/.config/wezterm` | [WezTerm](https://github.com/wez/wezterm) configuration     |
| `zshrc`   | `~/.zshrc`          | [Zsh](https://github.com/zsh-users/zsh) shell configuration |

## Requirements

Before using this repository, make sure the following tools are installed:

| Tool                                                  | Description                              |
| ----------------------------------------------------- | ---------------------------------------- |
| [Git](https://github.com/git/git)                     | Used to clone and manage this repository |
| [GNU Stow](https://www.gnu.org/software/stow/)        | Used to manage symbolic links            |
| [Zsh](https://github.com/zsh-users/zsh)               | Shell configuration                      |
| [tmux](https://github.com/tmux/tmux)                  | Terminal multiplexer                     |
| [Neovim](https://github.com/neovim/neovim)            | Text editor                              |
| [WezTerm](https://github.com/wez/wezterm)             | Terminal emulator                        |
| [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts) | Icon-enabled fonts for terminal UI       |

## Installation

### 1. Install GNU Stow

#### Ubuntu / Debian

```bash
sudo apt update
sudo apt install stow
```

#### Arch Linux

```bash
sudo pacman -S stow
```

#### Fedora

```bash
sudo dnf install stow
```

#### openSUSE

```bash
sudo zypper install stow
```

### 2. Clone the repository

```bash
git clone https://github.com/TienHungg/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### 3. Stow the packages

Stow all available packages:

```bash
stow -t ~ nvim tmux wezterm zshrc
```

Or stow packages individually:

```bash
stow -t ~ nvim
stow -t ~ tmux
stow -t ~ wezterm
stow -t ~ zshrc
```

## Usage

After stowing the packages, the configuration files will be available in their expected locations.

For example:

```text
~/.config/nvim
~/.tmux.conf
~/.config/wezterm
~/.zshrc
```

To reload Zsh configuration:

```bash
source ~/.zshrc
```

To reload tmux configuration inside an active tmux session:

```bash
tmux source-file ~/.tmux.conf
```

## Why GNU Stow?

[GNU Stow](https://www.gnu.org/software/stow/) is useful for managing dotfiles because it keeps the actual files inside this repository and creates symbolic links to the home directory.

This provides several benefits:

* Dotfiles remain organized in a single Git repository.
* Configurations can be reused across multiple Linux distributions.
* Files can be updated through Git instead of manual copying.
* Packages can be enabled or disabled independently.
* Existing configurations are easier to track and maintain.

## Important Note About `stow .`

This repository contains non-configuration files such as `README.md`.

Because of that, avoid running:

```bash
stow .
```

Instead, stow only the package directories:

```bash
stow -t ~ nvim tmux wezterm zshrc
```

This prevents unnecessary files like `README.md` from being symlinked into the home directory.

## Optional Install Script

You can create an `install.sh` script to automatically stow all package directories:

```bash
#!/usr/bin/env bash

set -e

cd "$(dirname "$0")"

for package in */; do
    package="${package%/}"
    echo "Stowing $package..."
    stow -t "$HOME" "$package"
done

echo "All packages have been stowed successfully."
```

Make the script executable:

```bash
chmod +x install.sh
```

Run it:

```bash
./install.sh
```

This script only stows directories, so files such as `README.md` are ignored automatically.

## Adding New Dotfiles

To add a new configuration package, create a directory that mirrors the target path inside your home directory.

For example, to add a [Starship](https://github.com/starship/starship) prompt configuration:

```bash
mkdir -p starship/.config
mv ~/.config/starship.toml starship/.config/starship.toml
```

Then stow it:

```bash
stow -t ~ starship
```

Commit the new package:

```bash
git add starship
git commit -m "add starship config"
git push
```

## Removing Dotfiles

To remove symlinks created by Stow, use the `-D` option.

Remove a single package:

```bash
stow -D -t ~ nvim
```

Remove all current packages:

```bash
stow -D -t ~ nvim tmux wezterm zshrc
```

This only removes the symbolic links.
It does not delete the actual files stored in this repository.

## Updating Dotfiles

To update the repository:

```bash
cd ~/dotfiles
git pull
```

If necessary, restow the packages:

```bash
stow -R -t ~ nvim tmux wezterm zshrc
```

The `-R` option restows the packages, which is useful after renaming, moving, or restructuring files.

## Troubleshooting

### Stow conflict error

If Stow shows a conflict like this:

```text
WARNING! stowing nvim would cause conflicts
```

it usually means a file or directory already exists at the target location.

For example:

```text
~/.config/nvim
```

To fix this, back up the existing configuration first:

```bash
mv ~/.config/nvim ~/.config/nvim.backup
```

Then run Stow again:

```bash
stow -t ~ nvim
```

### Preview Stow actions

To preview what Stow will do without making changes:

```bash
stow -n -v -t ~ nvim
```

### Restow a package

To recreate symlinks for a package:

```bash
stow -R -t ~ nvim
```

### Unstow a package

To remove symlinks for a package:

```bash
stow -D -t ~ nvim
```

## Recommended Tools

These dotfiles are designed around a terminal-based Linux workflow.

Recommended tools:

* [Neovim](https://github.com/neovim/neovim)
* [tmux](https://github.com/tmux/tmux)
* [WezTerm](https://github.com/wez/wezterm)
* [Zsh](https://github.com/zsh-users/zsh)
* [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh)
* [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
* [Starship](https://github.com/starship/starship)
* [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts)
* [GNU Stow](https://www.gnu.org/software/stow/)
* [fzf](https://github.com/junegunn/fzf)
* [ripgrep](https://github.com/BurntSushi/ripgrep)
* [fd](https://github.com/sharkdp/fd)
* [lazygit](https://github.com/jesseduffield/lazygit)

## Suggested Setup Flow

A typical setup on a new Linux machine:

```bash
sudo apt update
sudo apt install git stow zsh tmux neovim

git clone https://github.com/TienHungg/dotfiles.git ~/dotfiles
cd ~/dotfiles

stow -t ~ nvim tmux wezterm zshrc
```

After that, install a [Nerd Font](https://github.com/ryanoasis/nerd-fonts) and configure your terminal to use it.

Then restart the terminal or reload the shell:

```bash
source ~/.zshrc
```

## Notes

These dotfiles are primarily built for my personal Linux development environment.

They are public for reference, learning, and sharing.
Some configurations may require additional dependencies, plugins, fonts, or manual setup depending on the distribution and machine.

## License

This repository is open for learning and personal use.

Feel free to explore, copy, modify, or adapt the configuration to your own workflow.
