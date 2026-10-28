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
        foreach ($name in @('bootstrap', 'packages', 'doctor', 'update', 'backup', 'cleanup')) {
            $output | Should -Match $name
        }
    }

    It 'rejects unknown commands and steps' {
        { & $Dots no-such-command 6>$null } | Should -Throw '*Unknown command: no-such-command*'
        { & $Dots bootstrap -Skip no-such-step 6>$null } | Should -Throw '*Unknown step: no-such-step*'
    }

    It 'completes a dry run with every step skipped' {
        $output = & $Dots bootstrap -DryRun -NonInteractive -Skip packages, git, accounts, fonts, shell, apply *>&1 | Out-String
        $output | Should -Match 'Skipping packages'
        $output | Should -Match 'Skipping apply'
        $output | Should -Match 'Bootstrap complete'
    }

    It 'accepts -Skip as one comma-separated string, as pwsh -File passes it' {
        $output = & $Dots bootstrap -DryRun -NonInteractive -Skip 'packages,git,accounts,fonts,shell,apply' *>&1 | Out-String
        $output | Should -Match 'Skipping fonts'
        $output | Should -Match 'Bootstrap complete'
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

        $script:Calls | Should -Be @('packages/preview', 'git/preview')
    }

    It 'runs a step after yes' {
        $script:Answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('y', 'q'))
        Mock Read-Host { $script:Answers.Dequeue() }

        Invoke-Bootstrap 3>$null 6>$null

        $script:Calls | Should -Be @('packages/preview', 'packages/run', 'git/preview')
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
