BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Wallpaper = Join-Path $RepoRoot 'scripts\windows\setup-wallpaper.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:HasChezmoi = [bool](Get-Command chezmoi -ErrorAction SilentlyContinue)

    # Runs the script in a child pwsh whose HOME is $HomeDir (honoured on Linux; Windows
    # takes $HOME from the profile folder, where the runner has no wallpaper clone)
    function script:Invoke-WallpaperDryRun([string]$HomeDir) {
        $previous = $env:HOME
        $env:HOME = $HomeDir
        try {
            return (& $script:Pwsh -NoProfile -File $script:Wallpaper -DryRun *>&1 | Out-String)
        } finally {
            $env:HOME = $previous
        }
    }
}

Describe 'setup-wallpaper.ps1' {
    It 'prints the clone and the wallpaper change in a dry run' {
        if (-not $HasChezmoi) {
            Set-ItResult -Skipped -Because 'chezmoi is not installed'
            return
        }
        if ($IsWindows -and (Test-Path -LiteralPath (Join-Path $HOME 'Pictures\wallpaper'))) {
            Set-ItResult -Skipped -Because 'Windows takes HOME from the profile folder, which already has Pictures\wallpaper'
            return
        }
        $homeDir = Join-Path $TestDrive 'fresh-home'
        New-Item -ItemType Directory -Path $homeDir | Out-Null

        $output = Invoke-WallpaperDryRun $homeDir

        $output | Should -Match 'Cloning wallpapers from https://github.com/TienHwng/wallpapers.git'
        $output | Should -Match '\+ chezmoi --source .+ apply --verbose .+wallpaper'
        $output | Should -Match '\+ set the desktop wallpaper to .+space2\.jpg'
        Test-Path -LiteralPath (Join-Path $homeDir 'Pictures') | Should -BeFalse
    }

    It 'refuses a directory that is a clone of another repository' {
        if (-not $HasChezmoi -or $IsWindows) {
            Set-ItResult -Skipped -Because 'needs chezmoi and a HOME the child process honours (Linux)'
            return
        }
        $homeDir = Join-Path $TestDrive 'foreign-home'
        $clone = Join-Path $homeDir 'Pictures/wallpaper'
        & git init -q $clone
        & git -C $clone remote add origin https://github.com/someone/wallpaper.git

        $output = Invoke-WallpaperDryRun $homeDir

        $output | Should -Match 'is not a clone of https://github.com/TienHwng/wallpapers.git'
    }
}
