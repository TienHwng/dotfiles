[CmdletBinding()]
param(
    [switch]$DryRun,
    # Set by dots when it opens this script in a new administrator window
    [switch]$PauseOnExit
)

# The Windows system step (L5, admin): machine registry values from
# windows.registry.machine (UTC hardware clock, Fast Startup off), then the OpenSSH
# Authentication Agent service disabled so the Bitwarden SSH agent owns the pipe.
# With -DryRun it only reads and prints.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

function Get-AgentService {
    if (-not (Test-Command 'Get-Service')) {
        return $null
    }
    return Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
}

function Disable-AgentService {
    Stop-Service -Name 'ssh-agent' -Force
    Set-Service -Name 'ssh-agent' -StartupType Disabled
}

# The Windows agent and Bitwarden's both listen on \\.\pipe\openssh-ssh-agent
function Invoke-AgentServiceStep([switch]$DryRun) {
    if ((Get-ChezmoiValue '.accounts.ssh.agent' 'bitwarden') -ne 'bitwarden') {
        Write-Success 'SSH keys are files on disk (.accounts.ssh.agent = file); the OpenSSH agent service is left alone'
        return
    }
    $service = Get-AgentService
    if ($null -eq $service) {
        Write-Success 'The OpenSSH Authentication Agent service is not installed'
        return
    }
    if ("$($service.StartType)" -eq 'Disabled' -and "$($service.Status)" -eq 'Stopped') {
        Write-Success 'The OpenSSH Authentication Agent service is already disabled'
        return
    }

    Write-Host "  ssh-agent service: $($service.Status), $($service.StartType) -> Stopped, Disabled"
    if ($DryRun) {
        Write-Host '+ Stop-Service ssh-agent; Set-Service ssh-agent -StartupType Disabled'
        return
    }
    Disable-AgentService
    Write-Success 'Disabled the OpenSSH Authentication Agent service'
}

function Invoke-SystemStep([switch]$DryRun) {
    if (-not $DryRun -and -not (Test-Elevated)) {
        Stop-Tool 'The system step needs an administrator PowerShell; run: dots system'
    }

    Write-Step 'Machine registry values (windows.registry.machine)'
    & (Join-Path $PSScriptRoot 'setup-registry.ps1') -Scope machine -DryRun:$DryRun

    Write-Step 'OpenSSH Authentication Agent service'
    Invoke-AgentServiceStep -DryRun:$DryRun

    Write-Success 'System step complete'
}

# Dot-sourcing (Pester) loads the functions without running the step
if ($MyInvocation.InvocationName -ne '.') {
    $failed = $false
    try {
        Invoke-SystemStep -DryRun:$DryRun
    } catch {
        Write-Failure $_.Exception.Message
        $failed = $true
    }
    if ($PauseOnExit) {
        Read-Host 'Press Enter to close this window' | Out-Null
    }
    if ($failed) {
        exit 1
    }
    exit 0
}
