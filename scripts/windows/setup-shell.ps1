[CmdletBinding()]
param(
    [ValidateSet('pwsh', 'powershell')]
    [string]$Shell = 'pwsh',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$StubMarker = '# Written by dotfiles (scripts/windows/setup-shell.ps1).'
$Stub = @"
$StubMarker Edit ~/.config/powershell/profile.ps1 instead.
`$dotfilesConfigHome = if (`$env:XDG_CONFIG_HOME) { `$env:XDG_CONFIG_HOME } else { Join-Path `$HOME '.config' }
`$dotfilesProfile = Join-Path `$dotfilesConfigHome 'powershell\profile.ps1'
if (Test-Path -LiteralPath `$dotfilesProfile) { . `$dotfilesProfile }
"@

if (-not (Test-Command $Shell)) {
    if ($DryRun) {
        Write-ToolWarning "$Shell is not currently available; printing the planned profile setup only."
    } elseif ($Shell -eq 'pwsh') {
        Stop-Tool 'PowerShell 7 (pwsh) is not available. Run the packages step first (Microsoft.PowerShell is in the winget list).'
    } else {
        Stop-Tool 'Windows PowerShell is not available.'
    }
}

# One config path on both OSes: Neovim, oh-my-posh, git, ... read ~/.config
$configHome = Join-Path $HOME '.config'
$currentConfigHome = [Environment]::GetEnvironmentVariable('XDG_CONFIG_HOME', 'User')
if ($currentConfigHome -eq $configHome) {
    Write-Success "XDG_CONFIG_HOME is $configHome"
} else {
    if ($currentConfigHome) {
        Write-ToolWarning "XDG_CONFIG_HOME is $currentConfigHome; it will be replaced."
    }
    if ($DryRun) {
        Write-Host "+ set user environment variable XDG_CONFIG_HOME=`"$configHome`""
    } else {
        [Environment]::SetEnvironmentVariable('XDG_CONFIG_HOME', $configHome, 'User')
        $env:XDG_CONFIG_HOME = $configHome
        Write-Success "Set XDG_CONFIG_HOME=$configHome"
    }
}

# $PROFILE.CurrentUserAllHosts, resolved through the real Documents folder (OneDrive may move it)
$documents = [Environment]::GetFolderPath('MyDocuments')
$profileDirectory = if ($Shell -eq 'pwsh') {
    Join-Path $documents 'PowerShell'
} else {
    Join-Path $documents 'WindowsPowerShell'
}
$stubFile = Join-Path $profileDirectory 'profile.ps1'

$existing = if (Test-Path -LiteralPath $stubFile) { Get-Content -LiteralPath $stubFile -Raw } else { $null }
if ($null -ne $existing -and $existing.Trim() -eq $Stub.Trim()) {
    Write-Success "Profile stub is up to date: $stubFile"
} else {
    if ($null -ne $existing) {
        $backup = "$stubFile.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
        if ($DryRun) {
            Write-Host "+ Move-Item `"$stubFile`" `"$backup`""
        } else {
            Move-Item -LiteralPath $stubFile -Destination $backup
            Write-ToolWarning "Moved the previous profile to $backup"
        }
    }
    if ($DryRun) {
        Write-Host "+ write the profile stub to `"$stubFile`""
    } else {
        New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null
        Set-Content -LiteralPath $stubFile -Value $Stub -Encoding UTF8
        Write-Success "Wrote profile stub: $stubFile"
    }
}

$hostProfile = Join-Path $profileDirectory 'Microsoft.PowerShell_profile.ps1'
if (Test-Path -LiteralPath $hostProfile) {
    Write-ToolWarning "$hostProfile also loads; move what you keep into ~/.config/powershell/profile.ps1."
}
Write-ToolWarning 'Windows has no login shell; pick PowerShell 7 as the default profile in Windows Terminal.'
