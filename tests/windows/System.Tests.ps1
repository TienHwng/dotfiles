BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:WindowsScripts = Join-Path $RepoRoot 'scripts\windows'
    $script:Registry = Join-Path $WindowsScripts 'setup-registry.ps1'
    $script:System = Join-Path $WindowsScripts 'setup-system.ps1'
    $script:HasChezmoi = [bool](Get-Command chezmoi -ErrorAction SilentlyContinue)
}

Describe 'windows.yaml' {
    It 'lists the HKCU and dual-boot HKLM values' {
        if (-not $HasChezmoi) {
            Set-ItResult -Skipped -Because 'chezmoi is not installed'
            return
        }
        . $Registry

        $user = Get-RegistryEntry 'user'
        $machine = Get-RegistryEntry 'machine'

        $user.name | Should -Contain 'HideFileExt'
        @($user | Where-Object { $_.path -notmatch '^HKCU:\\' }).Count | Should -Be 0
        @($machine | Where-Object { $_.path -notmatch '^HKLM:\\' }).Count | Should -Be 0
        ($machine | Where-Object name -EQ 'RealTimeIsUniversal').value | Should -Be 1
        ($machine | Where-Object name -EQ 'HiberbootEnabled').value | Should -Be 0
    }
}

Describe 'Invoke-RegistryStep' {
    BeforeEach {
        . $Registry
        $script:Written = [System.Collections.Generic.List[string]]::new()
        $script:ExplorerRestarts = 0
        Mock Test-RegistryAvailable { $true }
        Mock Test-Command { $true }
        Mock Get-RegistryEntry {
            @(
                [pscustomobject]@{ path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; name = 'HideFileExt'; type = 'DWord'; value = 0 },
                [pscustomobject]@{ path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; name = 'AppsUseLightTheme'; type = 'DWord'; value = 0 }
            )
        }
        Mock Set-RegistryEntry { $script:Written.Add("$($Entry.path)|$($Entry.name)=$($Entry.value)") }
        Mock Restart-Explorer { $script:ExplorerRestarts++ }
    }

    It 'reports nothing when the registry already matches' {
        Mock Get-RegistryCurrent { [pscustomobject]@{ Kind = 'DWord'; Value = 0 } }

        $output = Invoke-RegistryStep -Scope user 6>&1 | Out-String

        $output | Should -Match 'already match windows.yaml'
        $script:Written.Count | Should -Be 0
        $script:ExplorerRestarts | Should -Be 0
    }

    It 'lists differing values in a dry run and writes nothing' {
        Mock Get-RegistryCurrent { $null } -ParameterFilter { $Name -eq 'HideFileExt' }
        Mock Get-RegistryCurrent { [pscustomobject]@{ Kind = 'DWord'; Value = 1 } } -ParameterFilter { $Name -eq 'AppsUseLightTheme' }

        $output = Invoke-RegistryStep -Scope user -DryRun 6>&1 | Out-String

        $output | Should -Match 'Explorer\\Advanced HideFileExt: <unset> -> 0 \(DWord\)'
        $output | Should -Match 'AppsUseLightTheme: 1 \(DWord\) -> 0 \(DWord\)'
        $output | Should -Match '\+ set .+Personalize AppsUseLightTheme = 0 \(DWord\)'
        $output | Should -Match '\+ restart Explorer'
        $script:Written.Count | Should -Be 0
        $script:ExplorerRestarts | Should -Be 0
    }

    It 'writes only the differing values and restarts Explorer for Explorer keys' {
        Mock Get-RegistryCurrent { [pscustomobject]@{ Kind = 'DWord'; Value = 0 } } -ParameterFilter { $Name -eq 'AppsUseLightTheme' }
        Mock Get-RegistryCurrent { [pscustomobject]@{ Kind = 'DWord'; Value = 1 } } -ParameterFilter { $Name -eq 'HideFileExt' }

        Invoke-RegistryStep -Scope user 6>$null

        $script:Written | Should -Be @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|HideFileExt=0')
        $script:ExplorerRestarts | Should -Be 1
    }

    It 'rewrites a value stored with another kind' {
        Mock Get-RegistryCurrent { [pscustomobject]@{ Kind = 'QWord'; Value = 0 } }

        Invoke-RegistryStep -Scope user 6>$null

        $script:Written.Count | Should -Be 2
    }

    It 'refuses machine values without admin' {
        Mock Get-RegistryCurrent { $null }
        Mock Test-Elevated { $false }

        { Invoke-RegistryStep -Scope machine 6>$null 3>$null } | Should -Throw '*administrator*dots system*'
        $script:Written.Count | Should -Be 0
    }

    It 'rejects an unsupported value type' {
        Mock Get-RegistryEntry { @([pscustomobject]@{ path = 'HKCU:\Software\Test'; name = 'Blob'; type = 'Binary'; value = 0 }) }

        { Invoke-RegistryStep -Scope user -DryRun 6>$null } | Should -Throw "*Unsupported registry type 'Binary'*"
    }

    It 'does nothing where there is no registry' {
        Mock Test-RegistryAvailable { $false }

        $output = Invoke-RegistryStep -Scope user 3>&1 | Out-String

        $output | Should -Match 'registry is unavailable'
        $script:Written.Count | Should -Be 0
    }
}

