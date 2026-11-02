BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:WindowsScripts = Join-Path $RepoRoot 'scripts\windows'
    $script:Dots = Join-Path $WindowsScripts 'dots.ps1'
    $script:HasChezmoi = [bool](Get-Command chezmoi -ErrorAction SilentlyContinue)
    $env:DOTS_NO_GUM = '1'
}

Describe 'dots.ps1 commands' {
    It 'lists every command in help' {
        $output = & $Dots help 6>&1 | Out-String
        foreach ($name in @('bootstrap', 'apps', 'sync', 'status', 'system-settings', 'doctor', 'update', 'backup', 'cleanup')) {
            $output | Should -Match $name
        }
    }

    It 'rejects unknown commands and steps' {
        { & $Dots no-such-command 6>$null } | Should -Throw '*Unknown command: no-such-command*'
        { & $Dots bootstrap -Skip no-such-step 6>$null } | Should -Throw '*Unknown step: no-such-step*'
    }

    It 'completes a dry run with every step skipped' {
        $output = & $Dots bootstrap -DryRun -NonInteractive -Skip apps, git-config, github-login, fonts, shell-setup, dotfiles, desktop-settings, wallpaper, auto-check, system-settings *>&1 | Out-String
        $output | Should -Match 'Skipping apps'
        $output | Should -Match 'Skipping dotfiles'
        $output | Should -Match 'Bootstrap complete'
        $output | Should -Not -Match 'What it does to this computer'
    }

    It 'accepts -Skip as one comma-separated string, as pwsh -File passes it' {
        $output = & $Dots bootstrap -DryRun -NonInteractive -Skip 'apps,git-config,github-login,fonts,shell-setup,dotfiles,desktop-settings,wallpaper,auto-check,system-settings' *>&1 | Out-String
        $output | Should -Match 'Skipping fonts'
        $output | Should -Match 'Bootstrap complete'
    }

    It 'names the new step when an old name is used' {
        { & $Dots desktop 6>$null } | Should -Throw '*Unknown command: desktop (renamed to desktop-settings: dots desktop-settings)*'
        { & $Dots bootstrap -Skip accounts 6>$null } | Should -Throw '*Unknown step: accounts (renamed to github-login)*'
    }
}

Describe 'Step descriptions' {
    BeforeAll {
        . $Dots
    }

    It 'says what <_> does, what it leaves alone and how to undo it' -ForEach @(
        'apps', 'git-config', 'github-login', 'fonts', 'shell-setup', 'dotfiles',
        'desktop-settings', 'wallpaper', 'auto-check', 'system-settings'
    ) {
        Get-StepTitle $_ | Should -Not -BeNullOrEmpty
        $detail = Get-StepDetail $_
        @($detail.Does).Count | Should -BeGreaterThan 0
        $detail.Never | Should -Not -BeNullOrEmpty
        $detail.Undo | Should -Not -BeNullOrEmpty
        (@($detail.Does) + $detail.Never + $detail.Undo) -join ' ' | Should -Match '^[\x20-\x7E]+$'
    }

    It 'covers every step' {
        $script:Steps | Should -Be @('apps', 'git-config', 'github-login', 'fonts', 'shell-setup', 'dotfiles',
            'desktop-settings', 'wallpaper', 'auto-check', 'system-settings')
    }

    It 'prints the description before the preview and the question' {
        Mock Test-StepEnabled { $true }
        Mock Invoke-Step { Write-Host "PREVIEW $Step" }
        Mock Read-Host { 'q' }

        $output = Invoke-StepList @('desktop-settings') 3>$null 6>&1 | Out-String

        $output | Should -Match '(?s)\[desktop-settings\] Change Windows settings.*What it does to this computer:.*Restarts Explorer.*It does not .*To undo: .*Preview, nothing has changed yet:.*PREVIEW desktop-settings'
    }
}

Describe 'Single steps' {
    It 'runs one step by its name' {
        . $Dots
        $script:Ran = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-StepList { $script:Ran.Add($StepList -join ',') }
        Set-Variable -Name Command -Value 'desktop-settings'

        Invoke-DotsCommand

        $script:Ran | Should -Be @('desktop-settings')
    }

    It 'runs dots apps once, as the apps step' {
        . $Dots
        $script:Ran = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-StepList { $script:Ran.Add($StepList -join ',') }
        Set-Variable -Name Command -Value 'apps'

        Invoke-DotsCommand

        $script:Ran | Should -Be @('apps')
    }
}

Describe 'System step policy' {
    BeforeEach {
        . $Dots
        Mock Test-StepEnabled { $true }
        Mock Write-ManualChecklist { }
    }

    It 'skips system-settings in a non-interactive bootstrap' {
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-Step { $script:Calls.Add("$Step/$Mode") }
        # dots.ps1 functions read the variable from the calling scope
        Set-Variable -Name NonInteractive -Value $true

        $output = Invoke-Bootstrap 3>&1 6>$null | Out-String

        $script:Calls | Should -Not -Contain 'system-settings/run'
        $script:Calls | Should -Contain 'desktop-settings/run'
        $output | Should -Match 'Skipping system-settings'
    }

    It 'refuses dots system-settings without a terminal unless it is a dry run' {
        # dots.ps1 functions read the variable from the calling scope
        Set-Variable -Name NonInteractive -Value $true

        { Invoke-SystemCommand 6>$null } | Should -Throw '*never runs non-interactively*'
    }

    It 'previews, asks, then applies dots system-settings' {
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-System { $script:Calls.Add("preview=$Preview") }
        Mock Read-Host { 'y' }

        Invoke-SystemCommand 6>$null

        $script:Calls | Should -Be @('preview=True', 'preview=False')
    }
}

