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
    [switch]$SkipApply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

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
    $current = [System.IO.DirectoryInfo](Resolve-Path -LiteralPath $StartPath)

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

    $sourcePath = (& chezmoi source-path 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sourcePath)) {
        return $null
    }

    return Find-RepoRoot $sourcePath
}

function Ensure-Chezmoi {
    New-Item -ItemType Directory -Force -Path $ChezmoiBinDir | Out-Null
    Add-UserPath $ChezmoiBinDir

    if (Test-Command 'chezmoi') {
        Write-Success "chezmoi is already installed: $((Get-Command chezmoi).Source)"
        return
    }

    Write-Step "Installing chezmoi into $ChezmoiBinDir..."

    if ($PSVersionTable.PSVersion.Major -le 5) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    $installerText = Invoke-RestMethod -Uri 'https://get.chezmoi.io/ps1'
    $installer = [ScriptBlock]::Create($installerText)
    & $installer -b $ChezmoiBinDir

    if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
        throw "chezmoi was installed but is not available in PATH: $ChezmoiBinDir"
    }
    Write-Success 'chezmoi installed'
}

if ($env:NON_INTERACTIVE -eq '1') {
    $NonInteractive = $true
}

if ($PromptPersonal -and $NonInteractive) {
    throw '-PromptPersonal cannot be used with -NonInteractive.'
}

Ensure-Chezmoi

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
    $initArgs += $Repo

    Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList $initArgs
    Write-Success 'Dotfiles source initialized'

    $repoRoot = Resolve-SourceRepoRoot
    if ([string]::IsNullOrWhiteSpace($repoRoot)) {
        throw 'Could not locate repository root from chezmoi source path.'
    }
} else {
    Write-Success "Using existing chezmoi source: $repoRoot"
}

$activeScriptRoot = Join-Path $repoRoot 'scripts\windows'
if (-not (Test-Path -LiteralPath $activeScriptRoot)) {
    throw "Bootstrap script directory not found: $activeScriptRoot"
}

Write-Step 'Platform: Windows PowerShell'

if (-not $SkipPackages) {
    & (Join-Path $activeScriptRoot 'install-packages.ps1') -DryRun:$DryRun
    Update-ProcessPath
} else {
    Write-ToolWarning 'Skipping package installation'
}

if (-not $SkipGit) {
    & (Join-Path $activeScriptRoot 'setup-git.ps1') `
    -Prompt:$PromptPersonal `
        -NonInteractive:$NonInteractive `
        -DryRun:$DryRun
} else {
    Write-ToolWarning 'Skipping Git setup'
}

if (-not $SkipAccounts) {
    & (Join-Path $activeScriptRoot 'setup-accounts.ps1') `
    -Prompt:$PromptPersonal `
        -NonInteractive:$NonInteractive `
        -DryRun:$DryRun
} else {
    Write-ToolWarning 'Skipping account onboarding'
}

$installFonts = Get-ChezmoiValue '.features.installFonts' 'true'
if (-not $SkipFonts -and $installFonts -eq 'true') {
    & (Join-Path $activeScriptRoot 'install-fonts.ps1') -DryRun:$DryRun
} else {
    Write-ToolWarning 'Skipping font installation'
}

$setupShell = Get-ChezmoiValue '.features.setupShell' 'true'
if (-not $SkipShell -and $setupShell -eq 'true') {
    $shellName = Get-ChezmoiValue '.shell.name' 'pwsh'
    & (Join-Path $activeScriptRoot 'setup-shell.ps1') `
        -Shell $shellName `
        -CreateProfile `
        -DryRun:$DryRun
} else {
    Write-ToolWarning 'Skipping PowerShell setup'
}

if (-not $SkipApply) {
    if (-not (Test-Command 'chezmoi')) {
        Stop-Tool 'chezmoi is required before applying dotfiles.'
    }

    Write-Step 'Applying dotfiles...'
    $arguments = @('apply', '--verbose')
    if ($DryRun) {
        $arguments += '--dry-run'
    }
    Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList $arguments
    Write-Success 'Dotfiles applied'
} else {
    Write-ToolWarning 'Skipping chezmoi apply'
}

if ((Test-Command 'chezmoi') -and -not $DryRun) {
    Write-Step 'Running chezmoi doctor...'
    Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('doctor') -IgnoreExitCode | Out-Null
}

Write-Success 'Windows bootstrap complete'