Describe 'setup-system.ps1' {
    BeforeEach {
        . $System
        $script:Disabled = 0
        Mock Get-ChezmoiValue { 'bitwarden' } -ParameterFilter { $Expression -eq '.accounts.ssh.agent' }
        Mock Disable-AgentService { $script:Disabled++ }
    }

    It 'previews disabling a running OpenSSH agent service without touching it' {
        Mock Get-AgentService { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }

        $output = Invoke-AgentServiceStep -DryRun 6>&1 | Out-String

        $output | Should -Match 'ssh-agent service: Running, Automatic -> Stopped, Disabled'
        $output | Should -Match '\+ Stop-Service ssh-agent; Set-Service ssh-agent -StartupType Disabled'
        $script:Disabled | Should -Be 0
    }

    It 'disables a running OpenSSH agent service' {
        Mock Get-AgentService { [pscustomobject]@{ Status = 'Running'; StartType = 'Manual' } }

        Invoke-AgentServiceStep 6>$null

        $script:Disabled | Should -Be 1
    }

    It 'leaves a disabled service and file mode alone' {
        Mock Get-AgentService { [pscustomobject]@{ Status = 'Stopped'; StartType = 'Disabled' } }
        Invoke-AgentServiceStep 6>$null

        Mock Get-ChezmoiValue { 'file' } -ParameterFilter { $Expression -eq '.accounts.ssh.agent' }
        Mock Get-AgentService { [pscustomobject]@{ Status = 'Running'; StartType = 'Automatic' } }
        Invoke-AgentServiceStep 6>$null

        $script:Disabled | Should -Be 0
    }

    It 'needs admin unless it is a dry run' {
        Mock Test-Elevated { $false }

        { Invoke-SystemStep 6>$null } | Should -Throw '*administrator*'
    }

    It 'runs as a script in a dry run and changes nothing' {
        $output = & (Get-Process -Id $PID).Path -NoProfile -File $System -DryRun *>&1 | Out-String

        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'System step complete'
    }
}

Describe 'install-nvidia-app.ps1' {
    BeforeEach {
        . (Join-Path $WindowsScripts 'install-nvidia-app.ps1')
        $script:Installs = 0
        $fakeBytes = [Text.Encoding]::ASCII.GetBytes('fake installer')
        $script:App = [pscustomobject]@{
            version = '1.2.3'
            url = 'https://us.download.nvidia.com/nvapp/client/1.2.3/NVIDIA_app_v1.2.3.exe'
            sha256 = (Get-FileHash -InputStream ([IO.MemoryStream]::new($fakeBytes)) -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        Mock Test-Command { $true }
        Mock Test-NvidiaGpu { $true }
        Mock Get-NvidiaAppVersion { $null }
        Mock Get-RepoData { $script:App } -ParameterFilter { $Expression -eq '.windows.nvidia.app' }
        Mock Save-NvidiaInstaller { [IO.File]::WriteAllText($Path, 'fake installer') }
        Mock Test-NvidiaSignature { $true }
        Mock Start-NvidiaInstaller { $script:Installs++; 0 }
    }

    It 'skips machines without an NVIDIA GPU and machines that have the app' {
        Mock Test-NvidiaGpu { $false }
        Invoke-NvidiaAppStep 6>$null

        Mock Test-NvidiaGpu { $true }
        Mock Get-NvidiaAppVersion { '11.0.0.1' }
        $output = Invoke-NvidiaAppStep 6>&1 | Out-String

        $output | Should -Match 'NVIDIA App 11.0.0.1 is installed'
        Should -Invoke Save-NvidiaInstaller -Times 0
        $script:Installs | Should -Be 0
    }

    It 'previews the pinned download in a dry run' {
        $output = Invoke-NvidiaAppStep -DryRun 6>&1 | Out-String

        $output | Should -Match 'NVIDIA App: <not installed> -> 1\.2\.3'
        $output | Should -Match '\+ download https://us\.download\.nvidia\.com/'
        Should -Invoke Save-NvidiaInstaller -Times 0
        $script:Installs | Should -Be 0
    }

    It 'installs when the checksum and the signature match' {
        Invoke-NvidiaAppStep 6>$null

        $script:Installs | Should -Be 1
        Test-Path -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) 'dots-nvidia-app') | Should -BeFalse
    }

    It 'refuses a download whose checksum differs' {
        $script:App.sha256 = '0' * 64

        { Invoke-NvidiaAppStep 6>$null } | Should -Throw '*does not match windows.nvidia.app.sha256*'
        $script:Installs | Should -Be 0
    }

    It 'refuses a download without a valid NVIDIA signature' {
        Mock Test-NvidiaSignature { $false }

        { Invoke-NvidiaAppStep 6>$null } | Should -Throw '*no valid NVIDIA Corporation signature*'
        $script:Installs | Should -Be 0
    }
}

Describe 'windows.yaml NVIDIA App pin' {
    It 'pins an NVIDIA download URL, its version and a SHA-256' {
        if (-not $HasChezmoi) {
            Set-ItResult -Skipped -Because 'chezmoi is not installed'
            return
        }
        . (Join-Path $WindowsScripts 'install-nvidia-app.ps1')

        $app = Get-RepoData '.windows.nvidia.app'

        $app.url | Should -Match '^https://us\.download\.nvidia\.com/'
        $app.url | Should -Match ([regex]::Escape($app.version))
        $app.sha256 | Should -Match '^[0-9a-f]{64}$'
    }
}
