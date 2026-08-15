[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$repoRoot = Get-RepoRoot
$fontList = Join-Path $repoRoot 'packages\fonts.txt'
if (-not (Test-Path -LiteralPath $fontList)) {
    Stop-Tool "Font list not found: $fontList"
}

$fonts = @(Get-ListFile $fontList)
if ($fonts.Count -eq 0) {
    Write-ToolWarning 'No Nerd Fonts are configured.'
    return
}

$fontHome = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$fontRegistry = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $fontHome | Out-Null
    New-Item -Path $fontRegistry -Force | Out-Null
}

foreach ($font in $fonts) {
    $marker = Join-Path $fontHome ".dotfiles-$font.installed"
    if ((Test-Path -LiteralPath $marker) -and -not $Force) {
        Write-Success "$font is already installed"
        continue
    }

    if ($DryRun) {
        Write-Host "+ install Nerd Font $font into `"$fontHome`""
        continue
    }

    Write-Step "Installing $font Nerd Font..."
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-font-" + [Guid]::NewGuid())
    $archive = Join-Path $tempRoot "$font.zip"
    $extractDir = Join-Path $tempRoot 'extracted'

    try {
        New-Item -ItemType Directory -Force -Path $tempRoot, $extractDir | Out-Null
        $url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$font.zip"
        Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
        Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force

        $fontFiles = @(
            Get-ChildItem -LiteralPath $extractDir -Recurse -File |
                Where-Object { $_.Extension -in @('.ttf', '.otf') }
        )
        if ($fontFiles.Count -eq 0) {
            throw "No .ttf or .otf files were found in the $font archive."
        }

        foreach ($fontFile in $fontFiles) {
            $destination = Join-Path $fontHome $fontFile.Name
            Copy-Item -LiteralPath $fontFile.FullName -Destination $destination -Force
            $registryName = "$($fontFile.BaseName) (TrueType)"
            New-ItemProperty `
                -Path $fontRegistry `
                -Name $registryName `
                -Value $destination `
                -PropertyType String `
                -Force | Out-Null
        }

        Set-Content -LiteralPath $marker -Value (Get-Date -Format o) -Encoding UTF8
        Write-Success "Installed $font"
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Success 'Font installation complete; restart open applications to refresh their font lists'
