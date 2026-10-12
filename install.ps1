#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\cmd3r'),
    [string]$CacheRoot = (Join-Path $env:LOCALAPPDATA 'cmd3r\downloads'),
    [string]$TerminalSettingsPath,
    [switch]$StageOnly,
    [switch]$SkipLaunch,
    [switch]$Offline,
    [switch]$NoAnimation,
    [ValidateSet('Ask','Yes','No')][string]$NvmWindows = 'Ask',
    [ValidateSet('Ask','Yes','No')][string]$Npkill = 'Ask',
    [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
try {
. ([IO.Path]::Combine($PSScriptRoot, 'src\installer-host.ps1'))
. (Join-Path $PSScriptRoot 'src\progress.ps1')
if ($env:OS -ne 'Windows_NT' -or ![Environment]::Is64BitOperatingSystem) { throw 'cmd3r requires 64-bit Windows 10/11 (Windows 11 ARM64 uses x64 emulation).' }
if ([Environment]::OSVersion.Version.Build -lt 19041) { throw 'Latest Windows Terminal requires Windows 10 build 19041 or newer.' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
. (Join-Path $PSScriptRoot 'src\setup-lib.ps1')
. (Join-Path $PSScriptRoot 'src\platform.ps1')
. (Join-Path $PSScriptRoot 'src\optional-tools.ps1')
Write-Host "`n  Optional developer tools (Enter skips):" -ForegroundColor Cyan
$wantNvm = Read-Cmd3rOptionalChoice -Label 'NVM for Windows' -Description 'Manage and switch between Node.js versions. Uses a verified offline installer; an existing NVM installation is kept. Node.js versions are installed separately.' -Choice $NvmWindows -NonInteractive:$NonInteractive -StageOnly:$StageOnly
$wantNpkill = Read-Cmd3rOptionalChoice -Label 'npkill' -Description 'Find node_modules folders and choose which ones to delete to free disk space. Requires active Node.js/npm. This setup only installs the tool; it does not delete any folders.' -Choice $Npkill -NonInteractive:$NonInteractive -StageOnly:$StageOnly
Initialize-Cmd3rProgress -Steps ($(if ($StageOnly) {5} else {11}) + [int]$wantNvm + [int]$wantNpkill) -NoAnimation:$NoAnimation
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
# Platform prerequisites are resolved, downloaded, installed, and verified
# before fetching productivity tools or changing fonts and configuration.
Start-Cmd3rStep 'Resolve the latest stable platform releases'
$platform = Get-PlatformCatalog -CacheRoot $CacheRoot -Offline:$Offline
Stop-Cmd3rStep -Message ("PowerShell {0}  /  Windows Terminal {1}  /  {2}" -f $platform.powershell.version,$platform.terminal.version,$platform.architecture)
Start-Cmd3rStep 'Install or update PowerShell from its offline MSI'
$pwshExe = Install-StablePowerShell $platform $CacheRoot -StageOnly:$StageOnly -Offline:$Offline
$pwshHome = Split-Path $pwshExe
Stop-Cmd3rStep -Message $(if ($StageOnly) {'Downloaded and verified; system installation skipped'} else {$pwshExe})
Start-Cmd3rStep 'Install or update Windows Terminal from its offline kit'
Install-StableTerminal $platform $CacheRoot -StageOnly:$StageOnly -Offline:$Offline
Stop-Cmd3rStep -Message $(if ($StageOnly) {'Downloaded offline bundle and dependencies; system installation skipped'} else {'Stable Windows Terminal and runtime dependencies verified'})
if ($wantNvm) {
    Start-Cmd3rStep 'Prepare optional NVM for Windows from its offline installer'
    Install-Cmd3rNvm -CacheRoot $CacheRoot -Offline:$Offline -StageOnly:$StageOnly -NonInteractive:($NonInteractive -or [Console]::IsInputRedirected)
    Stop-Cmd3rStep
}
if ($wantNpkill) {
    Start-Cmd3rStep 'Prepare optional npkill and its dependencies'
    Install-Cmd3rNpkill -InstallRoot $InstallRoot -CacheRoot $CacheRoot -Offline:$Offline -StageOnly:$StageOnly
    Stop-Cmd3rStep
}
$preferences = Get-Content (Join-Path $PSScriptRoot 'src\preferences.json') -Raw | ConvertFrom-Json
$scheme = Get-Content (Join-Path $PSScriptRoot 'src\scheme.json') -Raw | ConvertFrom-Json
$lightScheme = Get-Content (Join-Path $PSScriptRoot 'src\scheme-light.json') -Raw | ConvertFrom-Json
$themeMode = 'dark'
$modeFile = Join-Path $InstallRoot 'config\theme-mode.txt'
if (Test-Path $modeFile) {
    $savedMode = [IO.File]::ReadAllText($modeFile).Trim()
    if ($savedMode -in @('light','dark')) { $themeMode = $savedMode }
}
$preferences.colorScheme = $(if ($themeMode -eq 'light') {$lightScheme.name} else {$scheme.name})
$packages = Get-Content (Join-Path $PSScriptRoot 'packages.lock.json') -Raw | ConvertFrom-Json
$bin = Join-Path $InstallRoot 'bin'
$config = Join-Path $InstallRoot 'config'
$statePath = Join-Path $InstallRoot 'installed-packages.json'
$backup = Join-Path $InstallRoot ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
foreach ($dir in @($InstallRoot,$bin,$config,$backup,(Join-Path $InstallRoot 'data\posh-cache'),(Join-Path $InstallRoot 'data\zoxide'))) {
    [IO.Directory]::CreateDirectory($dir) | Out-Null
}
$oldState = @()
if (Test-Path $statePath) { $oldState = Get-Content $statePath -Raw | ConvertFrom-Json }
$newState = @()
if (!$StageOnly) {
    Start-Cmd3rStep 'Check Git for Windows'
    if (!(Get-Command git.exe -ErrorAction SilentlyContinue)) {
        $gitCandidates = @((Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),(Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe'))
        $gitExe = $gitCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (!$gitExe) {
            if ($Offline) { throw 'Offline mode requires Git to be installed already.' }
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
            if (!$winget) { throw 'Install App Installer (winget) to provision Git, then rerun cmd3r.' }
            if ($script:Cmd3rAnimated) { [Cmd3r.CliSpinner]::Stop() }
            & $winget.Source install --id Git.Git --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
            if ($LASTEXITCODE -ne 0) { throw "Git installation failed (exit $LASTEXITCODE)" }
            $gitExe = $gitCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        }
        if (!$gitExe) { throw 'Git installer completed but git.exe was not found' }
        $env:PATH = (Split-Path $gitExe) + ';' + $env:PATH
    }
    Stop-Cmd3rStep
}
Start-Cmd3rStep 'Download and install productivity tools'
foreach ($package in $packages) {
    $archive = Get-VerifiedDownload -Url $package.url -Sha256 $package.sha256 -CacheRoot $CacheRoot -Offline:$Offline
    $target = Join-Path $InstallRoot ("packages\$($package.id)\$($package.version)")
    if ($package.id -eq 'geist-font') { $fontSource = $target }
    $installed = @($oldState | Where-Object { $_.id -eq $package.id -and $_.sha256 -eq $package.sha256 }) | Select-Object -First 1
    $ready = Test-Path $target
    if ($package.executable) { $ready = Test-Path (Join-Path $bin $package.executable) }
    if (!$installed -or !$ready) {
        Write-Cmd3rNote "Installing $($package.id) $($package.version)"
        [IO.Directory]::CreateDirectory($target) | Out-Null
        if ($archive.EndsWith('.zip')) {
            Expand-Archive -LiteralPath $archive -DestinationPath $target -Force
            if ($package.executable) {
                $exe = Get-ChildItem $target -Recurse -File -Filter $package.executable | Select-Object -First 1
                if (!$exe) { throw "Archive missing $($package.executable)" }
                Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $bin $package.executable) -Force
            }
        } else {
            Copy-Item -LiteralPath $archive -Destination (Join-Path $bin $package.executable) -Force
        }
    } else { Write-Cmd3rNote "Ready: $($package.id) $($package.version)" }
    $newState += $package
}
Stop-Cmd3rStep
Start-Cmd3rStep 'Prepare the lightweight shell configuration'
foreach ($name in 'profile.ps1','theme.ps1','workspace-dark.omp.json','workspace-light.omp.json') {
    Backup-ExistingFile -Path (Join-Path $config $name) -BackupRoot $backup
    Copy-Item (Join-Path $PSScriptRoot "src\$name") $config -Force
}
Write-Utf8File (Join-Path $config 'theme-mode.txt') $themeMode
Write-Utf8File -Path (Join-Path $config 'paths.ps1') -Text ("`$terminalPwsh = '" + $pwshHome.Replace("'","''") + "'")
$zinit = (& (Join-Path $bin 'zoxide.exe') init powershell) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Zoxide initialization failed' }
Write-Utf8File (Join-Path $config 'zoxide-init.ps1') $zinit
Write-Utf8File $statePath (ConvertTo-Json -InputObject @($newState) -Depth 8)

# Install a copy of the source so cmd3r doctor/update survive moving the clone.
$setup = Join-Path $InstallRoot 'setup'
if ([IO.Path]::GetFullPath($PSScriptRoot) -ne [IO.Path]::GetFullPath($setup)) {
    [IO.Directory]::CreateDirectory((Join-Path $setup 'src')) | Out-Null
    foreach ($name in 'install.ps1','bootstrap.ps1','packages.lock.json') { Copy-Item (Join-Path $PSScriptRoot $name) $setup -Force }
    Copy-Item (Join-Path $PSScriptRoot 'src\*') (Join-Path $setup 'src') -Force
}
if ($StageOnly) {
    Stop-Cmd3rStep
    Write-Host "`n  Staging complete. Offline installers and tools are verified." -ForegroundColor Green
    Write-Host "  $InstallRoot" -ForegroundColor DarkGray
    return
}
Stop-Cmd3rStep
Start-Cmd3rStep 'Preserve and merge Windows Terminal settings'
if (!$TerminalSettingsPath) {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json')
    )
    $TerminalSettingsPath = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (!$TerminalSettingsPath) { $TerminalSettingsPath = $paths[0] }
}
# Parse before changing the user profiles: malformed settings must stay intact.
$settings = [pscustomobject]@{}
if (Test-Path $TerminalSettingsPath) { $settings = ConvertFrom-Jsonc (Get-Content $TerminalSettingsPath -Raw) }
$settings = Merge-TerminalSettings $settings $preferences @($scheme,$lightScheme) $pwshExe
Set-ObjectProperty $settings 'theme' $themeMode
Stop-Cmd3rStep
Start-Cmd3rStep 'Install Geist Mono Nerd Font for your account'

# Per-user font installation; discover the real family instead of guessing it.
Add-Type -AssemblyName PresentationCore
$regular = Get-ChildItem $fontSource -File | Where-Object Name -Match 'NerdFontMono-Regular\.(otf|ttf)$' | Select-Object -First 1
if (!$regular) { throw 'Geist font archive is missing the Mono variant' }
$glyph = New-Object Windows.Media.GlyphTypeface ([Uri]$regular.FullName)
if (!$glyph.CharacterToGlyphMap.ContainsKey(0xf07c) -or !$glyph.CharacterToGlyphMap.ContainsKey(0xe0a0)) { throw 'Font is missing prompt icons' }
Add-Type -AssemblyName System.Drawing
$fontCollection = New-Object Drawing.Text.PrivateFontCollection
$fontCollection.AddFontFile($regular.FullName)
if ($fontCollection.Families[0].Name -ne $preferences.fontFace) { throw 'Font family does not match preferences.json' }
$fontCollection.Dispose()
if (!('Cmd3r.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Cmd3r { public static class Native {
    [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string file, uint flags, IntPtr reserved);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr wp, string lp, uint flags, uint timeout, out IntPtr result);
} }
'@
}
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
[IO.Directory]::CreateDirectory($fontDir) | Out-Null
$fontRegistry = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
if (!(Test-Path $fontRegistry)) { New-Item $fontRegistry | Out-Null }
foreach ($font in Get-ChildItem $fontSource -File | Where-Object Name -Match 'NerdFontMono-(Regular|Light|Bold|Italic|LightItalic|BoldItalic)\.(otf|ttf)$') {
    $fontPath = Join-Path $fontDir $font.Name
    $same = (Test-Path $fontPath) -and ((Get-Cmd3rSha256 $fontPath) -eq (Get-Cmd3rSha256 $font.FullName))
    if (!$same) {
        Backup-ExistingFile -Path $fontPath -BackupRoot $backup
        Copy-Item -LiteralPath $font.FullName -Destination $fontPath -Force
    }
    $style = $font.BaseName.Split('-')[-1]
    New-ItemProperty $fontRegistry -Name "$($preferences.fontFace) $style (TrueType)" -Value $fontPath -PropertyType String -Force | Out-Null
    [Cmd3r.Native]::AddFontResourceEx($fontPath,0,[IntPtr]::Zero) | Out-Null
}
$messageResult = [IntPtr]::Zero
[Cmd3r.Native]::SendMessageTimeout([IntPtr]0xffff,0x001d,[IntPtr]::Zero,$null,2,1000,[ref]$messageResult) | Out-Null
Stop-Cmd3rStep
Start-Cmd3rStep 'Configure PowerShell profiles and saved history'
$pwshProfile = (& $pwshExe -NoLogo -NoProfile -Command '$PROFILE.CurrentUserCurrentHost') -join ''
if ($LASTEXITCODE -ne 0 -or !$pwshProfile) { throw 'Could not resolve PowerShell user profile' }
$pwshAllHostsProfile = (& $pwshExe -NoLogo -NoProfile -Command '$PROFILE.CurrentUserAllHosts') -join ''
if ($LASTEXITCODE -ne 0 -or !$pwshAllHostsProfile) { throw 'Could not resolve PowerShell all-hosts profile' }
$windowsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$legacyProfile = (& $windowsExe -NoLogo -NoProfile -Command '$PROFILE.CurrentUserCurrentHost') -join ''
$legacyAllHostsProfile = (& $windowsExe -NoLogo -NoProfile -Command '$PROFILE.CurrentUserAllHosts') -join ''
if ($LASTEXITCODE -ne 0 -or !$legacyProfile -or !$legacyAllHostsProfile) { throw 'Could not resolve Windows PowerShell user profiles' }
# CurrentHost loads last, after an existing Oh My Posh initialization.
foreach ($profilePath in @($pwshProfile,$legacyProfile) | Select-Object -Unique) {
    $existing = ''
    if (Test-Path $profilePath) { $existing = Get-Content $profilePath -Raw; if ($null -eq $existing) { $existing = '' } }
    Backup-ExistingFile $profilePath $backup
    Write-Utf8File -Path $profilePath -Text (Merge-ProfileContent $existing (Join-Path $config 'profile.ps1')) -Bom
}
# Older cmd3r releases loaded from AllHosts. Remove only that managed block.
foreach ($profilePath in @($pwshAllHostsProfile,$legacyAllHostsProfile) | Select-Object -Unique) {
    if (Test-Path -LiteralPath $profilePath) {
        $existing = Get-Content -LiteralPath $profilePath -Raw
        if ($null -eq $existing) { $existing = '' }
        $clean = Remove-Cmd3rProfileBlock $existing
        if ($clean -cne $existing) {
            Backup-ExistingFile $profilePath $backup
            Write-Utf8File -Path $profilePath -Text $clean -Bom
        }
    }
}
# Only adjust the user's execution policy if it currently prevents local profiles.
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentPolicy -in @('Undefined','Restricted')) {
    $machinePolicy = Get-ExecutionPolicy -Scope MachinePolicy
    $userPolicy = Get-ExecutionPolicy -Scope UserPolicy
    if ($machinePolicy -notin @('Undefined','RemoteSigned','Unrestricted','Bypass') -or $userPolicy -notin @('Undefined','RemoteSigned','Unrestricted','Bypass')) {
        throw 'A managed execution policy blocks unsigned profiles. Ask your administrator to permit this profile.'
    }
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
}
Stop-Cmd3rStep
Start-Cmd3rStep 'Apply the theme and command-line paths'
Backup-ExistingFile $TerminalSettingsPath $backup
Write-Utf8File $TerminalSettingsPath ($settings | ConvertTo-Json -Depth 50)
$userPath = [Environment]::GetEnvironmentVariable('Path','User')
$entries = @($userPath -split ';' | Where-Object { $_ })
foreach ($entry in @($bin,$pwshHome)) { if ($entries -notcontains $entry) { $entries += $entry } }
[Environment]::SetEnvironmentVariable('Path',($entries -join ';'),'User')
[Cmd3r.Native]::SendMessageTimeout([IntPtr]0xffff,0x001a,[IntPtr]::Zero,'Environment',2,1000,[ref]$messageResult) | Out-Null
Write-Utf8File (Join-Path $InstallRoot 'installation.json') ([pscustomobject]@{root=$InstallRoot;settings=$TerminalSettingsPath;powerShellProfile=$pwshProfile;legacyProfile=$legacyProfile;backup=$backup;installedAt=(Get-Date -Format o)} | ConvertTo-Json)
Stop-Cmd3rStep
Start-Cmd3rStep 'Verify your new terminal environment'
$verification = Invoke-Cmd3rVerification -PowerShellPath $pwshExe -DoctorPath (Join-Path $setup 'src\doctor.ps1') -InstallRoot $InstallRoot -CacheRoot $CacheRoot
Stop-Cmd3rStep -Message ($verification -join ' ')
Write-Host "`n  cmd3r is ready." -ForegroundColor Green
Write-Host "  Open a new Windows Terminal tab. Backups: $backup" -ForegroundColor DarkGray
if (!$SkipLaunch) {
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if (!$wt) { $wtPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe' } else { $wtPath = $wt.Source }
    if (Test-Path $wtPath) { Start-Process -FilePath $wtPath -ArgumentList ('-w new new-tab -p ' + $preferences.profileGuid) }
}
} catch {
    if (!(Get-Command Show-Cmd3rFailure -ErrorAction SilentlyContinue)) {
        [Console]::Error.WriteLine('cmd3r could not initialize its PowerShell host: ' + $_.Exception.Message)
        exit 1
    }
    $exitCode = Show-Cmd3rFailure -Failure $_ -CacheRoot $CacheRoot
    exit $exitCode
}
