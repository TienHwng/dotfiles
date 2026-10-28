[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

if (-not $Yes -and -not (Confirm-Action 'Clean chezmoi and dotfiles temporary caches?' -DefaultYes:$false)) {
    Write-ToolWarning 'Cleanup cancelled'
    return
}

$paths = [System.Collections.Generic.List[string]]::new()
$cacheDir = Get-ChezmoiValue '.chezmoi.cacheDir'
if (-not [string]::IsNullOrWhiteSpace($cacheDir)) {
    $paths.Add($cacheDir)
}

foreach ($path in $paths) {
    $items = @(Get-Item -Path $path -ErrorAction SilentlyContinue)
    foreach ($match in $items) {
        if ($DryRun) {
            Write-Host "+ Remove-Item -Recurse -Force `"$($match.FullName)`""
        } else {
            Remove-Item -LiteralPath $match.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Success 'Cleanup complete'
