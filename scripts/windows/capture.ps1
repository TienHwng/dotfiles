[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$NonInteractive
)

# Lists what changed on this machine but not in the repository, lets you pick items, writes
# them back, then shows the diff, asks for a message, commits to main and pushes:
#   file      a file changed in the repository
#   re-add    a dotfile chezmoi copied here and you edited (templates are listed instead)
#   registry  a registry value that differs from home/.chezmoidata/windows.yaml
#   packages  WinGet/Scoop packages that are not in the manifest (a second picker:
#             add them to the manifest or uninstall them)
# -DryRun lists the items and changes nothing.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
# Dot-sourcing setup-registry.ps1 binds its own -DryRun in this scope; keep ours first
$script:CaptureDryRun = [bool]$DryRun
$script:CaptureNonInteractive = [bool]$NonInteractive
. (Join-Path $PSScriptRoot 'setup-registry.ps1')
. (Join-Path $PSScriptRoot 'package-diff.ps1')

$script:Branch = 'main'
$script:WindowsYaml = Join-Path (Get-RepoRoot) 'home\.chezmoidata\windows.yaml'
$script:Templates = [System.Collections.Generic.List[string]]::new()

function Invoke-RepoGit([string[]]$Arguments) {
    # Windows PowerShell 5.1 turns native stderr into a terminating error under 'Stop'
    $ErrorActionPreference = 'Continue'
    return @(& git -C (Get-RepoRoot) @Arguments 2>$null)
}

function Get-ChezmoiDrift {
    if (-not (Test-Command 'chezmoi')) {
        return @()
    }
    $ErrorActionPreference = 'Continue'
    return @(& chezmoi --source (Join-Path (Get-RepoRoot) 'home') status --exclude externals, scripts 2>$null)
}

function Get-ChezmoiSourcePath([string]$Target) {
    $ErrorActionPreference = 'Continue'
    return "$(& chezmoi --source (Join-Path (Get-RepoRoot) 'home') source-path $Target 2>$null)".Trim()
}

function New-CaptureItem([string]$Kind, $Payload, [string]$Label) {
    return [pscustomobject]@{ Kind = $Kind; Payload = $Payload; Label = $Label }
}

