[CmdletBinding()]
param(
    [switch]$Packages,
    [switch]$Fonts,
    [switch]$DryRun,
    [switch]$NonInteractive
)

# Upgrades what is installed; with neither -Packages nor -Fonts, both:
#   -Packages  WinGet and Scoop packages from the manifest (upgrade, install the missing ones)
#   -Fonts     reinstall the Nerd Fonts from their latest release
# Each part lists what it would do and asks first; -DryRun only lists. Repository changes
# are not pulled here: that is dots sync, which shows and asks.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

if (-not $Packages -and -not $Fonts) {
    $Packages = $true
    $Fonts = $true
}

if ($Packages) {
    Write-Step 'Packages from the manifest'
    $installer = Join-Path $PSScriptRoot 'install-packages.ps1'
    & $installer -Upgrade -DryRun
    if (-not $DryRun -and (Confirm-Action 'Upgrade and install these packages?' -NonInteractive:$NonInteractive)) {
        & $installer -Upgrade
        Update-ProcessPath
    }
}

if ($Fonts) {
    Write-Step 'Nerd Fonts'
    $fontInstaller = Join-Path $PSScriptRoot 'install-fonts.ps1'
    & $fontInstaller -Force -DryRun
    if (-not $DryRun -and (Confirm-Action 'Reinstall these fonts from their latest release?' -NonInteractive:$NonInteractive)) {
        & $fontInstaller -Force
    }
}

Write-Success 'Update complete'
exit 0
