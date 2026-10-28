[CmdletBinding()]
param(
    [switch]$DryRun
)

# Fetches the wallpaper repository (chezmoi external, private Git LFS repository from
# .wallpapers.repo) into ~/.wallpapers.dir, then sets .wallpapers.current as the
# Windows desktop wallpaper.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

if (-not (Test-Command 'chezmoi')) {
    if ($DryRun) {
        Write-ToolWarning 'chezmoi is unavailable; the wallpaper step cannot be previewed in this dry-run.'
        return
    }
    Stop-Tool 'chezmoi is required to fetch the wallpapers.'
}

$sourceDir = Join-Path (Get-RepoRoot) 'home'

# Read from this checkout: on a fresh machine's dry-run chezmoi has no source directory yet
function Get-DataValue([string]$Expression) {
    return "$(& chezmoi --source $sourceDir execute-template "{{ $Expression }}")".Trim()
}

$repo = Get-DataValue '.wallpapers.repo'
$dir = Join-Path $HOME ((Get-DataValue '.wallpapers.dir') -replace '/', '\')
$image = Join-Path $dir (Get-DataValue '.wallpapers.current')

if ([string]::IsNullOrWhiteSpace($repo)) {
    Stop-Tool 'No wallpaper repository is set (.wallpapers.repo).'
}

if (-not (Test-Command 'git-lfs')) {
    if (-not $DryRun) {
        Stop-Tool 'git-lfs is required to fetch the wallpapers; it comes with Git for Windows (packages step).'
    }
    Write-ToolWarning 'git-lfs is unavailable; a real run would stop here.'
}

# chezmoi pulls whatever repository already sits there, so never adopt a foreign clone
if (Test-Path -LiteralPath $dir) {
    $ErrorActionPreference = 'Continue'
    $origin = "$(& git -C $dir remote get-url origin 2>$null)".Trim()
    $ErrorActionPreference = 'Stop'
    if (($origin -replace '\.git$', '') -ne ($repo -replace '\.git$', '')) {
        Stop-Tool "$dir is not a clone of $repo (origin: $origin). Move it away, then run this step again."
    }
    Write-Step "Updating wallpapers in $dir"
} else {
    Write-Step "Cloning wallpapers from $repo into $dir"
}
Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('--source', $sourceDir, 'apply', '--verbose', $dir) -DryRun:$DryRun | Out-Null

if ($DryRun) {
    Write-Host "+ set the desktop wallpaper to `"$image`""
} else {
    if (-not (Test-Path -LiteralPath $image)) {
        Stop-Tool "Wallpaper not found: $image (check .wallpapers.current)"
    }
    if (-not ('DotfilesWallpaper' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class DotfilesWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(int uiAction, int uiParam, string pvParam, int fWinIni);
}
'@
    }
    # SPI_SETDESKWALLPAPER, saved to the user profile (SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)
    if (-not [DotfilesWallpaper]::SystemParametersInfo(0x0014, 0, $image, 0x01 -bor 0x02)) {
        Stop-Tool "Windows refused to set the wallpaper: $image"
    }
    Write-Success "Wallpaper set: $image"
}

Write-Success 'Wallpaper step complete'
