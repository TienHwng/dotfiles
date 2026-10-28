[CmdletBinding()]
param(
    [string]$GitHubUser = $env:GITHUB_USERNAME,
    [string]$SshEmail = $env:SSH_KEY_EMAIL,
    [string]$SshKeyPath = $env:SSH_KEY_PATH,
    [string]$SshKeyType = $env:SSH_KEY_TYPE,
    [switch]$Prompt,
    [switch]$Force,
    [switch]$AllowUnencryptedKey,
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
    $GitHubUser = Get-ChezmoiValue '.githubUsername'
}
if ([string]::IsNullOrWhiteSpace($SshEmail) -and -not $Prompt) {
    $SshEmail = Get-ChezmoiValue '.sshEmail'
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
if ($Prompt -or ([string]::IsNullOrWhiteSpace($SshEmail) -and -not $NonInteractive)) {
    if ($DryRun) {
        Write-Host '+ chezmoi init --prompt'
        Write-ToolWarning 'Account prompts were not executed during dry-run.'
    } else {
        Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('init', '--prompt') | Out-Null
        if ([string]::IsNullOrWhiteSpace($GitHubUser)) {
            $GitHubUser = Get-ChezmoiValue '.githubUsername'
        }
        $SshEmail = Get-ChezmoiValue '.sshEmail'
    }
}
if ([string]::IsNullOrWhiteSpace($SshEmail)) {
    if ($DryRun) {
        Write-ToolWarning 'SSH key email is missing; a real run would stop before key generation.'
    } else {
        Stop-Tool 'SSH key email cannot be empty. Run `chezmoi init --prompt` or provide -SshEmail.'
    }
}

if ($SshKeyPath.StartsWith('~/')) {
    $SshKeyPath = Join-Path $HOME ($SshKeyPath.Substring(2) -replace '/', '\\')
}
$SshKeyPath = [System.IO.Path]::GetFullPath($SshKeyPath)
$sshDir = Split-Path -Path $SshKeyPath -Parent

if (-not (Test-Command 'ssh-keygen') -and -not $DryRun) {
    Stop-Tool 'ssh-keygen is required to manage SSH keys.'
}

if ((-not (Test-Path -LiteralPath $SshKeyPath) -or $Force) -and $NonInteractive -and -not $AllowUnencryptedKey) {
    if ($DryRun) {
        Write-ToolWarning 'Non-interactive key generation requires -AllowUnencryptedKey; no key would be created.'
    } else {
        Stop-Tool 'Refusing to create an unencrypted SSH key non-interactively. Pre-create a protected key, use -SkipAccounts, or explicitly pass -AllowUnencryptedKey.'
    }
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
    $sshKeygenArgs = @('-t', $SshKeyType, '-C', $SshEmail, '-f', $SshKeyPath)
    if ($AllowUnencryptedKey) {
        $sshKeygenArgs += @('-N', '')
    }
    Invoke-NativeCommand -FilePath 'ssh-keygen' -ArgumentList $sshKeygenArgs -DryRun:$DryRun | Out-Null
} else {
    Write-Success "Keeping existing SSH key: $SshKeyPath"
}

Write-Success 'SSH host configuration is owned by home/dot_ssh/private_config.tmpl'

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
