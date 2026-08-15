[CmdletBinding()]
param(
    [switch]$Packages,
    [switch]$Fonts,
    [switch]$UpgradePackages,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

if (-not (Test-Command 'chezmoi')) {
    Stop-Tool 'chezmoi is required.'
}
Write-Step 'Updating dotfiles repository and target state...'
if ($DryRun) {
    Write-Host '+ chezmoi update --verbose'
    Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('apply', '--dry-run', '--verbose')
} else {
    Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('update', '--verbose')
}
Write-Success 'Dotfiles update complete'

if ($Packages) {
    & (Join-Path $PSScriptRoot 'install-packages.ps1') `
        -Upgrade:$UpgradePackages `
        -DryRun:$DryRun
    Update-ProcessPath
}

if ($Fonts) {
    & (Join-Path $PSScriptRoot 'install-fonts.ps1') -Force -DryRun:$DryRun
}

if (-not $DryRun) {
    Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('doctor') -IgnoreExitCode | Out-Null
}
