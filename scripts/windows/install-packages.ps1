[CmdletBinding()]
param(
    [switch]$Upgrade,
    [switch]$DryRun,
    [switch]$ContinueOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

# winget upgrade exits with this code when the installed version is already the latest
$WingetNoApplicableUpdate = -1978335189

if (-not (Test-Command 'chezmoi')) {
    if ($DryRun) {
        Write-ToolWarning 'chezmoi is unavailable; the package manifest cannot be read in this dry-run.'
        return
    }
    Stop-Tool 'chezmoi is required to read the package manifest (home/.chezmoidata/packages.yaml).'
}

function Invoke-PackageCommand([string]$Package, [scriptblock]$Command) {
    try {
        & $Command
    } catch {
        if ($ContinueOnError) {
            Write-ToolWarning "Could not process ${Package}: $($_.Exception.Message)"
        } else {
            throw
        }
    }
}

# WinGet: GUI and system apps
$wingetPackages = @(Get-ManifestList 'winget')
if ($wingetPackages.Count -gt 0) {
    $hasWinget = Test-Command 'winget'
    if (-not $hasWinget) {
        if (-not $DryRun) {
            Stop-Tool 'WinGet is required. Install or repair App Installer before continuing.'
        }
        Write-ToolWarning 'WinGet is not currently available; printing every planned install.'
    }

    Write-Step "WinGet: $($wingetPackages.Count) package(s)"
    foreach ($package in $wingetPackages) {
        $installed = $hasWinget -and (Test-WingetPackage $package)
        if ($installed -and -not $Upgrade) {
            Write-Success "$package is installed"
            continue
        }

        $verb = if ($installed) { 'upgrade' } else { 'install' }
        $arguments = @(
            $verb, '--id', $package, '--exact', '--source', 'winget', '--silent',
            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
        )
        Invoke-PackageCommand $package {
            $code = Invoke-NativeCommand -FilePath 'winget' -ArgumentList $arguments -DryRun:$DryRun -IgnoreExitCode
            if ($code -ne 0 -and -not ($verb -eq 'upgrade' -and $code -eq $WingetNoApplicableUpdate)) {
                throw "winget $verb $package failed with exit code $code"
            }
        }
    }

    if (-not $DryRun) {
        Update-ProcessPath
    }
}

# Scoop: CLI tools, installed per user
$scoopPackages = @(Get-ManifestList 'scoop')
if ($scoopPackages.Count -gt 0) {
    Install-Scoop -DryRun:$DryRun

    $buckets = @(
        $scoopPackages |
            Where-Object { $_.Contains('/') } |
            ForEach-Object { ($_ -split '/')[0] } |
            Select-Object -Unique
    )
    foreach ($bucket in $buckets) {
        Add-ScoopBucket $bucket -DryRun:$DryRun
    }
    if ($Upgrade) {
        Invoke-NativeCommand -FilePath 'scoop' -ArgumentList @('update') -DryRun:$DryRun | Out-Null
    }

    Write-Step "Scoop: $($scoopPackages.Count) package(s)"
    foreach ($package in $scoopPackages) {
        $installed = Test-ScoopApp $package
        if ($installed -and -not $Upgrade) {
            Write-Success "$package is installed"
            continue
        }

        $arguments = if ($installed) { @('update', ($package -split '/')[-1]) } else { @('install', $package) }
        Invoke-PackageCommand $package {
            Invoke-NativeCommand -FilePath 'scoop' -ArgumentList $arguments -DryRun:$DryRun | Out-Null
        }
    }
}

if ($wingetPackages.Count -eq 0 -and $scoopPackages.Count -eq 0) {
    Write-ToolWarning 'No WinGet or Scoop packages configured'
    return
}

Write-Success 'Windows package installation complete'
