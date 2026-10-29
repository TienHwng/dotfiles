[CmdletBinding()]
param()

# Compares what WinGet and Scoop have installed with the manifest
# (home/.chezmoidata/packages.yaml): installed but not listed (extra), and listed but not
# installed (missing). Changes nothing. Run by `dots packages -Diff`; dots capture reads
# Get-ExtraPackage and writes chosen packages back with Add-ManifestPackage.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$script:PackagesYaml = Join-Path (Get-RepoRoot) 'home\.chezmoidata\packages.yaml'

# Package ids WinGet knows as installed (winget export lists only those it can match to a source)
function Get-InstalledWingetId {
    if (-not (Test-Command 'winget')) {
        return @()
    }
    $file = Join-Path ([IO.Path]::GetTempPath()) "dots-winget-export-$PID.json"
    try {
        $ErrorActionPreference = 'Continue'
        & winget export --output $file --accept-source-agreements --disable-interactivity *> $null
        if (-not (Test-Path -LiteralPath $file)) {
            return @()
        }
        $export = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        return @($export.Sources | ForEach-Object { $_.Packages } | ForEach-Object { $_.PackageIdentifier })
    } finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
}

function Get-InstalledScoopApp {
    $apps = Join-Path (Get-ScoopRoot) 'apps'
    if (-not (Test-Path -LiteralPath $apps)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $apps -Directory | Where-Object Name -NE 'scoop' | ForEach-Object Name)
}

# Names the manifest lists per manager; Scoop entries without their bucket, fonts as <font>-NF
function Get-ManifestName([string]$Manager) {
    if ($Manager -eq 'winget') {
        return @(Get-ManifestList 'winget')
    }
    return @(@(Get-ManifestList 'scoop' | ForEach-Object { ($_ -split '/')[-1] }) +
        @(Get-ManifestList 'nerdFonts' | ForEach-Object { "$_-NF" }))
}

function Get-ExtraPackage {
    $extra = [System.Collections.Generic.List[object]]::new()
    foreach ($manager in @('winget', 'scoop')) {
        $known = Get-ManifestName $manager
        $installed = if ($manager -eq 'winget') { Get-InstalledWingetId } else { Get-InstalledScoopApp }
        foreach ($name in $installed | Sort-Object -Unique) {
            if ($known -notcontains $name) {
                $extra.Add([pscustomobject]@{ Manager = $manager; Name = $name })
            }
        }
    }
    return $extra
}

function Get-MissingPackage {
    $missing = [System.Collections.Generic.List[object]]::new()
    foreach ($manager in @('winget', 'scoop')) {
        $installed = if ($manager -eq 'winget') { Get-InstalledWingetId } else { Get-InstalledScoopApp }
        foreach ($name in Get-ManifestName $manager) {
            if ($installed -notcontains $name) {
                $missing.Add([pscustomobject]@{ Manager = $manager; Name = $name })
            }
        }
    }
    return $missing
}

# Appends names to the manager's list in packages.yaml (an empty "[]" list becomes a block list)
function Add-ManifestPackage([string]$Manager, [string[]]$Name) {
    $lines = [System.Collections.Generic.List[string]]::new([string[]][IO.File]::ReadAllLines($script:PackagesYaml))
    $start = $lines.FindIndex({ param($line) $line -match "^  ${Manager}:" })
    if ($start -lt 0) {
        Stop-Tool "No '${Manager}:' list in packages.yaml"
    }
    $items = @($Name | ForEach-Object { "    - $_" })
    if ($lines[$start] -match '\[\]\s*$') {
        $lines[$start] = "  ${Manager}:"
        $lines.InsertRange($start + 1, [string[]]$items)
    } else {
        $last = $start
        for ($i = $start + 1; $i -lt $lines.Count -and $lines[$i] -notmatch '^  [A-Za-z]'; $i++) {
            if ($lines[$i] -match '^    - ') {
                $last = $i
            }
        }
        $lines.InsertRange($last + 1, [string[]]$items)
    }
    [IO.File]::WriteAllText($script:PackagesYaml, (($lines -join "`n") + "`n"))
}

function Uninstall-ExtraPackage([string]$Manager, [string[]]$Name) {
    foreach ($item in $Name) {
        if ($Manager -eq 'winget') {
            Invoke-NativeCommand -FilePath 'winget' -ArgumentList @('uninstall', '--id', $item, '--exact') -IgnoreExitCode | Out-Null
        } else {
            Invoke-NativeCommand -FilePath 'scoop' -ArgumentList @('uninstall', $item) -IgnoreExitCode | Out-Null
        }
    }
}

function Show-PackageDiff {
    $extra = @(Get-ExtraPackage)
    Write-Step "Installed but not in the manifest ($($extra.Count)):"
    $extra | ForEach-Object { Write-Host "  $($_.Manager)  $($_.Name)" }
    $missing = @(Get-MissingPackage)
    Write-Step "In the manifest but not installed ($($missing.Count)):"
    $missing | ForEach-Object { Write-Host "  $($_.Manager)  $($_.Name)" }
}

# Dot-sourcing (capture.ps1, Pester) loads the functions without printing the diff
if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Test-Command 'chezmoi')) {
        Stop-Tool 'chezmoi is required to read the package manifest.'
    }
    Show-PackageDiff
}
