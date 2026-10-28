[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

if (-not (Test-Command 'chezmoi')) {
    if ($DryRun) {
        Write-ToolWarning 'chezmoi is unavailable; the font list cannot be read in this dry-run.'
        return
    }
    Stop-Tool 'chezmoi is required to read the font list (home/.chezmoidata/packages.yaml).'
}

$fonts = @(Get-ManifestList 'nerdFonts')
if ($fonts.Count -eq 0) {
    Write-ToolWarning 'No Nerd Fonts are configured.'
    return
}

# Nerd Fonts come from the Scoop nerd-fonts bucket as <name>-NF, installed per user
Install-Scoop -DryRun:$DryRun
Add-ScoopBucket 'nerd-fonts' -DryRun:$DryRun

foreach ($font in $fonts) {
    $app = "$font-NF"
    $installed = Test-ScoopApp $app
    if ($installed -and -not $Force) {
        Write-Success "$font Nerd Font is already installed"
        continue
    }

    $arguments = if ($installed) { @('update', $app) } else { @('install', "nerd-fonts/$app") }
    Write-Step "Installing Nerd Font $font..."
    Invoke-NativeCommand -FilePath 'scoop' -ArgumentList $arguments -DryRun:$DryRun | Out-Null
}

Write-Success 'Font installation complete; restart open applications to refresh their font lists'
