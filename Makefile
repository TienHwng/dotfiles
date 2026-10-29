SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

BATS ?= bats
CHEZMOI_CMD ?= chezmoi
PWSH ?= pwsh
SHELLCHECK ?= shellcheck
SHFMT ?= shfmt
GITLEAKS ?= gitleaks

.PHONY: help bootstrap-unix bootstrap-unix-dry packages-unix update-unix \
	packages-unix-diff bootstrap-windows packages-windows update-windows preview doctor syntax \
	test lint templates secrets hooks validate test-windows lint-windows

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "Available targets:\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap-unix: ## Provision the current Unix user environment
	./scripts/unix/bootstrap.sh

bootstrap-unix-dry: ## Preview Unix bootstrap without changing the machine
	./scripts/unix/bootstrap.sh --dry-run

packages-unix: ## Install packages for the detected Unix platform from the manifest
	./scripts/unix/install-packages.sh

packages-unix-diff: ## List packages installed outside the manifest and manifest packages not installed
	./scripts/unix/install-packages.sh --diff

update-unix: ## Upgrade installed packages and fonts (asks first)
	./scripts/unix/update.sh

bootstrap-windows: ## Provision the Windows user environment
	$(PWSH) -NoProfile -File ./scripts/windows/bootstrap.ps1

packages-windows: ## Install WinGet and Scoop packages from the manifest
	$(PWSH) -NoProfile -File ./scripts/windows/install-packages.ps1

update-windows: ## Upgrade manifest packages and fonts (asks first)
	$(PWSH) -NoProfile -File ./scripts/windows/update.ps1

preview: ## Preview user-level chezmoi changes
	$(CHEZMOI_CMD) apply --dry-run --verbose

doctor: ## Run chezmoi diagnostics and verification
	$(CHEZMOI_CMD) doctor
	$(CHEZMOI_CMD) verify

syntax: ## Check Bash script syntax
	find scripts/unix tests -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
	bash -n scripts/unix/dots

test: ## Run isolated Bats tests
	$(BATS) tests

lint: ## Run ShellCheck and verify shfmt formatting
	find scripts/unix tests -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.bats' \) -print0 | xargs -0 $(SHELLCHECK)
	$(SHELLCHECK) -x scripts/unix/dots .githooks/*
	$(SHFMT) -d -i 2 -ci -bn scripts/unix tests .githooks

test-windows: ## Run the Pester tests for scripts/windows (needs pwsh + Pester 5)
	$(PWSH) -NoProfile -Command 'Invoke-Pester -Path tests/windows -CI -Output Detailed'

lint-windows: ## Run PSScriptAnalyzer on scripts/windows and tests/windows (needs pwsh)
	$(PWSH) -NoProfile -Command '$$r = @("scripts/windows", "tests/windows" | ForEach-Object { Invoke-ScriptAnalyzer -Path $$_ -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 }); $$r | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host; exit $$r.Count'

templates: ## Validate chezmoi templates in an isolated environment
	./tests/validate-templates.sh

secrets: ## Scan the full Git history for secrets with gitleaks
	$(GITLEAKS) git --redact --verbose

hooks: ## Enable the repository Git hooks (gitleaks pre-commit)
	git config core.hooksPath .githooks

validate: syntax lint test templates secrets ## Run every safe local validation
