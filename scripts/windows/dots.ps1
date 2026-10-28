# dots: the single entry point for setting up and maintaining this Windows machine.
# Every step previews what it will change and asks before running it.
# Runs on Windows PowerShell 5.1 (fresh machine) and PowerShell 7.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'The command functions below read the script parameters.')]
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',
    [switch]$DryRun,
    [switch]$NonInteractive,
    [string[]]$Skip = @(),
    # update
    [switch]$Packages,
    [switch]$Fonts,
    [switch]$Upgrade,
    # cleanup
    [switch]$Yes,
    # backup
    [string]$Destination
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$script:Steps = @('packages', 'git', 'accounts', 'fonts', 'shell', 'apply')

function Show-Usage {
    Write-Host @'
Usage: dots <command> [options]

Commands:
  bootstrap [-DryRun] [-NonInteractive] [-Skip step,...]
                  Set up this machine step by step: packages, git, accounts,
                  fonts, shell, apply. Each step shows a preview and asks
                  run / skip / quit before changing anything.
  packages [-DryRun]
                  Install missing WinGet and Scoop packages from the manifest
                  (preview, then ask).
  doctor          Check required tools, the shell setup, the manifest, and chezmoi.
  update [-Packages] [-Fonts] [-Upgrade] [-DryRun]
                  Pull and apply the repository, optionally packages and fonts.
  backup [-Destination PATH] [-DryRun]
                  Back up the repository and the local chezmoi config.
  cleanup [-Yes] [-DryRun]
                  Remove chezmoi caches.
  help            Show this help.

Prompts use gum when it is installed; set DOTS_NO_GUM=1 for plain prompts.
'@
}

function Test-UseGum {
    return (-not $env:DOTS_NO_GUM) -and
        (-not [Console]::IsInputRedirected) -and
        (-not [Console]::IsOutputRedirected) -and
        (Test-Command 'gum')
}

# Returns run, skip, or quit
function Read-StepChoice([string]$Step) {
    if (Test-UseGum) {
        $answer = & gum choose --header "Step: $Step" Run Skip Quit
        if ($LASTEXITCODE -ne 0) {
            $answer = 'Quit'
        }
    } else {
        $answer = Read-Host "Run step '$Step'? [Y]es / [s]kip / [q]uit"
    }

    switch -Regex ("$answer".Trim().ToLowerInvariant()) {
        '^(|y|yes|run)$' { return 'run' }
        '^(s|skip)$' { return 'skip' }
        default { return 'quit' }
    }
}

function Confirm-Yes([string]$Message) {
    if (Test-UseGum) {
        & gum confirm $Message
        return $LASTEXITCODE -eq 0
    }
    return Confirm-Action $Message -DefaultYes $true
}

function Get-StepDescription([string]$Step) {
    switch ($Step) {
        'packages' { 'Install WinGet and Scoop packages from home/.chezmoidata/packages.yaml' }
        'git' { 'Check the Git identity used by the git template' }
        'accounts' { 'Check the SSH key and GitHub CLI login' }
        'fonts' { 'Install Nerd Fonts from the manifest with Scoop' }
        'shell' { 'Set XDG_CONFIG_HOME and the PowerShell 7 profile stub' }
        'apply' { 'Apply dotfiles from home/ with chezmoi' }
    }
}

function Test-StepEnabled([string]$Step) {
    switch ($Step) {
        'fonts' { return (Get-ChezmoiValue '.features.installFonts' 'true') -eq 'true' }
        'shell' { return (Get-ChezmoiValue '.features.setupShell' 'true') -eq 'true' }
        default { return $true }
    }
}

function Invoke-ChezmoiApply([string]$Mode) {
    $arguments = @('--source', (Join-Path (Get-RepoRoot) 'home'))
    if ($NonInteractive) {
        $arguments += '--no-tty'
    }

    # Previews use diff: apply --dry-run still stops to ask about files changed outside chezmoi
    if (-not (Test-Command 'chezmoi')) {
        if (-not $DryRun) {
            Stop-Tool 'chezmoi is required before applying dotfiles.'
        }
        Write-Host (Format-NativeCommand 'chezmoi' ($arguments + @('diff', '--no-pager')))
        Write-ToolWarning 'chezmoi diff was not executed because chezmoi is unavailable.'
    } elseif ($DryRun -or $Mode -eq 'preview') {
        Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList ($arguments + @('diff', '--no-pager')) | Out-Null
    } else {
        Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList ($arguments + @('apply', '--verbose')) | Out-Null
    }
}

