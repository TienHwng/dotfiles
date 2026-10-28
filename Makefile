SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

BATS ?= bats
CHEZMOI_CMD ?= chezmoi
PWSH ?= pwsh
SHELLCHECK ?= shellcheck
SHFMT ?= shfmt

.PHONY: help bootstrap-unix bootstrap-unix-dry packages-unix update-unix \
	bootstrap-windows packages-windows update-windows preview doctor syntax \
	test lint templates validate

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "Available targets:\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap-unix: ## Provision the current Unix user environment
	./scripts/unix/bootstrap.sh

bootstrap-unix-dry: ## Preview Unix bootstrap without changing the machine
	./scripts/unix/bootstrap.sh --dry-run

packages-unix: ## Install packages for the detected Unix platform
	./scripts/unix/install-packages.sh

update-unix: ## Update the Unix dotfiles environment
	./scripts/unix/update.sh

bootstrap-windows: ## Provision the Windows user environment
	$(PWSH) -NoProfile -File ./scripts/windows/bootstrap.ps1

packages-windows: ## Install packages from packages/winget.txt
	$(PWSH) -NoProfile -File ./scripts/windows/install-packages.ps1

update-windows: ## Update the Windows dotfiles environment
	$(PWSH) -NoProfile -File ./scripts/windows/update.ps1

preview: ## Preview user-level chezmoi changes
	$(CHEZMOI_CMD) apply --dry-run --verbose

doctor: ## Run chezmoi diagnostics and verification
	$(CHEZMOI_CMD) doctor
	$(CHEZMOI_CMD) verify

syntax: ## Check Bash script syntax
	find scripts/unix tests -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n

test: ## Run isolated Bats tests
	$(BATS) tests

lint: ## Run ShellCheck and verify shfmt formatting
	find scripts/unix tests -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.bats' \) -print0 | xargs -0 $(SHELLCHECK)
	$(SHFMT) -d -i 2 -ci -bn scripts/unix tests

templates: ## Validate chezmoi templates in an isolated environment
	./tests/validate-templates.sh

validate: syntax lint test templates ## Run every safe local validation
