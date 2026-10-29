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
    # sync
    [switch]$Check,
    [switch]$Notify,
    # packages
    [switch]$Diff,
    [switch]$Upgrade,
    # update
    [switch]$Packages,
    [switch]$Fonts,
    # cleanup
    [switch]$Yes,
    # backup
    [string]$Destination
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

# git renders ~/.gitconfig (gh credential helper) so accounts can log in to gh before
# anything clones a private repository; wallpaper needs that login. system (admin) goes last.
$script:Steps = @('packages', 'git', 'accounts', 'fonts', 'shell', 'apply', 'desktop', 'wallpaper', 'sync', 'system')

function Show-Usage {
    Write-Host @'
Usage: dots <command> [options]

Commands:
  bootstrap [-DryRun] [-NonInteractive] [-Skip step,...]
                  Set up this machine step by step: packages, git, accounts,
                  fonts, shell, apply, desktop, wallpaper, sync, system. Each step
                  shows a preview and asks run / skip / quit before changing anything.
                  -NonInteractive skips system unless -DryRun is set.
  packages [-DryRun] [-Upgrade] | packages -Diff
                  Install missing WinGet and Scoop packages from the manifest
                  (preview, then ask; -Upgrade also upgrades installed ones), or
                  list packages installed outside it.
  sync [-Check [-Notify]]
                  Pull new commits (fast-forward only, after showing them), then run
                  the steps whose files changed, each with a preview. -Check only
                  fetches and reports how far behind this machine is; -Notify adds a
                  toast with a Sync now button (the dots-sync Scheduled Task uses it).
  status          Branch, commits behind/ahead, local changes, chezmoi drift, task.
  <step> [-DryRun]
                  Run one bootstrap step on its own (git, accounts, fonts, shell, apply,
                  desktop, wallpaper), previewed and confirmed. packages, sync and system
                  are commands of their own; the sync step is setup-sync.ps1.
  capture [-DryRun]
                  Pick what changed on this machine (repository files, dotfiles
                  chezmoi copied, registry values, packages), write it back, review the diff,
                  then commit to main and push.
  system [-DryRun]
                  Machine registry values, the OpenSSH agent service and the NVIDIA
                  App: preview, then ask and apply in an administrator window. Never
                  non-interactive.
  doctor          Check required tools, the shell setup, the manifest, and chezmoi.
  update [-Packages] [-Fonts] [-DryRun]
                  Upgrade the manifest's WinGet and Scoop packages and reinstall the
                  Nerd Fonts, each listed first and confirmed; neither option means
                  both. It does not pull the repository: that is dots sync.
  backup [-Destination PATH] [-DryRun]
                  Back up the repository and the local chezmoi config.
  cleanup [-Yes] [-DryRun]
                  Remove chezmoi caches.
  help            Show this help.

Full guide: docs/usage.md. Prompts use gum when it is installed; set DOTS_NO_GUM=1 for plain prompts.
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
        'git' { 'Check the Git identity and render ~/.gitconfig from the git template' }
        'accounts' { 'Log in to GitHub with gh and check the SSH key in the Bitwarden agent' }
        'fonts' { 'Install Nerd Fonts from the manifest with Scoop' }
        'shell' { 'Set XDG_CONFIG_HOME and the PowerShell 7 profile stub' }
        'apply' { 'Apply dotfiles from home/ with chezmoi (externals come later)' }
        'desktop' { 'Set user registry values (HKCU) from home/.chezmoidata/windows.yaml' }
        'wallpaper' { 'Fetch the wallpaper repository and set the desktop wallpaper' }
        'sync' { 'Register the dots-sync Scheduled Task: check the repository at logon and every 6 hours' }
        'system' { 'Admin: machine registry values (UTC clock, Fast Startup off), disable the OpenSSH agent service, NVIDIA App' }
    }
}

function Test-StepEnabled([string]$Step) {
    switch ($Step) {
        'fonts' { return (Get-ChezmoiValue '.features.installFonts' 'true') -eq 'true' }
        'shell' { return (Get-ChezmoiValue '.features.setupShell' 'true') -eq 'true' }
        'desktop' { return (Get-ChezmoiValue '.features.desktop' 'true') -eq 'true' }
        'wallpaper' { return (Get-ChezmoiValue '.features.wallpapers' 'true') -eq 'true' }
        default { return $true }
    }
}