# Run a step for real ("run") or only show what it would change ("preview").
# Previews never prompt, so setup scripts get -NonInteractive there.
function Invoke-Step([string]$Step, [string]$Mode) {
    $dry = $Mode -eq 'preview' -or $DryRun
    $quiet = $Mode -eq 'preview' -or $NonInteractive

    switch ($Step) {
        'packages' { & (Join-Path $PSScriptRoot 'install-packages.ps1') -DryRun:$dry; if (-not $dry) { Update-ProcessPath } }
        'git' { & (Join-Path $PSScriptRoot 'setup-git.ps1') -DryRun:$dry -NonInteractive:$quiet }
        'accounts' { & (Join-Path $PSScriptRoot 'setup-accounts.ps1') -DryRun:$dry -NonInteractive:$quiet }
        'fonts' { & (Join-Path $PSScriptRoot 'install-fonts.ps1') -DryRun:$dry }
        'shell' { & (Join-Path $PSScriptRoot 'setup-shell.ps1') -Shell 'pwsh' -DryRun:$dry }
        'apply' { Invoke-ChezmoiApply $Mode }
    }
}

function Write-ManualChecklist {
    Write-Step 'Manual steps that cannot be automated:'
    @(
        'Sign in to Bitwarden and enable its SSH agent',
        'Sign in to VS Code Settings Sync, the browser, Discord, and Steam',
        'Pick PowerShell 7 as the default profile in Windows Terminal',
        'Enable the secret-scanning Git hook once per clone: git config core.hooksPath .githooks'
    ) | ForEach-Object { Write-Host "  $_" }
}

function Invoke-Bootstrap {
    # pwsh -File passes "-Skip a,b" as one string; split it
    $skipSteps = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($step in $skipSteps) {
        if ($step -notin $script:Steps) {
            Stop-Tool "Unknown step: $step (steps: $($script:Steps -join ' '))"
        }
    }

    foreach ($step in $script:Steps) {
        Write-Step "[$step] $(Get-StepDescription $step)"

        if ($step -in $skipSteps) {
            Write-ToolWarning "Skipping $step"
            continue
        }
        if (-not (Test-StepEnabled $step)) {
            Write-ToolWarning "Skipping $step (disabled in .features)"
            continue
        }
        if ($DryRun -or $NonInteractive) {
            Invoke-Step $step 'run'
            continue
        }

        try {
            Invoke-Step $step 'preview'
        } catch {
            Write-ToolWarning "The $step preview reported a problem; review it before running: $($_.Exception.Message)"
        }
        switch (Read-StepChoice $step) {
            'run' { Invoke-Step $step 'run' }
            'skip' { Write-ToolWarning "Skipped $step" }
            'quit' {
                Write-ToolWarning "Stopped before $step; run dots bootstrap again to continue."
                return
            }
        }
    }

    if (-not $DryRun -and (Test-Command 'chezmoi')) {
        Write-Step 'Running chezmoi doctor...'
        if ((Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('doctor') -IgnoreExitCode) -ne 0) {
            Write-ToolWarning 'chezmoi doctor reported warnings'
        }
    }

    Write-Success 'Bootstrap complete'
    Write-ManualChecklist
}

function Invoke-PackageInstall {
    $installer = Join-Path $PSScriptRoot 'install-packages.ps1'
    if ($DryRun -or $NonInteractive) {
        & $installer -DryRun:$DryRun -Upgrade:$Upgrade
        return
    }

    & $installer -DryRun -Upgrade:$Upgrade
    if (Confirm-Yes 'Install these packages?') {
        & $installer -Upgrade:$Upgrade
    } else {
        Write-ToolWarning 'Nothing installed'
    }
}