Describe 'Interactive bootstrap' {
    BeforeEach {
        # Loads the functions; parameters keep their defaults (no -DryRun, -NonInteractive, -Skip)
        . $Dots
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        Mock Test-StepEnabled { $true }
        Mock Invoke-Step { $script:Calls.Add("$Step/$Mode") }
        Mock Write-ManualChecklist { }
    }

    It 'previews each step and honours skip and quit' {
        $script:Answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('s', 'q'))
        Mock Read-Host { $script:Answers.Dequeue() }

        Invoke-Bootstrap 3>$null 6>$null

        $script:Calls | Should -Be @('apps/preview', 'git-config/preview')
    }

    It 'runs a step after yes' {
        $script:Answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('y', 'q'))
        Mock Read-Host { $script:Answers.Dequeue() }

        Invoke-Bootstrap 3>$null 6>$null

        $script:Calls | Should -Be @('apps/preview', 'apps/run', 'git-config/preview')
    }
}

Describe 'Windows step scripts in a dry run' {
    BeforeAll {
        $env:SCOOP = Join-Path $TestDrive 'scoop'
    }
    AfterAll {
        Remove-Item Env:SCOOP
    }

    It 'install-packages prints WinGet and Scoop installs without installing' {
        if (-not $HasChezmoi) {
            Set-ItResult -Skipped -Because 'chezmoi is not installed'
            return
        }

        $output = & (Join-Path $WindowsScripts 'install-packages.ps1') -DryRun *>&1 | Out-String

        $output | Should -Match 'Microsoft\.PowerShell'
        $output | Should -Match '\+ scoop install ripgrep'
        $output | Should -Match 'PowerShell Gallery: \d+ module'
        $output | Should -Match "Install-Module -Name 'Terminal-Icons'|Terminal-Icons is installed"
        Test-Path -LiteralPath $env:SCOOP | Should -BeFalse
    }

    It 'update lists package upgrades and fonts without pulling the repository' {
        if (-not $HasChezmoi) {
            Set-ItResult -Skipped -Because 'chezmoi is not installed'
            return
        }

        $output = & (Join-Path $WindowsScripts 'update.ps1') -DryRun *>&1 | Out-String

        $output | Should -Match 'Packages from the manifest'
        $output | Should -Match 'Nerd Fonts'
        $output | Should -Not -Match 'chezmoi update'
        Test-Path -LiteralPath $env:SCOOP | Should -BeFalse
    }

    It 'install-fonts prints the Scoop Nerd Font install' {
        if (-not $HasChezmoi) {
            Set-ItResult -Skipped -Because 'chezmoi is not installed'
            return
        }

        $output = & (Join-Path $WindowsScripts 'install-fonts.ps1') -DryRun *>&1 | Out-String

        $output | Should -Match '\+ scoop bucket add nerd-fonts'
        $output | Should -Match '\+ scoop install nerd-fonts/JetBrainsMono-NF'
        Test-Path -LiteralPath $env:SCOOP | Should -BeFalse
    }

    It 'setup-shell leaves the profile and XDG_CONFIG_HOME alone' {
        if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
            Set-ItResult -Skipped -Because 'user environment variables and Documents are Windows-only'
            return
        }

        $stubFile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\profile.ps1'
        $stubBefore = if (Test-Path -LiteralPath $stubFile) { Get-Content -LiteralPath $stubFile -Raw } else { $null }
        $configHomeBefore = [Environment]::GetEnvironmentVariable('XDG_CONFIG_HOME', 'User')

        $output = & (Join-Path $WindowsScripts 'setup-shell.ps1') -DryRun *>&1 | Out-String

        $output | Should -Match 'profile stub'
        $stubAfter = if (Test-Path -LiteralPath $stubFile) { Get-Content -LiteralPath $stubFile -Raw } else { $null }
        $stubAfter | Should -Be $stubBefore
        [Environment]::GetEnvironmentVariable('XDG_CONFIG_HOME', 'User') | Should -Be $configHomeBefore
    }
}

Describe 'bootstrap.ps1 downloaded on its own' {
    It 'runs without the repository library until the clone' {
        if (-not $HasChezmoi) {
            Set-ItResult -Skipped -Because 'chezmoi is not installed'
            return
        }

        $standalone = Join-Path $TestDrive 'dots-bootstrap.ps1'
        Copy-Item -LiteralPath (Join-Path $WindowsScripts 'bootstrap.ps1') -Destination $standalone
        $output = [System.Collections.Generic.List[string]]::new()

        { & $standalone -DryRun -NonInteractive -Repo 'TienHwng' *>&1 | ForEach-Object { $output.Add("$_") } } |
            Should -Throw '*Dry-run requires an existing local repository checkout*'
        ($output -join "`n") | Should -Match '\+ chezmoi init --promptDefaults https://github.com/TienHwng/dotfiles.git'
    }
}
