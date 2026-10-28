default:
    @just --list

# Unix/Linux/macOS
bootstrap-unix:
    ./scripts/unix/bootstrap.sh

bootstrap-unix-dry:
    ./scripts/unix/bootstrap.sh --dry-run

packages-unix:
    ./scripts/unix/install-packages.sh

update-unix:
    ./scripts/unix/update.sh

# Windows PowerShell
bootstrap-windows:
    pwsh -NoProfile -File ./scripts/windows/bootstrap.ps1

packages-windows:
    pwsh -NoProfile -File ./scripts/windows/install-packages.ps1

update-windows:
    pwsh -NoProfile -File ./scripts/windows/update.ps1

preview:
    chezmoi apply --dry-run --verbose

doctor:
    chezmoi doctor
    chezmoi verify

test:
    bats tests

lint:
    find scripts/unix tests -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.bats' \) -print0 | xargs -0 shellcheck
    shellcheck .githooks/*
    shfmt -d -i 2 -ci -bn scripts/unix tests .githooks

templates:
    ./tests/validate-templates.sh

secrets:
    gitleaks git --redact --verbose

hooks:
    git config core.hooksPath .githooks

validate: lint test templates secrets
