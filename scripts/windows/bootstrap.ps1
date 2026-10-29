[CmdletBinding()]
param(
    [string]$Repo = $env:DOTFILES_REPO,
    [string]$Branch = $env:DOTFILES_BRANCH,
    [string]$ChezmoiBinDir = (Join-Path $HOME '.local\bin'),
    [switch]$NonInteractive,
    [switch]$PromptPersonal,
    [switch]$DryRun,
    [switch]$SkipPackages,
    [switch]$SkipFonts,
    [switch]$SkipGit,
    [switch]$SkipAccounts,
    [switch]$SkipShell,
    [switch]$SkipApply,
    [switch]$SkipDesktop,
    [switch]$SkipWallpaper,
    [switch]$SkipSync,
    [switch]$SkipSystem
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commonLibrary = Join-Path $PSScriptRoot 'lib\Common.ps1'
if (Test-Path -LiteralPath $commonLibrary) {
    . $commonLibrary
} else {
    # Downloaded on its own to a fresh machine: the few helpers needed before the clone.
    # The steps after the clone run from the repository's own scripts.
    function Write-Step([string]$Message) { Write-Host "-> $Message" -ForegroundColor Cyan }
    function Write-Success([string]$Message) { Write-Host "OK $Message" -ForegroundColor Green }
    function Write-ToolWarning([string]$Message) { Write-Warning $Message }
    function Test-Command([string]$Name) { return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) }
    function Invoke-NativeCommand([string]$FilePath, [string[]]$ArgumentList = @(), [switch]$DryRun) {
        if ($DryRun) {
            Write-Host "+ $FilePath $($ArgumentList -join ' ')"
            return 0
        }
        & $FilePath @ArgumentList | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "$FilePath failed with exit code $LASTEXITCODE"
        }
        return 0
    }
}

function Resolve-DotfilesRepo([string]$Value) {
    if ($Value -match '^(https?|ssh|file)://' -or
        $Value -match '^git@' -or
        [System.IO.Path]::IsPathRooted($Value) -or
        $Value.StartsWith('.\\') -or
        $Value.StartsWith('..\\') -or
        $Value.StartsWith('./') -or
        $Value.StartsWith('../')) {
        return $Value
    }

    if ($Value.Contains('/')) {
        $cleanValue = $Value -replace '\.git$', ''
        return "https://github.com/${cleanValue}.git"
    }

    return "https://github.com/$Value/dotfiles.git"
}

function Add-UserPath([string]$Directory) {
    $comparison = [System.StringComparison]::OrdinalIgnoreCase
    $processParts = @($env:Path -split ';' | Where-Object { $_ })

    $normalizedDirectory = $Directory.TrimEnd([char[]]'\\')
    if (-not ($processParts | Where-Object { [string]::Equals($_.TrimEnd([char[]]'\\'), $normalizedDirectory, $comparison) })) {
        $env:Path = "$Directory;$env:Path"
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userParts = @($userPath -split ';' | Where-Object { $_ })
    if (-not ($userParts | Where-Object { [string]::Equals($_.TrimEnd([char[]]'\\'), $normalizedDirectory, $comparison) })) {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
            $Directory
        } else {
            "$Directory;$userPath"
        }
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    }
}

function Find-RepoRoot([string]$StartPath) {
    $current = [System.IO.DirectoryInfo]::new((Resolve-Path -LiteralPath $StartPath).Path)

    for ($depth = 0; $depth -lt 8 -and $null -ne $current; $depth++) {
        $windowsBootstrapFile = Join-Path $current.FullName 'scripts\windows\bootstrap.ps1'
        $unixBootstrapFile = Join-Path $current.FullName 'scripts\unix\bootstrap.sh'

        if ((Test-Path -LiteralPath $windowsBootstrapFile) -and (Test-Path -LiteralPath $unixBootstrapFile)) {
            return $current.FullName
        }
        $current = $current.Parent
    }

    return $null
}

function Resolve-SourceRepoRoot {
    if (-not (Test-Command 'chezmoi')) {
        return $null
    }

    # Windows PowerShell 5.1 turns native stderr into a terminating error under 'Stop'
    $ErrorActionPreference = 'Continue'
    $sourcePath = (& chezmoi source-path 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($sourcePath) -or
        -not (Test-Path -LiteralPath $sourcePath)) {
        return $null
    }

    return Find-RepoRoot $sourcePath
}

