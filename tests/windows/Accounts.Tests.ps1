BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Accounts = Join-Path $RepoRoot 'scripts\windows\setup-accounts.ps1'

    # Global functions shadow the real commands for the script under test; their bodies
    # are built from literals because global functions cannot see this file's variables.
    # $AgentExit: ssh-add -L exit code (0 lists one key, 1 no keys, 2 no agent).
    function script:Set-AgentMock([int]$AgentExit, [string]$SshReply) {
        $script:UploadLog = Join-Path $TestDrive 'gh-ssh-key-add.log'
        $reply = $SshReply -replace "'", "''"
        $log = $script:UploadLog -replace "'", "''"

        $keyLine = if ($AgentExit -eq 0) { "'ssh-ed25519 AAAATESTKEY bitwarden'" } else { '' }
        Set-Item -Path function:global:ssh-add -Value ([scriptblock]::Create("`$global:LASTEXITCODE = $AgentExit; $keyLine"))
        Set-Item -Path function:global:ssh -Value ([scriptblock]::Create("`$global:LASTEXITCODE = 1; '$reply'"))
        Set-Item -Path function:global:gh -Value ([scriptblock]::Create(
                "if (`$args[0] -eq 'ssh-key') { Add-Content -LiteralPath '$log' -Value `"`$args`" }; `$global:LASTEXITCODE = 0"))
        # The Windows OpenSSH Authentication Agent is off
        Set-Item -Path function:global:Get-Service -Value { $null }
    }
}

Describe 'setup-accounts.ps1 in Bitwarden mode' {
    AfterEach {
        foreach ($name in @('ssh-add', 'ssh', 'gh', 'Get-Service')) {
            Remove-Item -LiteralPath "function:global:$name" -ErrorAction SilentlyContinue
        }
    }

    It 'reports an unreachable agent in a dry run without failing' {
        Set-AgentMock -AgentExit 2 -SshReply ''

        $output = & $Accounts -SshAgent bitwarden -DryRun -NonInteractive *>&1 | Out-String

        $output | Should -Match 'No SSH agent answers'
        $output | Should -Match 'gh auth login --hostname github.com --git-protocol https --web'
    }

    It 'fails when the agent is not reachable and prompts are off' {
        Set-AgentMock -AgentExit 2 -SshReply ''

        { & $Accounts -SshAgent bitwarden -NonInteractive *> $null } | Should -Throw '*not reachable*'
    }

    It 'fails when the agent holds no keys and prompts are off' {
        Set-AgentMock -AgentExit 1 -SshReply ''

        { & $Accounts -SshAgent bitwarden -NonInteractive *> $null } | Should -Throw '*holds no keys*'
    }

    It 'passes when GitHub accepts the agent key' {
        Set-AgentMock -AgentExit 0 -SshReply 'Hi tester! You have successfully authenticated, but GitHub does not provide shell access.'

        $output = & $Accounts -SshAgent bitwarden -NonInteractive *>&1 | Out-String

        $output | Should -Match 'holds 1 key'
        $output | Should -Match 'GitHub accepts the SSH key'
        Test-Path -LiteralPath $script:UploadLog | Should -BeFalse
    }

    It 'prints an unknown key instead of uploading it when prompts are off' {
        Set-AgentMock -AgentExit 0 -SshReply 'git@github.com: Permission denied (publickey).'

        $output = & $Accounts -SshAgent bitwarden -NonInteractive *>&1 | Out-String

        $output | Should -Match 'ssh-ed25519 AAAATESTKEY bitwarden'
        Test-Path -LiteralPath $script:UploadLog | Should -BeFalse
    }

    It 'uploads an unknown key with gh after yes' {
        Set-AgentMock -AgentExit 0 -SshReply 'git@github.com: Permission denied (publickey).'
        Set-Item -Path function:global:Read-Host -Value { 'y' }

        try {
            & $Accounts -SshAgent bitwarden *> $null
        } finally {
            Remove-Item -LiteralPath function:global:Read-Host
        }

        Get-Content -LiteralPath $script:UploadLog | Should -Match '^ssh-key add .+ --title .+\(Bitwarden\)$'
    }

    It 'rejects unknown agent modes' {
        { & $Accounts -SshAgent gnome -DryRun *> $null } | Should -Throw
    }
}
