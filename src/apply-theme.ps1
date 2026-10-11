# Apply theme changes to an existing installation without running app installers.
[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\cmd3r'),
    [ValidateSet('light','dark')][string]$Mode = 'dark'
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path (Join-Path $InstallRoot 'installation.json'))) { throw 'Install cmd3r before applying its theme.' }
. (Join-Path $PSScriptRoot 'setup-lib.ps1')
$backup = Join-Path $InstallRoot ('backups\theme-source-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
foreach ($name in 'profile.ps1','theme.ps1','workspace-dark.omp.json','workspace-light.omp.json') {
    $target = Join-Path $InstallRoot "config\$name"
    Backup-ExistingFile $target $backup
    Copy-Item (Join-Path $PSScriptRoot $name) $target -Force
}
foreach ($name in 'setup-lib.ps1','theme.ps1','scheme.json','scheme-light.json','preferences.json','doctor.ps1') {
    $target = Join-Path $InstallRoot "setup\src\$name"
    Backup-ExistingFile $target $backup
    Copy-Item (Join-Path $PSScriptRoot $name) $target -Force
}
$env:CMD3R_HOME = $InstallRoot
. (Join-Path $InstallRoot 'config\theme.ps1')
Set-Cmd3rTheme $Mode
Write-Host "Theme files applied. Backups: $backup"