# Apply the given targets, or everything except externals (the wallpaper step fetches those)
function Invoke-ChezmoiApply([string]$Mode, [string[]]$Target = @()) {
    $arguments = @('--source', (Join-Path (Get-RepoRoot) 'home'))
    if ($NonInteractive) {
        $arguments += '--no-tty'
    }
    if ($Target.Count -eq 0) {
        $arguments += @('--exclude', 'externals')
    }

    # Previews use diff: apply --dry-run still stops to ask about files changed outside chezmoi
    if (-not (Test-Command 'chezmoi')) {
        if (-not $DryRun) {
            Stop-Tool 'chezmoi is required before applying dotfiles.'
        }
        Write-Host (Format-NativeCommand 'chezmoi' ($arguments + @('diff', '--no-pager') + $Target))
        Write-ToolWarning 'chezmoi diff was not executed because chezmoi is unavailable.'
    } elseif ($DryRun -or $Mode -eq 'preview') {
        Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList ($arguments + @('diff', '--no-pager') + $Target) | Out-Null
    } else {
        Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList ($arguments + @('apply', '--verbose') + $Target) | Out-Null
    }
}

# Run a step for real ("run") or only show what it would change ("preview").
# Previews never prompt, so setup scripts get -NonInteractive there.
function Invoke-Step([string]$Step, [string]$Mode) {
    $dry = $Mode -eq 'preview' -or $DryRun
    $quiet = $Mode -eq 'preview' -or $NonInteractive

    switch ($Step) {
        'packages' { & (Join-Path $PSScriptRoot 'install-packages.ps1') -DryRun:$dry; if (-not $dry) { Update-ProcessPath } }
        'git' {
            & (Join-Path $PSScriptRoot 'setup-git.ps1') -DryRun:$dry -NonInteractive:$quiet
            Invoke-ChezmoiApply $Mode @(Join-Path $HOME '.gitconfig')
        }
        'accounts' { & (Join-Path $PSScriptRoot 'setup-accounts.ps1') -DryRun:$dry -NonInteractive:$quiet }
        'fonts' { & (Join-Path $PSScriptRoot 'install-fonts.ps1') -DryRun:$dry }
        'shell' { & (Join-Path $PSScriptRoot 'setup-shell.ps1') -Shell 'pwsh' -DryRun:$dry }
        'apply' { Invoke-ChezmoiApply $Mode }
        'desktop' { & (Join-Path $PSScriptRoot 'setup-registry.ps1') -Scope user -DryRun:$dry }
        'wallpaper' { & (Join-Path $PSScriptRoot 'setup-wallpaper.ps1') -DryRun:$dry }
        'sync' { & (Join-Path $PSScriptRoot 'setup-sync.ps1') -DryRun:$dry }
        'system' { Invoke-System -Preview:$dry }
    }
}