# Returns the number of failed required checks
function Invoke-Doctor {
    $failures = 0

    Write-Step 'Required tools'
    foreach ($tool in @('git', 'chezmoi')) {
        if (Test-Command $tool) {
            Write-Success "${tool}: $((Get-Command $tool).Source)"
        } else {
            Write-Failure "$tool is missing"
            $failures++
        }
    }

    Write-Step 'Optional tools'
    foreach ($tool in @('pwsh', 'winget', 'scoop', 'oh-my-posh', 'gum', 'gitleaks', 'fzf')) {
        if (Test-Command $tool) {
            Write-Success "${tool}: $((Get-Command $tool).Source)"
        } else {
            Write-ToolWarning "$tool is missing (install it from the manifest)"
        }
    }

    Write-Step 'Package manifest'
    if (Test-Command 'chezmoi') {
        try {
            $count = @(Get-ManifestList 'winget').Count + @(Get-ManifestList 'scoop').Count
            Write-Success "$count package(s) listed for WinGet and Scoop"
        } catch {
            Write-Failure "The package manifest is unreadable: $($_.Exception.Message)"
            $failures++
        }
    } else {
        Write-ToolWarning 'The package manifest needs chezmoi'
    }

    Write-Step 'Shell'
    $configHome = Join-Path $HOME '.config'
    if ([Environment]::GetEnvironmentVariable('XDG_CONFIG_HOME', 'User') -eq $configHome) {
        Write-Success "XDG_CONFIG_HOME is $configHome"
    } else {
        Write-ToolWarning 'XDG_CONFIG_HOME is not set; run the shell step: dots bootstrap'
    }
    $stubFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\profile.ps1'
    if ((Test-Path -LiteralPath $stubFile) -and
        (Select-String -LiteralPath $stubFile -SimpleMatch 'Written by dotfiles' -Quiet)) {
        Write-Success "Profile stub: $stubFile"
    } else {
        Write-ToolWarning "Profile stub missing at $stubFile; run the shell step: dots bootstrap"
    }

    Write-Step 'Git hooks'
    $hooksPath = ''
    if (Test-Command 'git') {
        $hooksPath = "$(& git -C (Get-RepoRoot) config --get core.hooksPath)".Trim()
    }
    if ($hooksPath -eq '.githooks') {
        Write-Success 'Secret-scanning pre-commit hook is enabled'
    } else {
        Write-ToolWarning 'Git hooks are off for this clone; run: git config core.hooksPath .githooks'
    }

    if (Test-Command 'chezmoi') {
        Write-Step 'chezmoi doctor'
        if ((Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('doctor') -IgnoreExitCode) -ne 0) {
            Write-ToolWarning 'chezmoi doctor reported problems; review its output above'
        }
    }

    if ($failures -gt 0) {
        Write-Failure "$failures check(s) failed"
    } else {
        Write-Success 'All required checks passed'
    }
    return $failures
}

function Invoke-DotsCommand {
    if ($env:NON_INTERACTIVE -eq '1') {
        $script:NonInteractive = $true
    }

    switch ($Command) {
        'bootstrap' { Invoke-Bootstrap }
        'packages' { Invoke-PackageInstall }
        'doctor' {
            if ((Invoke-Doctor) -gt 0) {
                exit 1
            }
        }
        'update' {
            & (Join-Path $PSScriptRoot 'update.ps1') -Packages:$Packages -Fonts:$Fonts -UpgradePackages:$Upgrade -DryRun:$DryRun
        }
        'backup' {
            $arguments = @{ DryRun = $DryRun }
            if ($Destination) {
                $arguments.Destination = $Destination
            }
            & (Join-Path $PSScriptRoot 'backup.ps1') @arguments
        }
        'cleanup' { & (Join-Path $PSScriptRoot 'cleanup.ps1') -Yes:$Yes -DryRun:$DryRun }
        { $_ -in @('help', '-h', '--help') } { Show-Usage }
        default {
            Show-Usage
            Stop-Tool "Unknown command: $Command"
        }
    }
}

# Dot-sourcing (Pester) loads the functions without running a command
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-DotsCommand
}
