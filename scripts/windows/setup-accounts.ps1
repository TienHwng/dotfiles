[CmdletBinding()]
param(
    [string]$GitHubUser = $env:GITHUB_USERNAME,
    [string]$SshEmail = $env:SSH_KEY_EMAIL,
    [string]$SshKeyPath = $env:SSH_KEY_PATH,
    [string]$SshKeyType = $env:SSH_KEY_TYPE,
    [switch]$Prompt,
    [switch]$Force,
    [switch]$NonInteractive,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

if ($env:NON_INTERACTIVE -eq '1') {
    $NonInteractive = $true
}

if ($Prompt -and $NonInteractive) {
    Stop-Tool '-Prompt cannot be used with -NonInteractive.'
}

if ([string]::IsNullOrWhiteSpace($GitHubUser) -and -not $Prompt) {
    $GitHubUser = Get-ChezmoiValue '.accounts.github.username'
}
if ([string]::IsNullOrWhiteSpace($SshEmail) -and -not $Prompt) {
    $SshEmail = Get-ChezmoiValue '.accounts.ssh.email'
}
if ([string]::IsNullOrWhiteSpace($SshKeyPath)) {
    $SshKeyPath = Get-ChezmoiValue '.accounts.ssh.keyPathWindows' '~/.ssh/id_ed25519'
}
if ([string]::IsNullOrWhiteSpace($SshKeyType)) {
    $SshKeyType = Get-ChezmoiValue '.accounts.ssh.keyType' 'ed25519'
}
if ([string]::IsNullOrWhiteSpace($SshEmail) -and (Test-Command 'git')) {
    $SshEmail = (& git config --global --get user.email 2>$null | Out-String).Trim()
}
if ($Prompt -and -not $NonInteractive) {
    $GitHubUser = Read-Host 'GitHub username (optional)'
}
if ([string]::IsNullOrWhiteSpace($SshEmail) -and -not $NonInteractive) {
    $SshEmail = Read-Host 'SSH key email'
}
if ([string]::IsNullOrWhiteSpace($SshEmail)) {
    Stop-Tool 'SSH key email cannot be empty. Provide -SshEmail or set accounts.ssh.email.'
}

if ($SshKeyPath.StartsWith('~/')) {
    $SshKeyPath = Join-Path $HOME ($SshKeyPath.Substring(2) -replace '/', '\\')
}
$SshKeyPath = [System.IO.Path]::GetFullPath($SshKeyPath)
$sshDir = Split-Path -Path $SshKeyPath -Parent

if (-not (Test-Command 'ssh-keygen') -and -not $DryRun) {
    Stop-Tool 'ssh-keygen is required to manage SSH keys.'
}

if ($DryRun) {
    Write-Host "+ New-Item -ItemType Directory -Force -Path $sshDir"
    Write-Host "+ chmod 700 $sshDir"
} else {
    New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
}

if ((Test-Path -LiteralPath $SshKeyPath) -and $Force) {
    $stamp = Get-Date -Format 'yyyyMMddHHmmss'
    $backup = "$SshKeyPath.bak.$stamp"
    Write-ToolWarning "Existing SSH key found, backing up to $backup"
    if ($DryRun) {
        Write-Host "+ Move-Item -LiteralPath $SshKeyPath -Destination $backup"
        if (Test-Path -LiteralPath "$SshKeyPath.pub") {
            Write-Host "+ Move-Item -LiteralPath $SshKeyPath.pub -Destination $backup.pub"
        }
    } else {
        Move-Item -LiteralPath $SshKeyPath -Destination $backup -Force
        if (Test-Path -LiteralPath "$SshKeyPath.pub") {
            Move-Item -LiteralPath "$SshKeyPath.pub" -Destination "$backup.pub" -Force
        }
    }
}

if (-not (Test-Path -LiteralPath $SshKeyPath)) {
    Write-Step "Generating SSH key: $SshKeyPath"
    Invoke-NativeCommand -FilePath 'ssh-keygen' -ArgumentList @('-t', $SshKeyType, '-C', $SshEmail, '-f', $SshKeyPath, '-N', '') -DryRun:$DryRun | Out-Null
} else {
    Write-Success "Keeping existing SSH key: $SshKeyPath"
}

$sshConfigPath = Join-Path $HOME '.ssh\config'
$startMarker = '# BEGIN DOTFILES GITHUB'
$endMarker = '# END DOTFILES GITHUB'
$managedBlock = @(
    $startMarker,
    'Host github.com',
    '  HostName github.com',
    '  User git',
    "  IdentityFile $SshKeyPath",
    '  IdentitiesOnly yes',
    '  AddKeysToAgent yes',
    $endMarker
)

if ($DryRun) {
    Write-Step "Would ensure GitHub SSH host block in $sshConfigPath"
} else {
    $existing = @()
    if (Test-Path -LiteralPath $sshConfigPath) {
        $existing = Get-Content -LiteralPath $sshConfigPath
    }

    $output = [System.Collections.Generic.List[string]]::new()
    $inBlock = $false
    foreach ($line in $existing) {
        if ($line -eq $startMarker) {
            $inBlock = $true
            continue
        }
        if ($line -eq $endMarker) {
            $inBlock = $false
            continue
        }
        if (-not $inBlock) {
            $output.Add($line)
        }
    }

    if ($output.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
        $output.Add('')
    }
    foreach ($line in $managedBlock) {
        $output.Add($line)
    }

    $output | Set-Content -LiteralPath $sshConfigPath
    Write-Success "SSH config updated: $sshConfigPath"
}

if ((Test-Command 'git') -and -not [string]::IsNullOrWhiteSpace($GitHubUser)) {
    Invoke-NativeCommand -FilePath 'git' -ArgumentList @('config', '--global', 'github.user', $GitHubUser) -DryRun:$DryRun | Out-Null
}

if (Test-Command 'gh') {
    $authOk = $true
    try {
        Invoke-NativeCommand -FilePath 'gh' -ArgumentList @('auth', 'status') -DryRun:$DryRun | Out-Null
    } catch {
        $authOk = $false
    }

    if ($authOk) {
        Write-Success 'GitHub CLI authentication already configured'
    } else {
        Write-ToolWarning 'GitHub CLI is installed but not authenticated. Run: gh auth login --git-protocol ssh --web'
    }
} else {
    Write-ToolWarning 'GitHub CLI (gh) not found; skipping GitHub authentication check'
}

if ((Test-Path -LiteralPath "$SshKeyPath.pub") -and -not $DryRun) {
    Write-Step 'Add this SSH public key to GitHub > Settings > SSH and GPG keys:'
    Get-Content -LiteralPath "$SshKeyPath.pub"
}

Write-Success 'Account onboarding complete'
