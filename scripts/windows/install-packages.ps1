[CmdletBinding()]
param(
    [switch]$Upgrade,
    [switch]$DryRun,
    [switch]$ContinueOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$repoRoot = Get-RepoRoot

if (-not (Test-Command 'winget')) {
    if ($DryRun) {
        Write-ToolWarning 'WinGet is not currently available; printing the planned commands only.'
    } else {
        Stop-Tool 'WinGet is required. Install or repair App Installer before continuing.'
    }
}

$file = Join-Path $repoRoot 'packages\winget.txt'
if (-not (Test-Path -LiteralPath $file)) {
    Stop-Tool "Package list does not exist: $file"
}

$packages = [System.Collections.Generic.List[string]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($package in Get-ListFile $file) {
    if ($seen.Add($package)) {
        $packages.Add($package)
    }
}

if ($packages.Count -eq 0) {
    Write-ToolWarning 'No WinGet packages configured'
    return
}

Write-Step "Installing $($packages.Count) package(s) with WinGet..."

foreach ($package in $packages) {
    $arguments = if ($Upgrade) {
        @(
            'upgrade', '--id', $package, '--exact', '--source', 'winget',
            '--silent', '--accept-package-agreements', '--accept-source-agreements',
            '--disable-interactivity'
        )
    } else {
        @(
            'install', '--id', $package, '--exact', '--source', 'winget',
            '--silent', '--no-upgrade', '--accept-package-agreements',
            '--accept-source-agreements', '--disable-interactivity'
        )
    }

    try {
        Invoke-NativeCommand -FilePath 'winget' -ArgumentList $arguments -DryRun:$DryRun | Out-Null
    } catch {
        if ($ContinueOnError) {
            Write-ToolWarning "Could not process $package: $($_.Exception.Message)"
        } else {
            throw
        }
    }
}

Write-Success 'Windows package installation complete'
