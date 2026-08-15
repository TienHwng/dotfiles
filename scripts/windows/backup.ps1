[CmdletBinding()]
param(
    [string]$Destination = $(
        if ($env:DOTFILES_BACKUP_DIR) { $env:DOTFILES_BACKUP_DIR }
        else { Join-Path $HOME 'dotfiles-backups' }
    ),
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

if (-not (Test-Command 'chezmoi')) {
    Stop-Tool 'chezmoi is required.'
}
if (-not (Test-Command 'tar.exe')) {
    Stop-Tool 'tar.exe is required for the backup archive.'
}

$sourcePath = (& chezmoi source-path).Trim()
$configFile = (& chezmoi execute-template '{{ .chezmoi.configFile }}').Trim()
$repoDirectory = [System.IO.DirectoryInfo](Resolve-Path -LiteralPath $sourcePath)

while ($null -ne $repoDirectory -and
       -not (Test-Path -LiteralPath (Join-Path $repoDirectory.FullName '.git'))) {
    $repoDirectory = $repoDirectory.Parent
}
if ($null -eq $repoDirectory) {
    $repoDirectory = [System.IO.DirectoryInfo](Resolve-Path -LiteralPath $sourcePath)
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDirectory = Join-Path $Destination "dotfiles-$timestamp"
$archive = Join-Path $backupDirectory 'repository.tar.gz'
$parent = $repoDirectory.Parent.FullName
$name = $repoDirectory.Name

if ($DryRun) {
    Write-Host "+ New-Item -ItemType Directory -Force -Path `"$backupDirectory`""
    Write-Host "+ tar.exe -czf `"$archive`" -C `"$parent`" `"$name`""
    if (Test-Path -LiteralPath $configFile) {
        Write-Host "+ Copy-Item `"$configFile`" `"$backupDirectory`""
    }
    return
}

New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
Write-Step 'Backing up the dotfiles repository...'
Invoke-NativeCommand -FilePath 'tar.exe' -ArgumentList @('-czf', $archive, '-C', $parent, $name) | Out-Null

if (Test-Path -LiteralPath $configFile) {
    Write-Step 'Backing up machine-specific chezmoi configuration...'
    Copy-Item -LiteralPath $configFile -Destination $backupDirectory -Force
}

if ((Test-Command 'git') -and (Test-Path -LiteralPath (Join-Path $repoDirectory.FullName '.git'))) {
    (& git -C $repoDirectory.FullName status --short | Out-String) |
        Set-Content -LiteralPath (Join-Path $backupDirectory 'git-status.txt') -Encoding UTF8
    (& git -C $repoDirectory.FullName log -1 --oneline | Out-String) |
        Set-Content -LiteralPath (Join-Path $backupDirectory 'git-head.txt') -Encoding UTF8
}

@"
Created: $(Get-Date -Format o)
Source state: $sourcePath
Repository: $($repoDirectory.FullName)
Chezmoi config: $configFile

Extract repository.tar.gz into a temporary directory first. Review its
contents and copy only the files you need; do not overwrite an active source
state blindly.
"@ | Set-Content -LiteralPath (Join-Path $backupDirectory 'RESTORE.txt') -Encoding UTF8

Write-Success "Backup created at $backupDirectory"
