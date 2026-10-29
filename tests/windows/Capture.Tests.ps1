BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Capture = Join-Path $RepoRoot 'scripts\windows\capture.ps1'
    $env:DOTS_NO_GUM = '1'
}

Describe 'capture.ps1' {
    BeforeEach {
        . $Capture
        $script:WindowsYaml = Join-Path $TestDrive 'windows.yaml'
        Set-Content -LiteralPath $script:WindowsYaml -Encoding ASCII -Value @(
            'windows:',
            '  registry:',
            '    user:',
            "      - { path: 'HKCU:\Software\Test', name: Count, type: DWord, value: 0 }",
            "      - { path: 'HKCU:\Software\Test', name: Label, type: String, value: 'old' }"
        )
        Mock Invoke-RepoGit { @() }
        Mock Get-ChezmoiDrift { @() }
        Mock Test-RegistryAvailable { $false }
        Mock Get-ExtraPackage { @() }
    }

    It 'offers repository files, copied dotfiles, and lists templates apart' {
        Mock Invoke-RepoGit { @(' M home/dot_gitconfig.tmpl', '?? docs/new.md') } -ParameterFilter { $Arguments[0] -eq 'status' }
        Mock Get-ChezmoiDrift { @('MM .config/wezterm/wezterm.lua', 'MM .gitconfig', ' M .config/other') }
        Mock Get-ChezmoiSourcePath { 'C:\repo\home\dot_config\wezterm\wezterm.lua' } -ParameterFilter { $Target -like '*wezterm.lua' }
        Mock Get-ChezmoiSourcePath { 'C:\repo\home\dot_gitconfig.tmpl' } -ParameterFilter { $Target -like '*.gitconfig' }

        $labels = @(Get-CaptureItem | ForEach-Object { $_.Label })

        $labels[0] | Should -Be 'file       M home/dot_gitconfig.tmpl'
        $labels[1] | Should -Be 'file      ?? docs/new.md'
        $labels[2] | Should -Match '^re-add    .+wezterm\.lua$'
        $labels.Count | Should -Be 3
        $script:Templates[0] | Should -Match '\.gitconfig \(.+dot_gitconfig\.tmpl\)'
    }

    It 'offers registry values that differ from windows.yaml' {
        Mock Test-RegistryAvailable { $true }
        Mock Test-Command { $true }
        Mock Get-RegistryEntry {
            @([pscustomobject]@{ path = 'HKCU:\Software\Test'; name = 'Count'; type = 'DWord'; value = 0 })
        } -ParameterFilter { $Scope -eq 'user' }
        Mock Get-RegistryEntry { @() } -ParameterFilter { $Scope -eq 'machine' }
        Mock Get-RegistryCurrent { [pscustomobject]@{ Kind = 'DWord'; Value = 5 } }

        $item = @(Get-CaptureItem)[0]

        $item.Label | Should -Be 'registry  HKCU:\Software\Test Count: 0 -> 5'
        $item.Payload.Value | Should -Be 5
    }

    It 'writes a captured registry value into windows.yaml' {
        $count = [pscustomobject]@{ path = 'HKCU:\Software\Test'; name = 'Count'; type = 'DWord'; value = 0 }
        $label = [pscustomobject]@{ path = 'HKCU:\Software\Test'; name = 'Label'; type = 'String'; value = 'old' }

        Set-RegistryYamlValue $count 7
        Set-RegistryYamlValue $label "it's `$1 new"

        $lines = Get-Content -LiteralPath $script:WindowsYaml
        $lines[3] | Should -BeExactly "      - { path: 'HKCU:\Software\Test', name: Count, type: DWord, value: 7 }"
        $lines[4] | Should -BeExactly "      - { path: 'HKCU:\Software\Test', name: Label, type: String, value: 'it''s `$1 new' }"
        { Set-RegistryYamlValue ([pscustomobject]@{ path = 'HKCU:\Nope'; name = 'X'; type = 'DWord' }) 1 } |
            Should -Throw '*No windows.yaml entry*'
    }

    It 'lists items in a dry run and refuses to run without a terminal' {
        Mock Invoke-RepoGit { @(' M home/dot_zshrc') } -ParameterFilter { $Arguments[0] -eq 'status' }

        $output = Invoke-Capture -DryRun 6>&1 | Out-String
        $output | Should -Match '1 item\(s\) to capture'
        $output | Should -Match 'file       M home/dot_zshrc'

        { Invoke-Capture -NonInteractive 6>$null } | Should -Throw '*never runs non-interactively*'
    }

    It 'stages only the chosen items, then commits and pushes to main' {
        $script:Git = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-RepoGit { $script:Git.Add($Arguments -join ' '); @() }
        Mock Invoke-RepoGit { @(' M docs/a.md', ' M docs/b.md') } -ParameterFilter { $Arguments[0] -eq 'status' }
        Mock Invoke-RepoGit { 'main' } -ParameterFilter { $Arguments[0] -eq 'branch' }
        $script:Staged = $false
        Mock Invoke-RepoGit { if ($script:Staged) { 'docs/b.md' } } -ParameterFilter { $Arguments -contains '--name-only' }
        Mock Invoke-RepoGit { $script:Staged = $true } -ParameterFilter { $Arguments[0] -eq 'add' -and $Arguments[-1] -eq 'docs/b.md' }
        Mock Read-CaptureAnswer { '2' } -ParameterFilter { $Prompt -like 'Numbers*' }
        Mock Read-CaptureAnswer { '' } -ParameterFilter { $Prompt -like 'Commit message*' }
        Mock Confirm-Action { $true }
        $script:Native = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-NativeCommand { $script:Native.Add($ArgumentList -join ' '); 0 }

        Invoke-Capture 6>$null

        Should -Invoke Invoke-RepoGit -ParameterFilter { $Arguments[0] -eq 'add' -and $Arguments[-1] -eq 'docs/b.md' } -Times 1
        Should -Invoke Invoke-RepoGit -ParameterFilter { $Arguments[0] -eq 'add' -and $Arguments[-1] -eq 'docs/a.md' } -Times 0
        $script:Native[0] | Should -Match 'commit --quiet -m Capture local changes from'
        $script:Native[1] | Should -Match 'push --quiet origin main$'
    }
}

