[CmdletBinding()]
param(
    [ValidateSet('user', 'machine')]
    [string]$Scope = 'user',
    [switch]$DryRun
)

# Applies the registry values from home/.chezmoidata/windows.yaml: windows.registry.user
# (HKCU, the desktop step) or windows.registry.machine (HKLM, dots system, admin).
# Prints current -> new for every value that differs; with -DryRun it changes nothing.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

$script:ValueKinds = @('DWord', 'QWord', 'String', 'ExpandString')

function Test-RegistryAvailable {
    return Test-Path -LiteralPath 'HKCU:\'
}

function Get-RegistryEntry([string]$Scope) {
    # Windows PowerShell 5.1 emits a JSON array as one object; ForEach-Object enumerates it
    return @((Get-RepoData ".windows.registry.$Scope") | ForEach-Object { $_ })
}

# Kind and value of one registry value, or $null when the key or the value is missing
function Get-RegistryCurrent([string]$Path, [string]$Name) {
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $key -or $key.GetValueNames() -notcontains $Name) {
        return $null
    }
    return [pscustomobject]@{
        Kind = $key.GetValueKind($Name).ToString()
        Value = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
    }
}

function ConvertTo-RegistryValue($Entry) {
    switch ($Entry.type) {
        'DWord' { return [int]$Entry.value }
        'QWord' { return [long]$Entry.value }
        default { return [string]$Entry.value }
    }
}

function Set-RegistryEntry($Entry) {
    if (-not (Test-Path -LiteralPath $Entry.path)) {
        New-Item -Path $Entry.path -Force | Out-Null
    }
    # -Force replaces an existing value, including one of another kind
    New-ItemProperty -LiteralPath $Entry.path -Name $Entry.name -PropertyType $Entry.type -Value (ConvertTo-RegistryValue $Entry) -Force | Out-Null
}

# Explorer reads its settings at start; Windows restarts the shell when it exits
function Restart-Explorer {
    Get-Process -Name 'explorer' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath 'explorer.exe'
    }
}

function Invoke-RegistryStep([string]$Scope, [switch]$DryRun) {
    if (-not (Test-RegistryAvailable)) {
        Write-ToolWarning 'The Windows registry is unavailable on this system; nothing to do.'
        return
    }
    if (-not $DryRun -and -not (Test-Command 'chezmoi')) {
        Stop-Tool 'chezmoi is required to read home/.chezmoidata/windows.yaml.'
    }
    if (-not (Test-Command 'chezmoi')) {
        Write-ToolWarning 'chezmoi is unavailable; the registry values cannot be previewed in this dry-run.'
        return
    }

    $pending = @()
    foreach ($entry in Get-RegistryEntry $Scope) {
        if ($entry.type -notin $script:ValueKinds) {
            Stop-Tool "Unsupported registry type '$($entry.type)' for $($entry.path)\$($entry.name) (use $($script:ValueKinds -join ', '))"
        }
        $current = Get-RegistryCurrent $entry.path $entry.name
        if ($null -ne $current -and $current.Kind -eq $entry.type -and
            "$($current.Value)" -eq "$(ConvertTo-RegistryValue $entry)") {
            continue
        }

        $old = if ($null -eq $current) { '<unset>' } else { "$($current.Value) ($($current.Kind))" }
        Write-Host "  $($entry.path) $($entry.name): $old -> $($entry.value) ($($entry.type))"
        $pending += $entry
    }

    if ($pending.Count -eq 0) {
        Write-Success "Registry values ($Scope) already match windows.yaml"
        return
    }
    Write-Step "$($pending.Count) registry value(s) ($Scope) differ from windows.yaml"

    if ($Scope -eq 'machine' -and -not $DryRun -and -not (Test-Elevated)) {
        Stop-Tool 'Machine registry values need an administrator PowerShell; run: dots system'
    }

    foreach ($entry in $pending) {
        if ($DryRun) {
            Write-Host "+ set $($entry.path) $($entry.name) = $($entry.value) ($($entry.type))"
        } else {
            Set-RegistryEntry $entry
        }
    }

    if (@($pending | Where-Object { $_.path -match '\\Explorer\\' }).Count -gt 0) {
        if ($DryRun) {
            Write-Host '+ restart Explorer'
        } else {
            Restart-Explorer
        }
    }
    if ($Scope -eq 'machine') {
        Write-ToolWarning 'Machine values take effect after the next restart.'
    }

    Write-Success "Registry values ($Scope) step complete"
}

# Dot-sourcing (Pester) loads the functions without running the step
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-RegistryStep -Scope $Scope -DryRun:$DryRun
}
