[CmdletBinding()]
param(
    [switch]$DryRun
)

# Installs the NVIDIA App on a machine with an NVIDIA GPU, from the installer pinned in
# windows.nvidia.app (home/.chezmoidata/windows.yaml). The app is not in the official winget
# repository, so the download is checked against the pinned SHA-256 and must carry a valid
# NVIDIA Corporation signature before it runs. Once installed, the app updates itself and the
# driver, so an installed app of any version is left alone.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

# PCI vendor id 10DE is NVIDIA
function Test-NvidiaGpu {
    if (-not (Test-Command 'Get-CimInstance')) {
        return $false
    }
    $controllers = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue)
    return @($controllers | Where-Object { "$($_.PNPDeviceID)" -match 'VEN_10DE' }).Count -gt 0
}

# DisplayVersion of the installed NVIDIA App ("NVIDIA App 11.0.9.565", not its components
# such as "NVIDIA App driver settings"), or $null
function Get-NvidiaAppVersion {
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entry = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.PSObject.Properties['DisplayName'] -and "$($_.DisplayName)" -match '^NVIDIA app( [\d.]+)?$' } |
        Select-Object -First 1
    if ($null -eq $entry) {
        return $null
    }
    if ($entry.PSObject.Properties['DisplayVersion']) {
        return "$($entry.DisplayVersion)"
    }
    return 'unknown version'
}

function Save-NvidiaInstaller([string]$Url, [string]$Path) {
    # Windows PowerShell 5.1 downloads many times slower while it draws the progress bar
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing
}

function Test-NvidiaSignature([string]$Path) {
    $signature = Get-AuthenticodeSignature -FilePath $Path
    return "$($signature.Status)" -eq 'Valid' -and
        $null -ne $signature.SignerCertificate -and
        $signature.SignerCertificate.Subject -match 'O="?NVIDIA Corporation'
}

# The installer shows its own window; dots system runs it from an administrator shell
function Start-NvidiaInstaller([string]$Path) {
    return (Start-Process -FilePath $Path -Wait -PassThru).ExitCode
}

function Install-NvidiaApp($App) {
    $downloadDir = Join-Path ([IO.Path]::GetTempPath()) 'dots-nvidia-app'
    $installer = Join-Path $downloadDir ([IO.Path]::GetFileName(([uri]$App.url).AbsolutePath))
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
    try {
        Write-Step "Downloading $($App.url)"
        Save-NvidiaInstaller $App.url $installer

        $hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
        if ($hash -ne $App.sha256) {
            Stop-Tool "The NVIDIA App installer does not match windows.nvidia.app.sha256 (expected $($App.sha256), got $hash). Nothing was installed."
        }
        if (-not (Test-NvidiaSignature $installer)) {
            Stop-Tool 'The NVIDIA App installer has no valid NVIDIA Corporation signature. Nothing was installed.'
        }

        Write-Step 'Running the NVIDIA App installer...'
        $exitCode = Start-NvidiaInstaller $installer
        # 3010: installed, a restart completes it
        if ($exitCode -eq 3010) {
            Write-ToolWarning 'The NVIDIA App installer asks for a restart.'
        } elseif ($exitCode -ne 0) {
            Stop-Tool "The NVIDIA App installer failed with exit code $exitCode"
        }
    } finally {
        Remove-Item -LiteralPath $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-NvidiaAppStep([switch]$DryRun) {
    if (-not (Test-NvidiaGpu)) {
        Write-Success 'No NVIDIA GPU; the NVIDIA App is not needed'
        return
    }
    $installed = Get-NvidiaAppVersion
    if ($installed) {
        Write-Success "NVIDIA App $installed is installed; it updates itself and the driver"
        return
    }
    if (-not (Test-Command 'chezmoi')) {
        if ($DryRun) {
            Write-ToolWarning 'chezmoi is unavailable; the NVIDIA App install cannot be previewed in this dry-run.'
            return
        }
        Stop-Tool 'chezmoi is required to read windows.nvidia.app.'
    }

    $app = Get-RepoData '.windows.nvidia.app'
    if ($null -eq $app) {
        Write-ToolWarning 'windows.nvidia.app is not set in windows.yaml; install the NVIDIA App by hand.'
        return
    }

    Write-Host "  NVIDIA App: <not installed> -> $($app.version)"
    if ($DryRun) {
        Write-Host "+ download $($app.url)"
        Write-Host "+ check SHA-256 $($app.sha256) and the NVIDIA Corporation signature"
        Write-Host '+ run the NVIDIA App installer'
        return
    }
    Install-NvidiaApp $app
    Write-Success "Installed the NVIDIA App $($app.version)"
}

# Dot-sourcing (Pester) loads the functions without running the step
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-NvidiaAppStep -DryRun:$DryRun
}
