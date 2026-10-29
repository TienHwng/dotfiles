[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Check', Justification = 'Checking is all this script does; -Check mirrors dots sync -Check.')]
[CmdletBinding()]
param(
    [switch]$Check,
    # Show a toast with a "Sync now" button when there are new commits (once per upstream commit)
    [switch]$Notify
)

# Fetches the repository and prints how many commits this machine is behind its upstream.
# Never pulls or applies anything. The dots-sync Scheduled Task runs it with -Check -Notify;
# "Sync now" opens the dots-sync: protocol that setup-sync.ps1 registers.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

# git output as one trimmed string; $null when git fails
function Get-GitOutput([string[]]$Arguments) {
    # Windows PowerShell 5.1 turns native stderr into a terminating error under 'Stop'
    $ErrorActionPreference = 'Continue'
    $output = & git -C (Get-RepoRoot) @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return ("$output").Trim()
}

function Update-Upstream {
    $previous = $env:GIT_TERMINAL_PROMPT
    # Never prompt: the Scheduled Task runs without a console
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        return $null -ne (Get-GitOutput @('fetch', '--quiet'))
    } finally {
        $env:GIT_TERMINAL_PROMPT = $previous
    }
}

function Get-SyncState {
    $upstream = Get-GitOutput @('rev-parse', '--abbrev-ref', '@{upstream}')
    if (-not $upstream) {
        Stop-Tool "The current branch of $(Get-RepoRoot) has no upstream; nothing to check."
    }
    if (-not (Update-Upstream)) {
        Write-ToolWarning 'git fetch failed (offline?); the count below uses the last fetch.'
    }
    return [pscustomobject]@{
        Upstream = $upstream
        UpstreamSha = Get-GitOutput @('rev-parse', '@{upstream}')
        Behind = [int](Get-GitOutput @('rev-list', '--count', 'HEAD..@{upstream}'))
        Ahead = [int](Get-GitOutput @('rev-list', '--count', '@{upstream}..HEAD'))
    }
}

function New-SyncToastXml([int]$Behind, [string]$Upstream) {
    $title = [Security.SecurityElement]::Escape('Dotfiles repository changed')
    $body = [Security.SecurityElement]::Escape("$Behind new commit(s) on $Upstream. Review and apply them with dots sync.")
    return @"
<toast activationType="protocol" launch="dots-sync:">
  <visual><binding template="ToastGeneric"><text>$title</text><text>$body</text></binding></visual>
  <actions><action content="Sync now" activationType="protocol" arguments="dots-sync:"/></actions>
</toast>
"@
}

# Windows' own toast API through WinRT, which only Windows PowerShell 5.1 projects
function Show-SyncToast([string]$Xml) {
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    $document = New-Object Windows.Data.Xml.Dom.XmlDocument
    $document.LoadXml($Xml)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $document
    # Toasts need a registered app id; Windows PowerShell's is always there
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
}

function Get-NotifiedPath {
    return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'dots\notified'
}

function Invoke-SyncNotify($State) {
    $stamp = Get-NotifiedPath
    if ((Test-Path -LiteralPath $stamp) -and (Get-Content -LiteralPath $stamp -Raw).Trim() -eq $State.UpstreamSha) {
        return
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $stamp) -Force | Out-Null
    Set-Content -LiteralPath $stamp -Value $State.UpstreamSha -Encoding ASCII
    Show-SyncToast (New-SyncToastXml $State.Behind $State.Upstream)
}

function Invoke-SyncCheck([switch]$Notify) {
    $state = Get-SyncState
    Write-Host "behind $($state.Behind), ahead $($state.Ahead)"
    if ($Notify -and $state.Behind -gt 0) {
        Invoke-SyncNotify $state
    }
    return $state
}

# Dot-sourcing (Pester, dots.ps1) loads the functions without running the check
if ($MyInvocation.InvocationName -ne '.') {
    # PowerShell 7 has no WinRT projection, so the toast runs under Windows PowerShell
    if ($Notify -and $PSVersionTable.PSEdition -eq 'Core' -and (Test-Command 'powershell.exe')) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Check -Notify
        exit $LASTEXITCODE
    }
    Invoke-SyncCheck -Notify:$Notify | Out-Null
    exit 0
}