Describe 'package-diff.ps1' {
    BeforeEach {
        . (Join-Path $RepoRoot 'scripts\windows\package-diff.ps1')
        $script:PackagesYaml = Join-Path $TestDrive 'packages.yaml'
        Set-Content -LiteralPath $script:PackagesYaml -Encoding ASCII -Value @(
            'packages:',
            '  winget:',
            '    - Microsoft.PowerShell',
            '',
            '  scoop: []',
            '',
            '  nerdFonts:',
            '    - JetBrainsMono'
        )
        Mock Get-ManifestList { @('Microsoft.PowerShell') } -ParameterFilter { $List -eq 'winget' }
        Mock Get-ManifestList { @('extras/vlc', 'ripgrep') } -ParameterFilter { $List -eq 'scoop' }
        Mock Get-ManifestList { @('JetBrainsMono') } -ParameterFilter { $List -eq 'nerdFonts' }
        Mock Get-InstalledWingetId { @('Microsoft.PowerShell', 'Valve.Steam') }
        Mock Get-InstalledScoopApp { @('vlc', 'JetBrainsMono-NF', '7zip') }
    }

    It 'lists installed packages outside the manifest, bucket and font names included' {
        $extra = @(Get-ExtraPackage | ForEach-Object { "$($_.Manager):$($_.Name)" })

        $extra | Should -Be @('winget:Valve.Steam', 'scoop:7zip')
        @(Get-MissingPackage | ForEach-Object { "$($_.Manager):$($_.Name)" }) | Should -Be @('scoop:ripgrep')
    }

    It 'appends to a block list and turns an empty list into one' {
        Add-ManifestPackage 'winget' @('Valve.Steam')
        Add-ManifestPackage 'scoop' @('7zip', 'fd')

        $lines = Get-Content -LiteralPath $script:PackagesYaml
        $lines[2..3] | Should -Be @('    - Microsoft.PowerShell', '    - Valve.Steam')
        $lines[5..7] | Should -Be @('  scoop:', '    - 7zip', '    - fd')
        $lines[-1] | Should -Be '    - JetBrainsMono'
    }
}

Describe 'capture.ps1 packages' {
    BeforeEach {
        . $Capture
        $script:Extra = @(
            [pscustomobject]@{ Manager = 'winget'; Name = 'Valve.Steam' },
            [pscustomobject]@{ Manager = 'scoop'; Name = '7zip' }
        )
        Mock Add-ManifestPackage { }
        Mock Uninstall-ExtraPackage { }
        Mock Invoke-RepoGit { @() }
        Mock Select-CaptureLabel { @('winget  Valve.Steam') }
    }

    It 'adds the chosen packages to the manifest' {
        Mock Read-CaptureAnswer { 'a' }

        Invoke-PackageCapture $script:Extra

        Should -Invoke Add-ManifestPackage -Times 1 -ParameterFilter { $Manager -eq 'winget' -and $Name -eq 'Valve.Steam' }
        Should -Invoke Add-ManifestPackage -Times 0 -ParameterFilter { $Manager -eq 'scoop' }
        Should -Invoke Uninstall-ExtraPackage -Times 0
    }

    It 'uninstalls the chosen packages instead when asked' {
        Mock Read-CaptureAnswer { 'u' }

        Invoke-PackageCapture $script:Extra

        Should -Invoke Uninstall-ExtraPackage -Times 1 -ParameterFilter { $Manager -eq 'winget' -and $Name -eq 'Valve.Steam' }
        Should -Invoke Add-ManifestPackage -Times 0
    }
}
