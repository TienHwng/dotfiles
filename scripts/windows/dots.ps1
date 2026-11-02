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
    # apps
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

# git-config renders ~/.gitconfig (gh credential helper) so github-login can log in to gh
# before anything clones a private repository; wallpaper needs that login.
# system-settings (admin) goes last.
$script:Steps = @(
    'apps', 'git-config', 'github-login', 'fonts', 'shell-setup', 'dotfiles',
    'desktop-settings', 'wallpaper', 'auto-check', 'system-settings'
)

# Names used before 2026-11-03, only to point at the new name; they no longer run
$script:RenamedSteps = @{
    'packages' = 'apps'
    'git' = 'git-config'
    'accounts' = 'github-login'
    'shell' = 'shell-setup'
    'apply' = 'dotfiles'
    'desktop' = 'desktop-settings'
    # dots sync (pull) is still a command; only the step that registered the task moved
    'sync' = 'auto-check'
    'system' = 'system-settings'
}

function Show-Usage {
    Write-Host @'
Usage: dots <command> [options]

Commands:
  bootstrap [-DryRun] [-NonInteractive] [-Skip step,...]
                  Set up this machine step by step: apps, git-config, github-login,
                  fonts, shell-setup, dotfiles, desktop-settings, wallpaper, auto-check,
                  system-settings. Each step says what it does to this computer, shows
                  a preview, and asks run / skip / quit before changing anything.
                  -NonInteractive skips system-settings unless -DryRun is set.
  <step> [-DryRun]
                  Run one of those steps on its own, described, previewed and confirmed.
  apps -Diff      List apps installed outside the manifest, and listed ones that are missing.
  apps -Upgrade   Like the apps step, and also upgrade the installed ones.
  sync [-Check [-Notify]]
                  Pull new commits (fast-forward only, after showing them), then run
                  the steps whose files changed, each with a preview. -Check only
                  fetches and reports how far behind this machine is; -Notify adds a
                  toast with a Sync now button (the auto-check task uses it).
  status          Branch, commits behind/ahead, local changes, chezmoi drift, task.
  capture [-DryRun]
                  Pick what changed on this machine (repository files, dotfiles
                  chezmoi copied, registry values, packages), write it back, review the diff,
                  then commit to main and push.
  doctor          Check required tools, the shell setup, the manifest, and chezmoi.
  update [-Packages] [-Fonts] [-DryRun]
                  Upgrade the manifest's apps (WinGet, Scoop, PowerShell modules), reinstall the
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

function Get-StepTitle([string]$Step) {
    switch ($Step) {
        'apps' { 'Install the apps and command-line tools this setup uses' }
        'git-config' { 'Set your Git name and email, write ~/.gitconfig' }
        'github-login' { 'Log in to GitHub and check your SSH key' }
        'fonts' { 'Install the Nerd Fonts' }
        'shell-setup' { 'Make PowerShell 7 load the shared profile (prompt, colours, the dots command)' }
        'dotfiles' { 'Copy the config files from the repository into your user folder' }
        'desktop-settings' { 'Change Windows settings for your user account (Explorer, dark mode)' }
        'wallpaper' { 'Download the wallpaper collection and set the desktop wallpaper' }
        'auto-check' { 'Check GitHub for repository changes in the background, notify only' }
        'system-settings' { 'Change settings for the whole computer, as administrator' }
    }
}

# What a step does to this computer, in plain words, shown before its preview:
# Does (what changes, where), Never (what it leaves alone), Undo (how to reverse it)
function Get-StepDetail([string]$Step) {
    switch ($Step) {
        'apps' {
            @{
                Does = @(
                    'Installs the missing apps listed in home/.chezmoidata/packages.yaml: desktop apps with winget (where each installer puts them, some ask for administrator rights), command-line tools with Scoop (into ~\scoop, adding ~\scoop\shims to your PATH), PowerShell modules from the PowerShell Gallery (into Documents\PowerShell\Modules).',
                    'Installs Scoop itself the first time (from get.scoop.sh).'
                )
                Never = 'uninstall or upgrade anything already installed (dots update upgrades, after asking).'
                Undo = 'winget uninstall --id <id>, scoop uninstall <app>, Uninstall-Module <name>.'
            }
        }
        'git-config' {
            @{
                Does = @(
                    'Asks for your Git name and email if they are missing, and keeps them in ~\.config\chezmoi\chezmoi.toml on this computer only (never in the repository).',
                    'Replaces ~\.gitconfig with the one built from home/dot_gitconfig.tmpl (the preview shows the difference).'
                )
                Never = 'change the settings of any Git repository.'
                Undo = 'edit ~\.gitconfig by hand; the next dotfiles or git-config run writes it again from the template.'
            }
        }
        'github-login' {
            @{
                Does = @(
                    'If the GitHub CLI is not logged in, opens your browser to log in to GitHub over HTTPS; gh keeps the token in Windows Credential Manager.',
                    'Checks that the Bitwarden SSH agent holds a key and that GitHub accepts it; if GitHub does not know the key yet, offers to add its public key to your GitHub account.',
                    'Stops with a warning while Bitwarden is not set up: skip the step until then.'
                )
                Never = 'store a token or a key in the repository.'
                Undo = 'gh auth logout; remove the key at github.com/settings/keys.'
            }
        }
        'fonts' {
            @{
                Does = @(
                    'Adds the Scoop bucket nerd-fonts and installs each Nerd Font from the manifest for your user account; open apps see them after a restart.'
                )
                Never = 'touch fonts installed for all users.'
                Undo = 'scoop uninstall <font>-NF (for example JetBrainsMono-NF).'
            }
        }
        'shell-setup' {
            @{
                Does = @(
                    'Sets the user environment variable XDG_CONFIG_HOME to ~\.config, where Neovim, oh-my-posh and Git then read their settings.',
                    'Writes Documents\PowerShell\profile.ps1, a 3-line file that loads ~\.config\powershell\profile.ps1 (prompt, colours, the dots command). A different file already there is renamed to profile.ps1.bak-<time> first.'
                )
                Never = 'edit Microsoft.PowerShell_profile.ps1 (it only warns that the file still loads).'
                Undo = 'delete Documents\PowerShell\profile.ps1 (or restore the .bak file) and remove XDG_CONFIG_HOME under System Properties > Environment Variables.'
            }
        }
        'dotfiles' {
            @{
                Does = @(
                    'Copies the config files kept in home/ (Git, SSH, Neovim, WezTerm, PowerShell profile, ...) into your user folder, overwriting the ones that differ; the preview shows every difference.',
                    'Asks before overwriting a file that was edited outside dots.'
                )
                Never = 'delete files it does not manage, or download the wallpapers (the wallpaper step does).'
                Undo = 'there is no backup of the overwritten files: to keep a local edit, skip this step and run dots capture, which saves it into the repository instead.'
            }
        }
        'desktop-settings' {
            @{
                Does = @(
                    'Writes the user registry values from home/.chezmoidata/windows.yaml (HKCU: show file extensions, show hidden files, dark mode for apps), only the ones that differ; the preview shows old -> new.',
                    'Restarts Explorer when an Explorer value changes: the taskbar disappears for a moment and open File Explorer windows close.'
                )
                Never = 'change settings for the whole computer (system-settings does).'
                Undo = 'set the option back in Settings or in File Explorer options.'
            }
        }
        'wallpaper' {
            $dir = (Get-ChezmoiValue '.wallpapers.dir' 'Pictures/wallpaper') -replace '/', '\'
            $image = Get-ChezmoiValue '.wallpapers.current' 'the configured image'
            @{
                Does = @(
                    "Downloads the private repository TienHwng/wallpapers into ~\$dir with your GitHub login, or updates it when it is already there.",
                    "Sets $image from it as the desktop wallpaper."
                )
                Never = "touch a folder at ~\$dir that is not that repository: it stops instead (Windows ignores letter case, so a folder named $($dir.ToUpperInvariant()) counts)."
                Undo = 'pick another wallpaper in Settings; delete the folder to remove the images.'
            }
        }
        'auto-check' {
            @{
                Does = @(
                    'Registers the Scheduled Task \dots\dots-sync for your user: at logon and every 6 hours it asks GitHub for new commits and shows a notification when there are some. It never downloads or changes files.',
                    'Registers the dots-sync: link (HKCU\Software\Classes\dots-sync) so the notification''s Sync now button opens Windows Terminal running dots sync, which shows the commits and asks first.'
                )
                Never = 'pull, apply or install anything on its own.'
                Undo = 'Unregister-ScheduledTask -TaskPath ''\dots\'' -TaskName dots-sync; Remove-Item HKCU:\Software\Classes\dots-sync -Recurse.'
            }
        }
        'system-settings' {
            @{
                Does = @(
                    'Opens an administrator window (UAC) and there:',
                    'writes the machine registry values from home/.chezmoidata/windows.yaml (HKLM): hardware clock in UTC so the time matches CachyOS, Fast Startup off so the Windows disk is fully shut down for the other OS;',
                    'stops and disables the Windows OpenSSH Authentication Agent service, so the Bitwarden SSH agent can take its place (only while .accounts.ssh.agent is bitwarden, the default);',
                    'with an NVIDIA graphics card and no NVIDIA App: downloads the installer pinned in windows.yaml from nvidia.com, checks its SHA-256 and NVIDIA signature, then runs it.',
                    'Some changes take effect after a restart.'
                )
                Never = 'run without asking, or without a terminal.'
                Undo = 'set the values back in an administrator PowerShell (the preview shows the old ones); Set-Service ssh-agent -StartupType Manual; uninstall the NVIDIA App from Settings > Apps.'
            }
        }
    }
}

function Write-StepDetail([string]$Step) {
    $detail = Get-StepDetail $Step
    Write-Host '  What it does to this computer:'
    $detail.Does | ForEach-Object { Write-Host "    - $_" }
    Write-Host "  It does not $($detail.Never)"
    Write-Host "  To undo: $($detail.Undo)"
}

function Test-StepEnabled([string]$Step) {
    switch ($Step) {
        'fonts' { return (Get-ChezmoiValue '.features.installFonts' 'true') -eq 'true' }
        'shell-setup' { return (Get-ChezmoiValue '.features.setupShell' 'true') -eq 'true' }
        'desktop-settings' { return (Get-ChezmoiValue '.features.desktop' 'true') -eq 'true' }
        'wallpaper' { return (Get-ChezmoiValue '.features.wallpapers' 'true') -eq 'true' }
        default { return $true }
    }
}

# The new name of a step or command renamed on 2026-11-03, or $null
function Get-RenamedStep([string]$Name) {
    if ($script:RenamedSteps.ContainsKey($Name)) {
        return $script:RenamedSteps[$Name]
    }
    return $null
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
        'apps' { & (Join-Path $PSScriptRoot 'install-packages.ps1') -DryRun:$dry -Upgrade:$Upgrade; if (-not $dry) { Update-ProcessPath } }
        'git-config' {
            & (Join-Path $PSScriptRoot 'setup-git.ps1') -DryRun:$dry -NonInteractive:$quiet
            Invoke-ChezmoiApply $Mode @(Join-Path $HOME '.gitconfig')
        }
        'github-login' { & (Join-Path $PSScriptRoot 'setup-accounts.ps1') -DryRun:$dry -NonInteractive:$quiet }
        'fonts' { & (Join-Path $PSScriptRoot 'install-fonts.ps1') -DryRun:$dry }
        'shell-setup' { & (Join-Path $PSScriptRoot 'setup-shell.ps1') -Shell 'pwsh' -DryRun:$dry }
        'dotfiles' { Invoke-ChezmoiApply $Mode }
        'desktop-settings' { & (Join-Path $PSScriptRoot 'setup-registry.ps1') -Scope user -DryRun:$dry }
        'wallpaper' { & (Join-Path $PSScriptRoot 'setup-wallpaper.ps1') -DryRun:$dry }
        'auto-check' { & (Join-Path $PSScriptRoot 'setup-sync.ps1') -DryRun:$dry }
        'system-settings' { Invoke-System -Preview:$dry }
    }
}

