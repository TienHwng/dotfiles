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

# One package per line from a manifest list (winget, scoop, nerdFonts, ...) in
# home/.chezmoidata/packages.yaml, rendered by scripts/package-list.tmpl.
function Get-ManifestList([string]$List) {
    $repoRoot = Get-RepoRoot
    $template = Join-Path $repoRoot 'scripts\package-list.tmpl'
    $previous = $env:DOTFILES_PACKAGE_LIST
    $env:DOTFILES_PACKAGE_LIST = $List
    try {
        $output = Get-Content -LiteralPath $template -Raw | & chezmoi --source $repoRoot execute-template
        if ($LASTEXITCODE -ne 0) {
            Stop-Tool "Could not read the '$List' list from the package manifest."
        }
    } finally {
        $env:DOTFILES_PACKAGE_LIST = $previous
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