function Install-Chezmoi([string]$BinDir) {
    if (Test-Command 'chezmoi') {
        Write-Success "chezmoi is already installed: $((Get-Command chezmoi).Source)"
        return
    }

    Write-Step "Installing chezmoi into $BinDir..."

    if ($DryRun) {
        Write-Host "+ New-Item -ItemType Directory -Force -Path `"$BinDir`""
        Write-Host "+ download and run the official chezmoi installer into `"$BinDir`""
        Write-ToolWarning 'chezmoi is unavailable; template rendering and apply cannot be validated in this dry-run.'
        return
    }

    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    Add-UserPath $BinDir

    if ($PSVersionTable.PSVersion.Major -le 5) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    $installerText = Invoke-RestMethod -Uri 'https://get.chezmoi.io/ps1'
    $installer = [ScriptBlock]::Create($installerText)
    & $installer -b $BinDir

    if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
        throw "chezmoi was installed but is not available in PATH: $BinDir"
    }
    Write-Success 'chezmoi installed'
}

if ($env:NON_INTERACTIVE -eq '1') {
    $NonInteractive = $true
}

if ($PromptPersonal -and $NonInteractive) {
    throw '-PromptPersonal cannot be used with -NonInteractive.'
}

Install-Chezmoi $ChezmoiBinDir

$repoRoot = Resolve-SourceRepoRoot
$shouldInit = [string]::IsNullOrWhiteSpace($repoRoot) -or
    -not [string]::IsNullOrWhiteSpace($Repo) -or
    -not [string]::IsNullOrWhiteSpace($Branch)

if ($shouldInit) {
    if ([string]::IsNullOrWhiteSpace($Repo)) {
        $Repo = 'https://github.com/TienHwng/dotfiles.git'
    }

    $Repo = Resolve-DotfilesRepo $Repo
    Write-Step "Initializing dotfiles from $Repo..."
    $initArgs = @('init')
    if (-not [string]::IsNullOrWhiteSpace($Branch)) {
        $initArgs += @('--branch', $Branch)
    }
    if ($NonInteractive) {
        $initArgs += '--promptDefaults'
    }
    if ($PromptPersonal) {
        $initArgs += '--prompt'
    }
    $initArgs += $Repo

    Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList $initArgs -DryRun:$DryRun | Out-Null
    if ($DryRun) {
        $repoRoot = Find-RepoRoot (Join-Path $PSScriptRoot '..\..')
        if ([string]::IsNullOrWhiteSpace($repoRoot)) {
            throw 'Dry-run requires an existing local repository checkout.'
        }
        Write-ToolWarning 'Repository initialization was not executed; continuing against the local checkout.'
    } else {
        Write-Success 'Dotfiles source initialized'
        $repoRoot = Resolve-SourceRepoRoot
        if ([string]::IsNullOrWhiteSpace($repoRoot)) {
            throw 'Could not locate repository root from chezmoi source path.'
        }
    }
} else {
    Write-Success "Using existing chezmoi source: $repoRoot"

    if ($PromptPersonal) {
        Invoke-NativeCommand `
            -FilePath 'chezmoi' `
            -ArgumentList @('init', '--prompt') `
            -DryRun:$DryRun | Out-Null
    }
}

$activeScriptRoot = Join-Path $repoRoot 'scripts\windows'
if (-not (Test-Path -LiteralPath $activeScriptRoot)) {
    throw "Bootstrap script directory not found: $activeScriptRoot"
}

# The steps themselves (packages, git, accounts, fonts, shell, apply, desktop, wallpaper,
# sync, system) live in dots.ps1
$skip = @()
if ($SkipPackages) { $skip += 'packages' }
if ($SkipGit) { $skip += 'git' }
if ($SkipAccounts) { $skip += 'accounts' }
if ($SkipFonts) { $skip += 'fonts' }
if ($SkipShell) { $skip += 'shell' }
if ($SkipApply) { $skip += 'apply' }
if ($SkipDesktop) { $skip += 'desktop' }
if ($SkipWallpaper) { $skip += 'wallpaper' }
if ($SkipSync) { $skip += 'sync' }
if ($SkipSystem) { $skip += 'system' }

$dotsArguments = @{
    Command = 'bootstrap'
    DryRun = [bool]$DryRun
    NonInteractive = [bool]$NonInteractive
    Skip = $skip
}
& (Join-Path $activeScriptRoot 'dots.ps1') @dotsArguments

Write-Success 'Windows bootstrap complete'
# Probes such as ssh-add -L leave a non-zero $LASTEXITCODE behind; failures throw instead
exit 0
