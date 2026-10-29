BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:WindowsScripts = Join-Path $RepoRoot 'scripts\windows'
    $env:DOTS_NO_GUM = '1'
}

Describe 'sync.ps1' {
    BeforeEach {
        . (Join-Path $WindowsScripts 'sync.ps1')
        $script:Toasts = [System.Collections.Generic.List[string]]::new()
        Mock Show-SyncToast { $script:Toasts.Add($Xml) }
        Mock Get-NotifiedPath { Join-Path $TestDrive 'state\notified' }
    }

    It 'builds a protocol toast with a Sync now button and escaped text' {
        [xml]$xml = New-SyncToastXml 3 'origin/<main>'

        $xml.toast.activationType | Should -Be 'protocol'
        $xml.toast.actions.action.content | Should -Be 'Sync now'
        $xml.toast.actions.action.arguments | Should -Be 'dots-sync:'
        $xml.toast.visual.binding.text[1] | Should -Match '3 new commit\(s\) on origin/<main>'
    }

    It 'notifies once per upstream commit' {
        $state = [pscustomobject]@{ Upstream = 'origin/main'; UpstreamSha = 'aaa'; Behind = 2; Ahead = 0 }

        Invoke-SyncNotify $state
        Invoke-SyncNotify $state
        $script:Toasts.Count | Should -Be 1

        $state.UpstreamSha = 'bbb'
        Invoke-SyncNotify $state
        $script:Toasts.Count | Should -Be 2
    }

    It 'stays quiet when the machine is up to date or -Notify is off' {
        Mock Get-SyncState { [pscustomobject]@{ Upstream = 'origin/main'; UpstreamSha = 'aaa'; Behind = 0; Ahead = 1 } }
        $output = Invoke-SyncCheck -Notify 6>&1 | Out-String
        $output | Should -Match 'behind 0, ahead 1'

        Mock Get-SyncState { [pscustomobject]@{ Upstream = 'origin/main'; UpstreamSha = 'ccc'; Behind = 4; Ahead = 0 } }
        Invoke-SyncCheck 6>$null | Out-Null

        $script:Toasts.Count | Should -Be 0
    }

    It 'counts commits against the real upstream of this checkout' {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'git is not installed'
            return
        }
        Mock Update-Upstream { $true }
        if (-not (Get-GitOutput @('rev-parse', '--abbrev-ref', '@{upstream}'))) {
            Set-ItResult -Skipped -Because 'this checkout has no upstream (CI)'
            return
        }

        $state = Get-SyncState 3>$null

        $state.Behind | Should -BeGreaterOrEqual 0
        $state.UpstreamSha | Should -Match '^[0-9a-f]{40}$'
    }
}

Describe 'setup-sync.ps1' {
    BeforeEach {
        . (Join-Path $WindowsScripts 'setup-sync.ps1')
        $script:Registered = [System.Collections.Generic.List[string]]::new()
        Mock Test-Command { $true }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'HKCU:\' }
        Mock Register-SyncTask { $script:Registered.Add('task') }
        Mock Register-SyncProtocol { $script:Registered.Add('protocol') }
        Mock Get-SyncNowCommand { '"C:\wt.exe" "C:\pwsh.exe" -NoExit -File "dots.ps1" sync' }
    }

    It 'previews the task and the protocol in a dry run' {
        Mock Test-SyncTaskRegistered { $false }
        Mock Test-ProtocolRegistered { $false }

        $output = Invoke-SyncSetup -DryRun 6>&1 | Out-String

        $output | Should -Match 'at logon \+ every 6 hours -> conhost.exe --headless powershell.exe .+sync.ps1" -Check -Notify'
        $output | Should -Match '\+ Register-ScheduledTask -TaskName dots-sync'
        $output | Should -Match 'URL protocol dots-sync:'
        $script:Registered.Count | Should -Be 0
    }

    It 'registers only what is missing' {
        Mock Test-SyncTaskRegistered { $true }
        Mock Test-ProtocolRegistered { $false }

        Invoke-SyncSetup 6>$null

        $script:Registered | Should -Be @('protocol')
    }

    It 'does nothing where Scheduled Tasks do not exist' {
        Mock Test-Command { $false } -ParameterFilter { $Name -eq 'Register-ScheduledTask' }

        $output = Invoke-SyncSetup 3>&1 | Out-String

        $output | Should -Match 'Scheduled Tasks are unavailable'
        $script:Registered.Count | Should -Be 0
    }
}

Describe 'dots.ps1 sync' {
    BeforeEach {
        . (Join-Path $WindowsScripts 'dots.ps1')
    }

    It 'maps changed paths to the steps that read them' {
        $steps = Get-StepsForPath @('scripts/windows/dots.ps1', 'home/dot_gitconfig.tmpl', 'home/.chezmoidata/windows.yaml',
            'home/.chezmoidata/packages.yaml', 'home/.chezmoidata/kde.yaml', 'root/etc/default/grub.tmpl')

        $steps | Should -Be @('packages', 'fonts', 'apply', 'desktop', 'system')
    }

    It 'refuses to pull without a terminal' {
        # dots.ps1 functions read the variable from the calling scope
        Set-Variable -Name NonInteractive -Value $true

        { Invoke-SyncCommand 6>$null } | Should -Throw '*dots sync -Check*'
    }

    It 'refuses to pull over local changes' {
        Mock Get-RepoGit { @(' M home/dot_zshrc') } -ParameterFilter { $Arguments[0] -eq 'status' }

        { Invoke-SyncCommand 6>$null } | Should -Throw '*local changes*'
    }
}
