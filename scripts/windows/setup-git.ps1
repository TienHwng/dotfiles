[CmdletBinding()]
param(
    [string]$Name = $env:GIT_NAME,
    [string]$Email = $env:GIT_EMAIL,
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
if (-not (Test-Command 'git') -and -not $DryRun) {
    Stop-Tool 'git is not installed.'
}
if (-not (Test-Command 'git') -and $DryRun) {
    Write-ToolWarning 'git is not currently available; printing the planned configuration commands only.'
}

if ($Prompt -and $NonInteractive) {
    Stop-Tool '-Prompt cannot be used with -NonInteractive.'
}

$configuredName = Get-ChezmoiValue '.gitName'
$configuredEmail = Get-ChezmoiValue '.gitEmail'

if ($Prompt -or (([string]::IsNullOrWhiteSpace($configuredName) -or
    [string]::IsNullOrWhiteSpace($configuredEmail)) -and -not $NonInteractive)) {
    if ($DryRun) {
        Write-Host '+ chezmoi init --prompt'
        Write-ToolWarning 'Git identity prompts were not executed during dry-run.'
    } else {
        Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('init', '--prompt') | Out-Null
        $configuredName = Get-ChezmoiValue '.gitName'
        $configuredEmail = Get-ChezmoiValue '.gitEmail'
    }
}

if ((-not [string]::IsNullOrWhiteSpace($Name) -and $Name -ne $configuredName) -or
    (-not [string]::IsNullOrWhiteSpace($Email) -and $Email -ne $configuredEmail) -or $Force) {
    Write-ToolWarning 'Direct Git writes are disabled. Re-run `chezmoi init --prompt` to change machine data.'
}

if ([string]::IsNullOrWhiteSpace($configuredName) -or [string]::IsNullOrWhiteSpace($configuredEmail)) {
    if ($DryRun) {
        Write-ToolWarning 'Git identity is incomplete; a real non-interactive bootstrap would stop before apply.'
    } else {
        Stop-Tool 'Git identity is incomplete. Run `chezmoi init --prompt` or populate data.gitName and data.gitEmail.'
    }
}

Write-Success 'Git configuration is owned by home/dot_gitconfig.tmpl'
