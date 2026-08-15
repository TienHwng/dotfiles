default:
    @just --list

# Unix/Linux/macOS
bootstrap-unix:
    ./scripts/unix/bootstrap.sh

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
