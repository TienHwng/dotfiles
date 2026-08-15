Set-StrictMode -Version Latest
$script:DotfilesCommonRoot = $PSScriptRoot

function Write-Step([string]$Message) {
    Write-Host "→ $Message" -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host "✔ $Message" -ForegroundColor Green
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

function Get-ListFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    return @(
        Get-Content -LiteralPath $Path |
            ForEach-Object { ($_ -replace '\s*#.*$', '').Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-ChezmoiValue([string]$Expression, [string]$Fallback = '') {
    if (Test-Command 'chezmoi') {
        $value = (& chezmoi execute-template "{{ $Expression }}" 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and
            -not [string]::IsNullOrWhiteSpace($value) -and
            $value -notin @('<no value>', '<nil>')) {
            return $value
        }
    }

    return $Fallback
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

    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0 -and -not $IgnoreExitCode) {
        throw "$FilePath failed with exit code $exitCode"
    }

    return $exitCode
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
