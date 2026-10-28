BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $RepoRoot 'scripts\windows\lib\Common.ps1')
    $script:HasChezmoi = [bool](Get-Command chezmoi -ErrorAction SilentlyContinue)
}

Describe 'Format-NativeCommand' {
    It 'quotes arguments that contain spaces or quotes' {
        Format-NativeCommand 'winget' @('install', 'a b', 'x"y') | Should -Be '+ winget install "a b" "x\"y"'
    }
}

Describe 'Invoke-NativeCommand' {
    It 'prints the command instead of running it in a dry run' {
        $output = Invoke-NativeCommand -FilePath 'no-such-command' -ArgumentList @('x') -DryRun 6>&1 | Out-String
        $output | Should -Match '\+ no-such-command x'
    }
}

Describe 'Get-ManifestList' {
    It 'reads GUI apps from WinGet and CLI tools from Scoop' {
        if (-not $HasChezmoi) {
            Set-ItResult -Skipped -Because 'chezmoi is not installed'
            return
        }

        $winget = @(Get-ManifestList 'winget')
        $scoop = @(Get-ManifestList 'scoop')

        $winget | Should -Contain 'Git.Git'
        $winget | Should -Contain 'Microsoft.PowerShell'
        $winget | Should -Not -Contain 'ripgrep'
        $scoop | Should -Contain 'ripgrep'
        $scoop | Should -Contain 'oh-my-posh'
        @(Get-ManifestList 'nerdFonts') | Should -Be @('JetBrainsMono')
    }
}

Describe 'Test-ScoopApp' {
    BeforeEach {
        $env:SCOOP = Join-Path $TestDrive 'scoop'
        New-Item -ItemType Directory -Force -Path (Join-Path $env:SCOOP 'apps\ripgrep\current') | Out-Null
    }
    AfterEach {
        Remove-Item Env:SCOOP
    }

    It 'finds apps installed under the Scoop root, with or without a bucket' {
        Test-ScoopApp 'ripgrep' | Should -BeTrue
        Test-ScoopApp 'main/ripgrep' | Should -BeTrue
        Test-ScoopApp 'fd' | Should -BeFalse
    }
}
