[CmdletBinding()]
param(
    [switch]$DryRun
)

# Registers the repository check for this user:
# - the Scheduled Task \dots\dots-sync: at logon (after 2 minutes) and every 6 hours it runs
#   sync.ps1 -Check -Notify, which only shows a toast about new commits;
# - the dots-sync: URL protocol (HKCU), which the toast's "Sync now" button opens: a
#   terminal running dots sync.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$script:TaskName = 'dots-sync'
$script:TaskPath = '\dots\'
$script:ProtocolKey = 'HKCU:\Software\Classes\dots-sync'

# The command "Sync now" runs: PowerShell 7 if present, inside Windows Terminal if present
function Get-SyncNowCommand {
    $dots = Join-Path $PSScriptRoot 'dots.ps1'
    $shell = if (Test-Command 'pwsh.exe') { 'pwsh.exe' } else { 'powershell.exe' }
    $command = "`"$((Get-Command $shell).Source)`" -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$dots`" sync"
    if (Test-Command 'wt.exe') {
        return "`"$((Get-Command 'wt.exe').Source)`" $command"
    }
    return $command
}

# conhost --headless keeps a console window from flashing at every check
function Get-CheckArgument {
    $sync = Join-Path $PSScriptRoot 'sync.ps1'
    return "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$sync`" -Check -Notify"
}

function Test-SyncTaskRegistered {
    $task = Get-ScheduledTask -TaskName $script:TaskName -TaskPath $script:TaskPath -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return $false
    }
    return "$($task.Actions[0].Arguments)" -eq (Get-CheckArgument)
}

function Test-ProtocolRegistered {
    $command = Get-ItemProperty -LiteralPath "$script:ProtocolKey\shell\open\command" -ErrorAction SilentlyContinue
    return $null -ne $command -and "$($command.'(default)')" -eq (Get-SyncNowCommand)
}

function Register-SyncTask {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $trigger.Delay = 'PT2M'
    $trigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 6)).Repetition
    $action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument (Get-CheckArgument)
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $script:TaskName -TaskPath $script:TaskPath -Trigger $trigger -Action $action `
        -Principal $principal -Settings $settings -Description 'dotfiles: check the repository for new commits (notify only)' `
        -Force | Out-Null
}

function Register-SyncProtocol {
    New-Item -Path "$script:ProtocolKey\shell\open\command" -Force | Out-Null
    Set-ItemProperty -LiteralPath $script:ProtocolKey -Name '(default)' -Value 'URL:dots sync'
    Set-ItemProperty -LiteralPath $script:ProtocolKey -Name 'URL Protocol' -Value ''
    Set-ItemProperty -LiteralPath "$script:ProtocolKey\shell\open\command" -Name '(default)' -Value (Get-SyncNowCommand)
}

function Invoke-SyncSetup([switch]$DryRun) {
    if (-not (Test-Command 'Register-ScheduledTask') -or -not (Test-Path -LiteralPath 'HKCU:\')) {
        Write-ToolWarning 'Scheduled Tasks are unavailable on this system; the repository check is not registered.'
        return
    }

    $taskReady = Test-SyncTaskRegistered
    $protocolReady = Test-ProtocolRegistered
    if ($taskReady -and $protocolReady) {
        Write-Success 'The dots-sync task and the dots-sync: protocol are registered'
        return
    }

    if (-not $taskReady) {
        Write-Host "  Scheduled Task $script:TaskPath$($script:TaskName): at logon + every 6 hours -> conhost.exe $(Get-CheckArgument)"
        if ($DryRun) {
            Write-Host "+ Register-ScheduledTask -TaskName $script:TaskName -TaskPath $script:TaskPath"
        } else {
            Register-SyncTask
        }
    }
    if (-not $protocolReady) {
        Write-Host "  URL protocol dots-sync: -> $(Get-SyncNowCommand)"
        if ($DryRun) {
            Write-Host "+ set $script:ProtocolKey\shell\open\command"
        } else {
            Register-SyncProtocol
        }
    }
    if (-not $DryRun) {
        Write-Success 'Registered the repository check: at logon and every 6 hours'
    }
}

# Dot-sourcing (Pester) loads the functions without running the step
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-SyncSetup -DryRun:$DryRun
}
