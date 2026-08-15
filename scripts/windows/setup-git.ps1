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
$gitAvailable = Test-Command 'git'
if (-not $gitAvailable -and -not $DryRun) {
    Stop-Tool 'git is not installed.'
}
if (-not $gitAvailable -and $DryRun) {
    Write-ToolWarning 'git is not currently available; printing the planned configuration commands only.'
}

if ($Prompt -and $NonInteractive) {
    Stop-Tool '-Prompt cannot be used with -NonInteractive.'
}

if ([string]::IsNullOrWhiteSpace($Name) -and -not $Prompt) {
    $Name = Get-ChezmoiValue '.git.name'
}
if ([string]::IsNullOrWhiteSpace($Email) -and -not $Prompt) {
    $Email = Get-ChezmoiValue '.git.email'
}

if ([string]::IsNullOrWhiteSpace($Name) -and -not $NonInteractive) {
    $Name = Read-Host 'Git user name'
}
if ([string]::IsNullOrWhiteSpace($Email) -and -not $NonInteractive) {
    $Email = Read-Host 'Git email'
}

$existingName = if ($gitAvailable) { (& git config --global --get user.name 2>$null | Out-String).Trim() } else { '' }
$existingEmail = if ($gitAvailable) { (& git config --global --get user.email 2>$null | Out-String).Trim() } else { '' }

if (-not [string]::IsNullOrWhiteSpace($Name) -and
    ([string]::IsNullOrWhiteSpace($existingName) -or $Force)) {
    Invoke-NativeCommand -FilePath 'git' -ArgumentList @('config', '--global', 'user.name', $Name) -DryRun:$DryRun | Out-Null
} elseif (-not [string]::IsNullOrWhiteSpace($existingName)) {
    Write-Success "Keeping existing Git user.name: $existingName"
} else {
    Write-ToolWarning 'Git user.name is not configured'
}

if (-not [string]::IsNullOrWhiteSpace($Email) -and
    ([string]::IsNullOrWhiteSpace($existingEmail) -or $Force)) {
    Invoke-NativeCommand -FilePath 'git' -ArgumentList @('config', '--global', 'user.email', $Email) -DryRun:$DryRun | Out-Null
} elseif (-not [string]::IsNullOrWhiteSpace($existingEmail)) {
    Write-Success "Keeping existing Git user.email: $existingEmail"
} else {
    Write-ToolWarning 'Git user.email is not configured'
}

$settings = @(
    @('init.defaultBranch', 'main'),
    @('fetch.prune', 'true'),
    @('rerere.enabled', 'true'),
    @('push.autoSetupRemote', 'true'),
    @('core.autocrlf', 'false')
)

foreach ($setting in $settings) {
    Invoke-NativeCommand `
        -FilePath 'git' `
        -ArgumentList @('config', '--global', $setting[0], $setting[1]) `
        -DryRun:$DryRun | Out-Null
}

$existingEditor = if ($gitAvailable) { (& git config --global --get core.editor 2>$null | Out-String).Trim() } else { '' }
if ((Test-Command 'nvim') -and [string]::IsNullOrWhiteSpace($existingEditor)) {
    Invoke-NativeCommand -FilePath 'git' -ArgumentList @('config', '--global', 'core.editor', 'nvim') -DryRun:$DryRun | Out-Null
}

Write-Success 'Git configuration complete'
