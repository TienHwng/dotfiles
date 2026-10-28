[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'The step functions below read the script parameters.')]
[CmdletBinding()]
param(
    [ValidateSet('', 'bitwarden', 'file')]
    [string]$SshAgent = $env:SSH_AGENT,
    [string]$SshEmail = $env:SSH_KEY_EMAIL,
    [string]$SshKeyPath = $env:SSH_KEY_PATH,
    [string]$SshKeyType = $env:SSH_KEY_TYPE,
    [switch]$Prompt,
    [switch]$Force,
    [switch]$AllowUnencryptedKey,
    [switch]$NonInteractive,
    [switch]$DryRun
)

# Logs in to GitHub with gh (HTTPS; the git template already makes gh the credential
# helper), then checks the SSH key:
#   bitwarden  the Bitwarden desktop SSH agent holds a key that GitHub accepts
#   file       a passphrase-protected key file exists (created if missing)
# The mode comes from .accounts.ssh.agent in chezmoi data.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

if ($env:NON_INTERACTIVE -eq '1') {
    $NonInteractive = $true
}

if ($Prompt -and $NonInteractive) {
    Stop-Tool '-Prompt cannot be used with -NonInteractive.'
}

if ([string]::IsNullOrWhiteSpace($SshAgent)) {
    $SshAgent = Get-ChezmoiValue '.accounts.ssh.agent' 'bitwarden'
}
if ($SshAgent -notin @('bitwarden', 'file')) {
    Stop-Tool "Unknown SSH agent mode: $SshAgent (expected bitwarden or file)"
}

# GitHub over HTTPS through gh. The git template renders gh as the credential
# helper, so gh auth login does not offer to edit ~/.gitconfig (never run gh auth setup-git).
function Invoke-GitHubLogin {
    # Windows PowerShell 5.1 turns native stderr into a terminating error under 'Stop'
    $ErrorActionPreference = 'Continue'

    if (-not (Test-Command 'gh')) {
        Write-ToolWarning 'GitHub CLI (gh) not found; install it with the packages step.'
        return
    }
    $loginArguments = @('auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web')
    if ($DryRun) {
        Write-Step 'Would check gh auth status and, if logged out, run:'
        Write-Host (Format-NativeCommand 'gh' $loginArguments)
        return
    }
    & gh auth status --hostname github.com *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Success 'GitHub CLI is logged in'
        return
    }
    if ($NonInteractive) {
        Write-ToolWarning 'GitHub CLI is not logged in. Run: gh auth login --hostname github.com --git-protocol https --web'
        return
    }

    $helpers = "$(& git config --get-all 'credential.https://github.com.helper' 2>$null)"
    if ($helpers -notmatch 'auth git-credential') {
        Write-ToolWarning "If gh asks 'Authenticate Git with your GitHub credentials?', answer No: home/dot_gitconfig.tmpl owns ~/.gitconfig. Run the apply step first to avoid the question."
    }
    Invoke-NativeCommand -FilePath 'gh' -ArgumentList $loginArguments | Out-Null
}

function Write-BitwardenAgentHelp {
    Write-Step 'Set up the Bitwarden SSH agent:'
    @(
        'Open Bitwarden desktop and unlock the vault',
        'Settings > Enable SSH agent',
        'Create the key in the vault: New > SSH key (generate ed25519), then save'
    ) | ForEach-Object { Write-Host "  $_" }
}

# Public keys from the agent; $null when no agent answers on the pipe
function Get-AgentKey {
    $ErrorActionPreference = 'Continue'
    # Windows OpenSSH (on PATH; Git for Windows only adds git\cmd) talks to Bitwarden's agent pipe
    $output = @(& ssh-add -L 2>$null)
    # ssh-add -L: 0 = keys listed, 1 = agent has no identities, 2 = no agent
    switch ($LASTEXITCODE) {
        0 { return , @($output | Where-Object { "$_".Trim() }) }
        1 { return , @() }
        default { return $null }
    }
}

# Waits for the person to fix the agent (interactive) or fails (non-interactive)
function Wait-AgentFix([string]$Message) {
    if ($NonInteractive -or -not (Confirm-Action "$Message Retry now?" -DefaultYes $true)) {
        Stop-Tool $Message
    }
}

function Test-GitHubSsh {
    $ErrorActionPreference = 'Continue'
    $output = & ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | Out-String
    return $output -match 'successfully authenticated'
}

