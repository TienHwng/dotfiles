[CmdletBinding()]
param(
    [ValidateSet('pwsh', 'powershell')]
    [string]$Shell = 'pwsh',
    [switch]$CreateProfile,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

if (-not (Test-Command $Shell)) {
    if ($DryRun) {
        Write-ToolWarning "$Shell is not currently available; printing the planned profile setup only."
    } elseif ($Shell -eq 'pwsh') {
        Stop-Tool 'PowerShell 7 (pwsh) is not available. Add Microsoft.PowerShell to the winget list in home/.chezmoidata/packages.yaml.'
    } else {
        Stop-Tool 'Windows PowerShell is not available.'
    }
}

$documents = [Environment]::GetFolderPath('MyDocuments')
$profileDirectory = if ($Shell -eq 'pwsh') {
    Join-Path $documents 'PowerShell'
} else {
    Join-Path $documents 'WindowsPowerShell'
}
$profileFile = Join-Path $profileDirectory 'Microsoft.PowerShell_profile.ps1'

if ($DryRun) {
    Write-Host "+ New-Item -ItemType Directory -Force -Path `"$profileDirectory`""
    if ($CreateProfile -and -not (Test-Path -LiteralPath $profileFile)) {
        Write-Host "+ New-Item -ItemType File -Path `"$profileFile`""
    }
    return
}

New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null
if ($CreateProfile -and -not (Test-Path -LiteralPath $profileFile)) {
    New-Item -ItemType File -Path $profileFile | Out-Null
}

Write-Success "$Shell is available"
Write-Success "PowerShell profile path: $profileFile"
Write-ToolWarning 'Windows does not use chsh. The default Windows Terminal profile should be selected in Windows Terminal settings.'