# The system-settings step previews as the current user; applying it needs admin, so a normal
# shell opens the same script in an administrator window (UAC) and waits for it.
function Invoke-System([switch]$Preview) {
    $systemScript = Join-Path $PSScriptRoot 'setup-system.ps1'
    if ($Preview) {
        & $systemScript -DryRun
        $exitCode = $LASTEXITCODE
    } elseif ($NonInteractive) {
        Stop-Tool 'The system-settings step changes machine settings and never runs non-interactively.'
    } elseif (Test-Elevated) {
        & $systemScript
        $exitCode = $LASTEXITCODE
    } else {
        Write-Step 'Opening an administrator window for system-settings...'
        $shell = (Get-Process -Id $PID).Path
        $process = Start-Process -FilePath $shell -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$systemScript`"", '-PauseOnExit'
        )
        $exitCode = $process.ExitCode
    }
    if ($exitCode -ne 0) {
        Stop-Tool "The system-settings step failed (exit code $exitCode)"
    }
}

# Steps whose inputs changed, in step order, for repository paths
function Get-StepsForPath([string[]]$Path) {
    $wanted = @{}
    foreach ($item in $Path) {
        switch -Wildcard ($item) {
            'home/.chezmoidata/packages.yaml' { $wanted['apps'] = $true; $wanted['fonts'] = $true; break }
            'home/.chezmoidata/windows.yaml' { $wanted['desktop-settings'] = $true; $wanted['system-settings'] = $true; break }
            'home/.chezmoidata/kde.yaml' { break }
            'home/.chezmoiexternal.toml.tmpl' { $wanted['dotfiles'] = $true; $wanted['wallpaper'] = $true; break }
            'home/.chezmoidata.yaml' { $wanted['dotfiles'] = $true; $wanted['wallpaper'] = $true; break }
            'home/*' { $wanted['dotfiles'] = $true; break }
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
        $taskState = if ($task) { "$($task.State)" } else { 'not registered (run: dots auto-check)' }
        Write-Host "Sync task    $taskState"
    }
}

function Invoke-SystemCommand {
    Write-Step "[system-settings] $(Get-StepTitle 'system-settings')"
    Write-StepDetail 'system-settings'
    if ($DryRun) {
        Write-Host '  Dry run, nothing changes:'
        Invoke-System -Preview
        return
    }
    if ($NonInteractive) {
        Stop-Tool 'dots system-settings changes machine settings and never runs non-interactively; use -DryRun to preview.'
    }

    Write-Host '  Preview, nothing has changed yet:'
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
        Write-Step "[$step] $(Get-StepTitle $step)"

        if ($step -in $SkipStep) {
            Write-ToolWarning "Skipping $step"
            continue
        }
        if (-not (Test-StepEnabled $step)) {
            Write-ToolWarning "Skipping $step (disabled in .features)"
            continue
        }
        if ($step -eq 'system-settings' -and $NonInteractive -and -not $DryRun) {
            Write-ToolWarning 'Skipping system-settings (admin; it never runs non-interactively, run dots system-settings later)'
            continue
        }
        Write-StepDetail $step
        if ($DryRun) {
            Write-Host '  Dry run, nothing changes:'
        }
        if ($DryRun -or $NonInteractive) {
            Invoke-Step $step 'run'
            continue
        }

        Write-Host '  Preview, nothing has changed yet:'
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
            $renamed = Get-RenamedStep $step
            if ($renamed) {
                Stop-Tool "Unknown step: $step (renamed to $renamed)"
            }
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
        Write-ToolWarning 'XDG_CONFIG_HOME is not set; run: dots shell-setup'
    }
    $stubFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\profile.ps1'
    if ((Test-Path -LiteralPath $stubFile) -and
        (Select-String -LiteralPath $stubFile -SimpleMatch 'Written by dotfiles' -Quiet)) {
        Write-Success "Profile stub: $stubFile"
    } else {
        Write-ToolWarning "Profile stub missing at $stubFile; run: dots shell-setup"
    }

    Write-Step 'SSH agent'
    if ((Get-ChezmoiValue '.accounts.ssh.agent' 'bitwarden') -ne 'bitwarden') {
        Write-Success 'SSH keys are files on disk (.accounts.ssh.agent = file)'
    } elseif (Test-WindowsAgentRunning) {
        Write-ToolWarning 'The Windows OpenSSH Authentication Agent is running and blocks Bitwarden; run: dots system-settings'
    } elseif (Test-SshAgentKey) {
        Write-Success 'Bitwarden SSH agent is running and holds keys'
    } else {
        Write-ToolWarning 'Bitwarden SSH agent is not running or holds no keys; see: dots github-login'
    }

    Write-Step 'Sync task'
    if (Test-Command 'Get-ScheduledTask') {
        if (Get-ScheduledTask -TaskName 'dots-sync' -TaskPath '\dots\' -ErrorAction SilentlyContinue) {
            Write-Success 'The dots-sync task is registered (repository check at logon and every 6 hours)'
        } else {
            Write-ToolWarning 'The dots-sync task is not registered; run: dots auto-check'
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
        # These two are steps too: break keeps the step clause below from running them again
        'apps' {
            if ($Diff) {
                & (Join-Path $PSScriptRoot 'package-diff.ps1')
            } else {
                Invoke-StepList @('apps')
            }
            break
        }
        'system-settings' { Invoke-SystemCommand; break }
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
            $renamed = Get-RenamedStep $Command
            if ($renamed) {
                Stop-Tool "Unknown command: $Command (renamed to $($renamed): dots $renamed)"
            }
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