# The system step previews as the current user; applying it needs admin, so a normal
# shell opens the same script in an administrator window (UAC) and waits for it.
function Invoke-System([switch]$Preview) {
    $systemScript = Join-Path $PSScriptRoot 'setup-system.ps1'
    if ($Preview) {
        & $systemScript -DryRun
        $exitCode = $LASTEXITCODE
    } elseif ($NonInteractive) {
        Stop-Tool 'The system step changes machine settings and never runs non-interactively.'
    } elseif (Test-Elevated) {
        & $systemScript
        $exitCode = $LASTEXITCODE
    } else {
        Write-Step 'Opening an administrator window for the system step...'
        $shell = (Get-Process -Id $PID).Path
        $process = Start-Process -FilePath $shell -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$systemScript`"", '-PauseOnExit'
        )
        $exitCode = $process.ExitCode
    }
    if ($exitCode -ne 0) {
        Stop-Tool "The system step failed (exit code $exitCode)"
    }
}

# Steps whose inputs changed, in step order, for repository paths
function Get-StepsForPath([string[]]$Path) {
    $wanted = @{}
    foreach ($item in $Path) {
        switch -Wildcard ($item) {
            'home/.chezmoidata/packages.yaml' { $wanted.packages = $true; $wanted.fonts = $true; break }
            'home/.chezmoidata/windows.yaml' { $wanted.desktop = $true; $wanted.system = $true; break }
            'home/.chezmoidata/kde.yaml' { break }
            'home/.chezmoiexternal.toml.tmpl' { $wanted.apply = $true; $wanted.wallpaper = $true; break }
            'home/.chezmoidata.yaml' { $wanted.apply = $true; $wanted.wallpaper = $true; break }
            'home/*' { $wanted.apply = $true; break }
        }
    }
    return @($script:Steps | Where-Object { $wanted.ContainsKey($_) })
}

function Get-RepoGit([string[]]$Arguments) {
    # Windows PowerShell 5.1 turns native stderr into a terminating error under 'Stop'
    $ErrorActionPreference = 'Continue'
    return @(& git -C (Get-RepoRoot) @Arguments 2>$null)
}

# Pull (fast-forward only, after showing the commits), then run the steps whose files changed
function Invoke-SyncCommand {
    $syncScript = Join-Path $PSScriptRoot 'sync.ps1'
    if ($Check) {
        & $syncScript -Check -Notify:$Notify
        return
    }
    if ($NonInteractive) {
        Stop-Tool 'dots sync asks before pulling; use dots sync -Check without a terminal.'
    }

    $localChanges = @(Get-RepoGit @('status', '--porcelain', '--untracked-files=no'))
    if ($localChanges.Count -gt 0) {
        $localChanges | ForEach-Object { Write-Host "  $_" }
        Stop-Tool 'The repository has local changes; commit them (dots capture) before syncing.'
    }

    . $syncScript
    $state = Invoke-SyncCheck
    if ($state.Behind -eq 0) {
        Write-Success 'Already up to date'
        return
    }

    $before = "$(Get-RepoGit @('rev-parse', 'HEAD'))".Trim()
    Get-RepoGit @('log', '--oneline', '--no-decorate', 'HEAD..@{upstream}') | ForEach-Object { Write-Host "  $_" }
    Get-RepoGit @('diff', '--stat', 'HEAD...@{upstream}') | ForEach-Object { Write-Host "  $_" }
    if (-not (Confirm-Yes 'Pull these commits?')) {
        Write-ToolWarning 'Nothing pulled'
        return
    }
    if ((Invoke-NativeCommand -FilePath 'git' -ArgumentList @('-C', (Get-RepoRoot), 'merge', '--ff-only', '--quiet', '@{upstream}') -IgnoreExitCode) -ne 0) {
        Stop-Tool 'Cannot fast-forward (local commits?); rebase or merge by hand.'
    }
    $after = "$(Get-RepoGit @('rev-parse', 'HEAD'))".Trim()
    Write-Success "Pulled $($before.Substring(0, 7))..$($after.Substring(0, 7))"

    $steps = Get-StepsForPath (Get-RepoGit @('diff', '--name-only', $before, $after))
    if ($steps.Count -eq 0) {
        Write-Success 'No step needs to run for these changes'
        return
    }
    Write-Step "Steps for the changed files: $($steps -join ' ')"
    Invoke-StepList $steps
    if (-not $script:StoppedEarly) {
        Write-Success 'Sync complete'
    }
}

function Invoke-Status {
    $root = Get-RepoRoot
    $branch = "$(Get-RepoGit @('branch', '--show-current'))".Trim()
    Write-Host "Repository   $root ($(if ($branch) { $branch } else { 'detached' }))"
    $upstream = "$(Get-RepoGit @('rev-parse', '--abbrev-ref', '@{upstream}'))".Trim()
    if ($upstream) {
        $env:GIT_TERMINAL_PROMPT = '0'
        Get-RepoGit @('fetch', '--quiet') | Out-Null
        $behind = "$(Get-RepoGit @('rev-list', '--count', 'HEAD..@{upstream}'))".Trim()
        $ahead = "$(Get-RepoGit @('rev-list', '--count', '@{upstream}..HEAD'))".Trim()
        Write-Host "Upstream     $($upstream): $behind behind, $ahead ahead"
    } else {
        Write-Host 'Upstream     none'
    }
    Write-Host "Local edits  $(@(Get-RepoGit @('status', '--porcelain')).Count) file(s) changed in the repository"
    if (Test-Command 'chezmoi') {
        $ErrorActionPreference = 'Continue'
        $drift = @(& chezmoi --source (Join-Path $root 'home') status --exclude externals 2>$null).Count
        Write-Host "Drift        $drift target(s) differ from home/ (dots capture)"
    }
    if (Test-Command 'Get-ScheduledTask') {
        $task = Get-ScheduledTask -TaskName 'dots-sync' -TaskPath '\dots\' -ErrorAction SilentlyContinue
        $taskState = if ($task) { "$($task.State)" } else { 'not registered (run the sync step: dots bootstrap)' }
        Write-Host "Sync task    $taskState"
    }
}

function Invoke-SystemCommand {
    if ($DryRun) {
        Invoke-System -Preview
        return
    }
    if ($NonInteractive) {
        Stop-Tool 'dots system changes machine settings and never runs non-interactively; use -DryRun to preview.'
    }

    Invoke-System -Preview
    if (Confirm-Yes 'Apply these system settings as administrator?') {
        Invoke-System
    } else {
        Write-ToolWarning 'Nothing changed'
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

# Runs the given steps in order: describe, preview, ask run / skip / quit.
# Sets $script:StoppedEarly when the person quits (steps may write to the pipeline,
# so it is not a return value).
function Invoke-StepList([string[]]$StepList, [string[]]$SkipStep = @()) {
    $script:StoppedEarly = $false
    foreach ($step in $StepList) {
        Write-Step "[$step] $(Get-StepDescription $step)"

        if ($step -in $SkipStep) {
            Write-ToolWarning "Skipping $step"
            continue
        }
        if (-not (Test-StepEnabled $step)) {
            Write-ToolWarning "Skipping $step (disabled in .features)"
            continue
        }
        if ($step -eq 'system' -and $NonInteractive -and -not $DryRun) {
            Write-ToolWarning 'Skipping system (admin; it never runs non-interactively, run dots system later)'
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
                Write-ToolWarning "Stopped before $step; run the same dots command again to continue."
                $script:StoppedEarly = $true
                return
            }
        }
    }
}

function Invoke-Bootstrap {
    # pwsh -File passes "-Skip a,b" as one string; split it
    $skipSteps = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($step in $skipSteps) {
        if ($step -notin $script:Steps) {
            Stop-Tool "Unknown step: $step (steps: $($script:Steps -join ' '))"
        }
    }

    Invoke-StepList $script:Steps $skipSteps
    if ($script:StoppedEarly) {
        return
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
    if ($Diff) {
        & (Join-Path $PSScriptRoot 'package-diff.ps1')
        return
    }
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

function Test-SshAgentKey {
    # Windows PowerShell 5.1 turns native stderr into a terminating error under 'Stop'
    $ErrorActionPreference = 'Continue'
    if (-not (Test-Command 'ssh-add')) {
        return $false
    }
    & ssh-add -l *> $null
    return $LASTEXITCODE -eq 0
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
    foreach ($tool in @('pwsh', 'winget', 'scoop', 'oh-my-posh', 'gum', 'gitleaks', 'fzf', 'bw')) {
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

    Write-Step 'SSH agent'
    if ((Get-ChezmoiValue '.accounts.ssh.agent' 'bitwarden') -ne 'bitwarden') {
        Write-Success 'SSH keys are files on disk (.accounts.ssh.agent = file)'
    } elseif (Test-WindowsAgentRunning) {
        Write-ToolWarning 'The Windows OpenSSH Authentication Agent is running and blocks Bitwarden; run: dots system'
    } elseif (Test-SshAgentKey) {
        Write-Success 'Bitwarden SSH agent is running and holds keys'
    } else {
        Write-ToolWarning 'Bitwarden SSH agent is not running or holds no keys; see the accounts step: dots bootstrap'
    }

    Write-Step 'Sync task'
    if (Test-Command 'Get-ScheduledTask') {
        if (Get-ScheduledTask -TaskName 'dots-sync' -TaskPath '\dots\' -ErrorAction SilentlyContinue) {
            Write-Success 'The dots-sync task is registered (repository check at logon and every 6 hours)'
        } else {
            Write-ToolWarning 'The dots-sync task is not registered; run the sync step: dots bootstrap'
        }
    } else {
        Write-ToolWarning 'Scheduled Tasks are unavailable; the repository check cannot run here'
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
        'system' { Invoke-SystemCommand }
        'sync' { Invoke-SyncCommand }
        'status' { Invoke-Status }
        'capture' { & (Join-Path $PSScriptRoot 'capture.ps1') -DryRun:$DryRun -NonInteractive:$NonInteractive }
        'doctor' {
            if ((Invoke-Doctor) -gt 0) {
                exit 1
            }
        }
        'update' {
            & (Join-Path $PSScriptRoot 'update.ps1') -Packages:$Packages -Fonts:$Fonts -DryRun:$DryRun -NonInteractive:$NonInteractive
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
        { $_ -in $script:Steps } {
            # dots <step>: one bootstrap step on its own, previewed and confirmed
            Invoke-StepList @($Command)
        }
        default {
            Show-Usage
            Stop-Tool "Unknown command: $Command"
        }
    }
}

# Dot-sourcing (Pester) loads the functions without running a command
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-DotsCommand
    # Probes such as ssh-add -L leave a non-zero $LASTEXITCODE behind; failures throw instead
    exit 0
}
