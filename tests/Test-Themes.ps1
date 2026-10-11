[CmdletBinding()]
param([string]$Posh)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$Posh) {
    $Posh = @((Join-Path $env:LOCALAPPDATA 'Programs\cmd3r\bin\oh-my-posh.exe'), (Join-Path $env:USERPROFILE 'AppData\Local\Programs\cmd3r\bin\oh-my-posh.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (!$Posh) { throw 'oh-my-posh.exe is required for theme tests. Pass -Posh with its path.' }
function Assert($Condition,[string]$Message) { if (!$Condition) { throw $Message } }
. (Join-Path $root 'src\setup-lib.ps1')
$fixture = Join-Path $env:TEMP ('cmd3r theme # test ' + [guid]::NewGuid().ToString('N'))
foreach ($directory in 'config','setup\src') { [IO.Directory]::CreateDirectory((Join-Path $fixture $directory)) | Out-Null }
foreach ($name in 'theme.ps1','workspace-dark.omp.json','workspace-light.omp.json') { Copy-Item (Join-Path $root "src\$name") (Join-Path $fixture 'config') }
foreach ($name in 'setup-lib.ps1','preferences.json','scheme.json','scheme-light.json') { Copy-Item (Join-Path $root "src\$name") (Join-Path $fixture 'setup\src') }
$preferences = Get-Content (Join-Path $root 'src\preferences.json') -Raw | ConvertFrom-Json
$settingsPath = Join-Path $fixture 'settings.json'
$settings = [pscustomobject]@{
    profiles=@{list=@(@{guid=$preferences.profileGuid;font=@{face='GeistMono NFM';size=10;weight='light';cellHeight='1.4'}},@{guid='custom';colorScheme='Custom';commandline='cmd.exe'})}
    schemes=@(@{name='Custom';background='#123456'})
    actions=@(@{command='find';keys='ctrl+shift+f'})
}
Write-Utf8File $settingsPath ($settings | ConvertTo-Json -Depth 15)
Write-Utf8File (Join-Path $fixture 'installation.json') (@{settings=$settingsPath} | ConvertTo-Json)
$env:CMD3R_HOME = $fixture
. (Join-Path $fixture 'config\theme.ps1')
Import-Module PSReadLine
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
foreach ($mode in 'light','dark','light','dark') {
    Set-Cmd3rTheme $mode
    $actual = Get-Content $settingsPath -Raw | ConvertFrom-Json
    Assert ($actual.profiles.list[1].commandline -eq 'cmd.exe' -and $actual.profiles.list[1].colorScheme -eq 'Custom') 'Theme switch changed another profile'
    Assert ($actual.actions[0].keys -eq 'ctrl+shift+f') 'Theme switch lost a custom shortcut'
    Assert ($actual.schemes.Count -eq 3) 'Repeated switches duplicated color schemes'
    Assert ($actual.profiles.list[0].font.face -eq 'GeistMono NFM' -and $actual.profiles.list[0].font.weight -eq 'light') 'Theme switch changed font settings'
    Assert ($actual.theme -eq $mode) 'Terminal UI mode was not changed'
    Assert ($actual.profiles.list[0].font.cellHeight -eq '1.4' -and $actual.profiles.list[0].font.size -eq 10) 'Theme switch changed font size or line spacing'
    $global:Cmd3rThemeMode = ''
    Initialize-Cmd3rTheme
    Assert ($global:Cmd3rThemeMode -eq $mode) 'Theme choice was not restored at startup'
    $readLine = Get-PSReadLineOption
    $expectedText = $(if ($mode -eq 'light') {"$([char]27)[38;2;17;18;20m"} else {"$([char]27)[38;2;241;240;237m"})
    Assert ($readLine.DefaultTokenColor -eq $expectedText) 'Unclassified arguments retained the wrong theme color'
    Assert ($readLine.SelectionColor.Contains('[48;2;')) 'Selection needs an explicit readable background'
    Assert ($env:FZF_DEFAULT_OPTS.Contains('--color=') -and $env:BAT_THEME -eq $(if ($mode -eq 'light') {'GitHub'} else {'TwoDark'})) 'Search/preview colors did not switch'
    foreach ($width in 60,120) {
        $rendered = (& $Posh print primary --config $global:TerminalPromptTheme --shell pwsh --pwd $root --pswd $root --terminal-width $width --status 7 --execution-time 1240 --plain) -join "`n"
        Assert ($LASTEXITCODE -eq 0 -and $rendered -notmatch 'CONFIG ERROR|TEMPLATE ERROR') 'Theme failed to render'
        Assert ($rendered.Contains('+') -and !$rendered.Contains([char]0x253c) -and $rendered.Contains([char]0xf07c)) 'Compact border junction or folder icon is missing'
        Assert ($rendered.Contains('EXIT 7')) 'Error badge is missing'
        Assert ($rendered -notmatch 'WORKSPACE|GIT |01 /|02 /|COMMAND| LIGHT | DARK ') 'Removed labels appeared in the prompt'
        Assert ($rendered.TrimEnd().EndsWith('>')) 'Command line should contain only the input marker'
        if ($width -eq 120) { Assert ($rendered -match '\b\d{2}:\d{2} (AM|PM)\b') 'Wide prompt lost the AM/PM clock' }
    }
    $success = (& $Posh print primary --config $global:TerminalPromptTheme --shell pwsh --pwd $fixture --pswd $fixture --terminal-width 120 --status 0 --plain) -join "`n"
    Assert (!$success.Contains('EXIT ') -and !$success.Contains('GIT ')) 'Clean prompt showed an error or Git details outside a repository'
    # The theme must construct its own correct link even in an older shell.
    $env:CMD3R_FOLDER_URL = 'file:///C:/wrong-directory'
    $linked = (& $Posh print primary --config $global:TerminalPromptTheme --shell pwsh --pwd $fixture --pswd $fixture --terminal-width 120 --status 0 --escape=false) -join "`n"
    $folderLink = [regex]::Match($linked, "$([char]27)\]8;;(file:[^\x07\x1b]+)")
    Assert ($folderLink.Success -and ([Uri]$folderLink.Groups[1].Value).LocalPath.TrimEnd('\','/') -eq $fixture.TrimEnd('\','/')) 'Folder hyperlink did not preserve spaces and special characters'
    $env:CMD3R_FOLDER_URL = ''
}
Write-Utf8File (Join-Path $fixture 'config\theme-mode.txt') 'light'
Sync-Cmd3rTheme
Assert ($global:Cmd3rThemeMode -eq 'light' -and (Get-PSReadLineOption).DefaultTokenColor.Contains('17;18;20')) 'An open dark session did not follow a theme change from another tab'
Write-Utf8File (Join-Path $fixture 'config\theme-mode.txt') 'dark'
Sync-Cmd3rTheme
Assert ($global:Cmd3rThemeMode -eq 'dark' -and (Get-PSReadLineOption).DefaultTokenColor.Contains('241;240;237')) 'An open light session retained dark-on-dark text after switching'
Write-Host 'PASS: both rendered themes, narrow/wide layouts, error badge, persistent and cross-tab switching, fonts, and unrelated settings.'