function Get-CaptureItem {
    $items = [System.Collections.Generic.List[object]]::new()

    foreach ($line in Invoke-RepoGit @('status', '--porcelain=v1', '--untracked-files=all')) {
        if ("$line".Length -lt 4) {
            continue
        }
        $path = ("$line".Substring(3) -split ' -> ')[-1]
        $items.Add((New-CaptureItem 'file' $path ("file      {0} {1}" -f "$line".Substring(0, 2), $path)))
    }

    # Targets edited by hand since chezmoi wrote them (first status column)
    foreach ($line in Get-ChezmoiDrift) {
        if ("$line".Length -lt 4 -or "$line"[0] -ne 'M') {
            continue
        }
        $target = Join-Path $HOME "$line".Substring(3)
        $source = Get-ChezmoiSourcePath $target
        if (-not $source) {
            continue
        }
        if ($source.EndsWith('.tmpl')) {
            $script:Templates.Add("$target ($source)")
        } else {
            $items.Add((New-CaptureItem 're-add' $target "re-add    $target"))
        }
    }

    if ((Test-RegistryAvailable) -and (Test-Command 'chezmoi')) {
        foreach ($scope in @('user', 'machine')) {
            foreach ($entry in Get-RegistryEntry $scope) {
                $current = Get-RegistryCurrent $entry.path $entry.name
                if ($null -eq $current -or $current.Kind -ne $entry.type -or
                    "$($current.Value)" -eq "$(ConvertTo-RegistryValue $entry)") {
                    continue
                }
                $items.Add((New-CaptureItem 'registry' ([pscustomobject]@{ Entry = $entry; Value = $current.Value }) `
                    ("registry  {0} {1}: {2} -> {3}" -f $entry.path, $entry.name, $entry.value, $current.Value)))
            }
        }
    }
    if (Test-Command 'chezmoi') {
        $extra = @(Get-ExtraPackage)
        if ($extra.Count -gt 0) {
            $items.Add((New-CaptureItem 'packages' $extra "packages  pick from $($extra.Count) installed package(s) not in the manifest"))
        }
    }
    return $items
}

# YAML scalar for a registry value: numbers bare, strings single-quoted
function Format-YamlValue([string]$Type, $Value) {
    if ($Type -in @('DWord', 'QWord')) {
        return "$Value"
    }
    return "'" + ("$Value" -replace "'", "''") + "'"
}

# Sets value: on the windows.yaml line of this path and name (one-line flow mappings)
function Set-RegistryYamlValue($Entry, $Value) {
    $lines = [IO.File]::ReadAllLines($script:WindowsYaml)
    $pathPattern = "path: '" + [regex]::Escape(($Entry.path -replace "'", "''")) + "'"
    $namePattern = 'name: ' + [regex]::Escape($Entry.name) + ','
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pathPattern -and $lines[$i] -match $namePattern) {
            $lines[$i] = $lines[$i].Substring(0, $lines[$i].LastIndexOf('value: ')) + "value: $(Format-YamlValue $Entry.type $Value) }"
            $found = $true
            break
        }
    }
    if (-not $found) {
        Stop-Tool "No windows.yaml entry for $($Entry.path) $($Entry.name)"
    }
    # windows.yaml is ASCII; keep LF endings
    [IO.File]::WriteAllText($script:WindowsYaml, (($lines -join "`n") + "`n"))
}

function Test-UseGum {
    return (-not $env:DOTS_NO_GUM) -and
        (-not [Console]::IsInputRedirected) -and
        (-not [Console]::IsOutputRedirected) -and
        (Test-Command 'gum')
}

function Read-CaptureAnswer([string]$Prompt) {
    return "$(Read-Host $Prompt)".Trim()
}

# The chosen labels
function Select-CaptureLabel([string[]]$Label, [string]$Header = 'Changes to keep in the repository') {
    if (Test-UseGum) {
        return @($Label | & gum filter --no-limit --header $Header)
    }
    Write-Host $Header
    for ($i = 0; $i -lt $Label.Count; $i++) {
        Write-Host ('  {0,3}  {1}' -f ($i + 1), $Label[$i])
    }
    $answer = Read-CaptureAnswer 'Numbers to capture (e.g. 1 3, "all"; empty for none)'
    if ($answer -eq 'all') {
        return $Label
    }
    return @($answer -split '\s+' | Where-Object { $_ -match '^\d+$' -and [int]$_ -ge 1 -and [int]$_ -le $Label.Count } |
        ForEach-Object { $Label[[int]$_ - 1] })
}

function Invoke-CaptureItem($Item) {
    switch ($Item.Kind) {
        'file' { Invoke-RepoGit @('add', '-A', '--', $Item.Payload) | Out-Null }
        're-add' {
            Invoke-NativeCommand -FilePath 'chezmoi' -ArgumentList @('--source', (Join-Path (Get-RepoRoot) 'home'), 're-add', $Item.Payload) | Out-Null
            Invoke-RepoGit @('add', '-A', '--', (Get-ChezmoiSourcePath $Item.Payload)) | Out-Null
        }
        'registry' {
            Set-RegistryYamlValue $Item.Payload.Entry $Item.Payload.Value
            Invoke-RepoGit @('add', '--', $script:WindowsYaml) | Out-Null
        }
        'packages' { Invoke-PackageCapture $Item.Payload }
    }
}

# Second picker for packages outside the manifest: add them to it, or uninstall them
function Invoke-PackageCapture($Extra) {
    $labels = @($Extra | ForEach-Object { '{0,-7} {1}' -f $_.Manager, $_.Name })
    $chosen = @(Select-CaptureLabel $labels 'Packages outside the manifest')
    if ($chosen.Count -eq 0) {
        return
    }
    $answer = Read-CaptureAnswer "$($chosen.Count) package(s): [a]dd to the manifest / [u]ninstall / [s]kip"
    foreach ($manager in @('winget', 'scoop')) {
        $names = @($Extra | Where-Object { $_.Manager -eq $manager -and $chosen -contains ('{0,-7} {1}' -f $_.Manager, $_.Name) } |
            ForEach-Object { $_.Name })
        if ($names.Count -eq 0) {
            continue
        }
        switch -Regex ($answer) {
            '^(a|add)' {
                Add-ManifestPackage $manager $names
                Invoke-RepoGit @('add', '--', $script:PackagesYaml) | Out-Null
            }
            '^(u|uninstall)' { Uninstall-ExtraPackage $manager $names }
            default { Write-ToolWarning 'Packages left alone' }
        }
    }
}

function Complete-Capture {
    if (@(Invoke-RepoGit @('diff', '--cached', '--name-only')).Count -eq 0) {
        Write-ToolWarning 'Nothing selected; nothing committed.'
        return
    }
    Invoke-RepoGit @('--no-pager', 'diff', '--cached', '--stat') | ForEach-Object { Write-Host $_ }
    Invoke-RepoGit @('--no-pager', 'diff', '--cached') | ForEach-Object { Write-Host $_ }

    $default = "Capture local changes from $env:COMPUTERNAME"
    $message = Read-CaptureAnswer "Commit message [$default]"
    if (-not $message) {
        $message = $default
    }
    if (-not (Confirm-Action "Commit and push to origin/$($script:Branch)?" -DefaultYes $true)) {
        Invoke-RepoGit @('reset', '--quiet') | Out-Null
        Write-ToolWarning 'Unstaged everything; your edits stay in the working tree.'
        return
    }
    $root = Get-RepoRoot
    Invoke-NativeCommand -FilePath 'git' -ArgumentList @('-C', $root, 'commit', '--quiet', '-m', $message) | Out-Null
    Invoke-NativeCommand -FilePath 'git' -ArgumentList @('-C', $root, 'push', '--quiet', 'origin', $script:Branch) | Out-Null
    Write-Success "Committed and pushed to origin/$($script:Branch): $message"
}

function Invoke-Capture([switch]$DryRun, [switch]$NonInteractive) {
    $items = @(Get-CaptureItem)
    if ($script:Templates.Count -gt 0) {
        Write-ToolWarning 'Templates changed by hand; edit their source and run dots capture again:'
        $script:Templates | ForEach-Object { Write-Host "  $_" }
    }
    if ($items.Count -eq 0) {
        Write-Success 'Nothing to capture: this machine matches the repository'
        return
    }
    if ($DryRun) {
        Write-Step "$($items.Count) item(s) to capture:"
        $items | ForEach-Object { Write-Host "  $($_.Label)" }
        return
    }
    if ($NonInteractive) {
        Stop-Tool 'dots capture asks what to keep; it never runs non-interactively.'
    }
    if ("$(Invoke-RepoGit @('branch', '--show-current'))".Trim() -ne $script:Branch) {
        Stop-Tool "Captures commit to $($script:Branch); switch the repository to it first (git -C $(Get-RepoRoot) switch $($script:Branch))."
    }
    if (@(Invoke-RepoGit @('diff', '--cached', '--name-only')).Count -gt 0) {
        Stop-Tool 'The repository already has staged changes; commit or unstage them first.'
    }

    foreach ($label in Select-CaptureLabel @($items | ForEach-Object { $_.Label })) {
        $items | Where-Object { $_.Label -eq $label } | ForEach-Object { Invoke-CaptureItem $_ }
    }
    Complete-Capture
}

# Dot-sourcing (Pester) loads the functions without running a capture
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Capture -DryRun:$script:CaptureDryRun -NonInteractive:$script:CaptureNonInteractive
}
