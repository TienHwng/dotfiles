Set-StrictMode -Version Latest
$script:DotfilesCommonRoot = $PSScriptRoot

# Symbols as char codes: Windows PowerShell 5.1 reads BOM-less scripts as ANSI
$script:ArrowSymbol = [char]0x2192
$script:CheckSymbol = [char]0x2714
$script:CrossSymbol = [char]0x2718

function Write-Step([string]$Message) {
    Write-Host "$script:ArrowSymbol $Message" -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host "$script:CheckSymbol $Message" -ForegroundColor Green
}

function Write-Failure([string]$Message) {
    Write-Host "$script:CrossSymbol $Message" -ForegroundColor Red
}

function Write-ToolWarning([string]$Message) {
    Write-Warning $Message
}

function Stop-Tool([string]$Message) {
    throw $Message
}

function Test-Command([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $script:DotfilesCommonRoot '..\..\..')).Path
}

# The firmware's manufacturer ("ASUSTeK COMPUTER INC."); empty when unknown
function Get-MachineVendor {
    if (Test-Command 'Get-CimInstance') {
        $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($null -ne $system) {
            return "$($system.Manufacturer)".Trim()
        }
    }
    $sysVendor = '/sys/class/dmi/id/sys_vendor'
    if (Test-Path -LiteralPath $sysVendor) {
        return (Get-Content -LiteralPath $sysVendor -Raw).Trim()
    }
    return ''
}

# One package per line from a manifest list (winget, scoop, nerdFonts, ...) in
# home/.chezmoidata/packages.yaml, rendered by scripts/package-list.tmpl.
function Get-ManifestList([string]$List) {
    $repoRoot = Get-RepoRoot
    $template = Join-Path $repoRoot 'scripts\package-list.tmpl'
    $previous = $env:DOTFILES_PACKAGE_LIST
    $previousVendor = $env:DOTFILES_VENDOR
    $env:DOTFILES_PACKAGE_LIST = $List
    # A set DOTFILES_VENDOR overrides detection (tests)
    if ($null -eq $previousVendor) {
        $env:DOTFILES_VENDOR = Get-MachineVendor
    }
    try {
        $output = Get-Content -LiteralPath $template -Raw | & chezmoi --source $repoRoot execute-template
        if ($LASTEXITCODE -ne 0) {
            Stop-Tool "Could not read the '$List' list from the package manifest."
        }
    } finally {
        $env:DOTFILES_PACKAGE_LIST = $previous
        $env:DOTFILES_VENDOR = $previousVendor
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    return @(
        $output |
            ForEach-Object { "$_".Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $seen.Add($_) }
    )
}

function Get-ChezmoiValue([string]$Expression, [string]$Fallback = '') {
    if (Test-Command 'chezmoi') {
        # Windows PowerShell 5.1 turns native stderr into a terminating error under 'Stop'
        $ErrorActionPreference = 'Continue'
        $value = (& chezmoi execute-template "{{ $Expression }}" 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and
            -not [string]::IsNullOrWhiteSpace($value) -and
            $value -notin @('<no value>', '<nil>')) {
            return $value
        }
    }

    return $Fallback
}

# Chezmoi data from this checkout, parsed from JSON ($null when unset). Reads the checkout
# because on a fresh machine's dry-run chezmoi has no source directory yet.
function Get-RepoData([string]$Expression) {
    $sourceDir = Join-Path (Get-RepoRoot) 'home'
    $json = & chezmoi --source $sourceDir execute-template "{{ $Expression | toJson }}"
    if ($LASTEXITCODE -ne 0) {
        Stop-Tool "Could not read $Expression from home/.chezmoidata."
    }
    return ($json | ConvertFrom-Json)
}

function Format-NativeCommand([string]$FilePath, [string[]]$ArgumentList) {
    $parts = @($FilePath) + @($ArgumentList | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    })
    return '+ ' + ($parts -join ' ')
}

function Invoke-NativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$DryRun,
        [switch]$IgnoreExitCode
    )

    if ($DryRun) {
        Write-Host (Format-NativeCommand $FilePath $ArgumentList)
        return 0
    }

    # Out-Host keeps the command's output on screen and out of the return value
    & $FilePath @ArgumentList | Out-Host
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0 -and -not $IgnoreExitCode) {
        throw "$FilePath failed with exit code $exitCode"
    }

    return $exitCode
}

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# The Windows OpenSSH Authentication Agent owns the same pipe as Bitwarden's agent
function Test-WindowsAgentRunning {
    if (-not (Test-Command 'Get-Service')) {
        return $false
    }
    $service = Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
    return $null -ne $service -and $service.Status -eq 'Running'
}

# True when the exact WinGet package id is installed
function Test-WingetPackage([string]$Id) {
    & winget list --id $Id --exact --source winget --accept-source-agreements --disable-interactivity *> $null
    return $LASTEXITCODE -eq 0
}

function Get-ScoopRoot {
    if ($env:SCOOP) {
        return $env:SCOOP
    }
    return Join-Path $HOME 'scoop'
}

# True when a Scoop app ("app" or "bucket/app") is installed for this user
function Test-ScoopApp([string]$Name) {
    $app = ($Name -split '/')[-1]
    return Test-Path -LiteralPath (Join-Path (Get-ScoopRoot) "apps\$app\current")
}

# Scoop installs per user and refuses an elevated shell
function Install-Scoop {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'The official Scoop installer is a script.')]
    [CmdletBinding()]
    param([switch]$DryRun)

    if (Test-Command 'scoop') {
        return
    }
    if ($DryRun) {
        Write-Host '+ Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression'
        return
    }
    if (Test-Elevated) {
        Stop-Tool 'Scoop cannot be installed from an elevated shell. Run dots from a normal PowerShell window.'
    }

    Write-Step 'Installing Scoop...'
    Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    Update-ProcessPath
    if (-not (Test-Command 'scoop')) {
        Stop-Tool 'Scoop was installed but is not on PATH; open a new terminal and run dots again.'
    }
}

function Add-ScoopBucket([string]$Bucket, [switch]$DryRun) {
    if (Test-Path -LiteralPath (Join-Path (Get-ScoopRoot) "buckets\$Bucket")) {
        return
    }
    Invoke-NativeCommand -FilePath 'scoop' -ArgumentList @('bucket', 'add', $Bucket) -DryRun:$DryRun | Out-Null
}

function Update-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machinePath, $userPath) -join ';'
}

function Confirm-Action([string]$Message, [bool]$DefaultYes = $false, [switch]$NonInteractive) {
    if ($NonInteractive) {
        return $DefaultYes
    }

    $suffix = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$Message $suffix"

    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $DefaultYes
    }
    return $answer -match '^[Yy]'
}