function Add-GitHubSshKey([string]$PublicKey) {
    if (-not (Test-Command 'gh') -or $NonInteractive -or
        -not (Confirm-Action 'Add this key to your GitHub account with gh?' -DefaultYes $true)) {
        Write-ToolWarning 'Add this public key at https://github.com/settings/ssh/new:'
        Write-Host $PublicKey
        return
    }

    $keyFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -LiteralPath $keyFile -Value $PublicKey -Encoding ascii
        $code = Invoke-NativeCommand -FilePath 'gh' -ArgumentList @('ssh-key', 'add', $keyFile, '--title', "$env:COMPUTERNAME (Bitwarden)") -IgnoreExitCode
        if ($code -ne 0) {
            Write-ToolWarning 'gh needs the admin:public_key scope: gh auth refresh -h github.com -s admin:public_key'
        }
    } finally {
        Remove-Item -LiteralPath $keyFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-BitwardenSsh {
    # The Windows OpenSSH Authentication Agent owns the same pipe; it must be off
    $windowsAgent = Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
    $adminHint = 'In an administrator PowerShell: Stop-Service ssh-agent; Set-Service ssh-agent -StartupType Disabled'

    if ($DryRun) {
        if ($windowsAgent -and $windowsAgent.Status -eq 'Running') {
            Write-ToolWarning "The Windows OpenSSH Authentication Agent is running and blocks Bitwarden's agent. $adminHint"
        }
        $keys = Get-AgentKey
        if ($null -eq $keys) {
            Write-ToolWarning 'No SSH agent answers on the OpenSSH pipe; a real run would stop here.'
        } else {
            Write-Success "The SSH agent holds $($keys.Count) key(s)"
        }
        Write-Step 'Would check that GitHub accepts the key: ssh -T git@github.com'
        return
    }

    while ($true) {
        $windowsAgent = Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
        if (-not ($windowsAgent -and $windowsAgent.Status -eq 'Running')) {
            break
        }
        Write-ToolWarning $adminHint
        Wait-AgentFix "The Windows OpenSSH Authentication Agent is running and blocks Bitwarden's agent."
    }
    while ($null -eq ($keys = Get-AgentKey)) {
        Write-BitwardenAgentHelp
        Wait-AgentFix 'The Bitwarden SSH agent is not reachable.'
    }
    while ($keys.Count -eq 0) {
        Write-BitwardenAgentHelp
        Wait-AgentFix 'The Bitwarden SSH agent holds no keys (is the vault unlocked?).'
        $keys = Get-AgentKey
        if ($null -eq $keys) {
            $keys = @()
        }
    }
    Write-Success "Bitwarden SSH agent holds $($keys.Count) key(s)"

    if (Test-GitHubSsh) {
        Write-Success 'GitHub accepts the SSH key (ssh -T git@github.com)'
        return
    }
    if ($keys.Count -eq 1) {
        Write-ToolWarning 'GitHub does not know this key yet.'
        Add-GitHubSshKey $keys[0]
    } else {
        Write-ToolWarning 'GitHub accepts none of the agent keys. Add one at https://github.com/settings/ssh/new:'
        $keys | ForEach-Object { Write-Host $_ }
    }
}

# Headless machines without Bitwarden: a passphrase-protected key file
function Invoke-KeyFileSetup {
    $ErrorActionPreference = 'Continue'
    $email = $SshEmail
    $keyPath = $SshKeyPath
    $keyType = $SshKeyType

    if ([string]::IsNullOrWhiteSpace($email) -and -not $Prompt) {
        $email = Get-ChezmoiValue '.sshEmail'
    }
    if ([string]::IsNullOrWhiteSpace($keyPath)) {
        $keyPath = Get-ChezmoiValue '.accounts.ssh.keyPathWindows' '~/.ssh/id_ed25519'
    }
    if ([string]::IsNullOrWhiteSpace($keyType)) {
        $keyType = Get-ChezmoiValue '.accounts.ssh.keyType' 'ed25519'
    }
    if ([string]::IsNullOrWhiteSpace($email) -and (Test-Command 'git')) {
        $email = "$(& git config --global --get user.email 2>$null)".Trim()
    }
    $ErrorActionPreference = 'Stop'

    if ($Prompt -or ([string]::IsNullOrWhiteSpace($email) -and -not $NonInteractive)) {
        if ($DryRun) {
            Write-Host '+ chezmoi init --prompt'
            Write-ToolWarning 'Account prompts were not executed during dry-run.'
        } else {
            Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('init', '--prompt') | Out-Null
            $email = Get-ChezmoiValue '.sshEmail'
        }
    }
    if ([string]::IsNullOrWhiteSpace($email)) {
        if ($DryRun) {
            Write-ToolWarning 'SSH key email is missing; a real run would stop before key generation.'
        } else {
            Stop-Tool 'SSH key email cannot be empty. Run `chezmoi init --prompt` or provide -SshEmail.'
        }
    }

    if ($keyPath.StartsWith('~/')) {
        $keyPath = Join-Path $HOME ($keyPath.Substring(2) -replace '/', '\')
    }
    $keyPath = [System.IO.Path]::GetFullPath($keyPath)
    $sshDir = Split-Path -Path $keyPath -Parent

    if (-not (Test-Command 'ssh-keygen') -and -not $DryRun) {
        Stop-Tool 'ssh-keygen is required to manage SSH keys.'
    }

    if ((-not (Test-Path -LiteralPath $keyPath) -or $Force) -and $NonInteractive -and -not $AllowUnencryptedKey) {
        if ($DryRun) {
            Write-ToolWarning 'Non-interactive key generation requires -AllowUnencryptedKey; no key would be created.'
        } else {
            Stop-Tool 'Refusing to create an unencrypted SSH key non-interactively. Pre-create a protected key, use -Skip accounts, or explicitly pass -AllowUnencryptedKey.'
        }
    }

    if ($DryRun) {
        Write-Host "+ New-Item -ItemType Directory -Force -Path $sshDir"
    } else {
        New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    }

    if ((Test-Path -LiteralPath $keyPath) -and $Force) {
        $backup = "$keyPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-ToolWarning "Existing SSH key found, backing up to $backup"
        if ($DryRun) {
            Write-Host "+ Move-Item -LiteralPath $keyPath -Destination $backup"
        } else {
            Move-Item -LiteralPath $keyPath -Destination $backup -Force
            if (Test-Path -LiteralPath "$keyPath.pub") {
                Move-Item -LiteralPath "$keyPath.pub" -Destination "$backup.pub" -Force
            }
        }
    }

    if (-not (Test-Path -LiteralPath $keyPath)) {
        Write-Step "Generating SSH key: $keyPath"
        $sshKeygenArgs = @('-t', $keyType, '-C', $email, '-f', $keyPath)
        if ($AllowUnencryptedKey) {
            $sshKeygenArgs += @('-N', '')
        }
        Invoke-NativeCommand -FilePath 'ssh-keygen' -ArgumentList $sshKeygenArgs -DryRun:$DryRun | Out-Null
    } else {
        Write-Success "Keeping existing SSH key: $keyPath"
    }

    if ((Test-Path -LiteralPath "$keyPath.pub") -and -not $DryRun) {
        Write-Step 'Add this SSH public key to GitHub > Settings > SSH and GPG keys:'
        Get-Content -LiteralPath "$keyPath.pub"
    }
}

# Templates do not read Bitwarden secrets yet; report the CLI state for when they do
function Write-BitwardenCliStatus {
    $ErrorActionPreference = 'Continue'
    if (-not (Test-Command 'bw')) {
        Write-ToolWarning 'Bitwarden CLI (bw) not found; templates cannot read Bitwarden secrets on this machine.'
        return
    }
    $status = ''
    $statusJson = "$(& bw status 2>$null)"
    if ($statusJson -match '"status":"([a-z]+)"') {
        $status = $Matches[1]
    }
    switch ($status) {
        { $_ -in @('locked', 'unlocked') } { Write-Success "Bitwarden CLI is logged in ($status)" }
        'unauthenticated' { Write-ToolWarning 'Bitwarden CLI is not logged in. Run bw login before templates use Bitwarden secrets.' }
        default { Write-ToolWarning 'Could not read the Bitwarden CLI status (bw status).' }
    }
}

Invoke-GitHubLogin
if ($SshAgent -eq 'bitwarden') {
    Invoke-BitwardenSsh
} else {
    Invoke-KeyFileSetup
}
Write-BitwardenCliStatus

Write-Success 'SSH host configuration is owned by home/dot_ssh/private_config.tmpl'
Write-Success 'Account onboarding complete'
