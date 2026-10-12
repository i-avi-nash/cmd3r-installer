[CmdletBinding()]
param([string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\cmd3r'))
$ErrorActionPreference = 'Stop'
try {
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$profile = Join-Path $InstallRoot 'config\profile.ps1'
. $profile
$preferences = Get-Content (Join-Path $InstallRoot 'setup\src\preferences.json') -Raw | ConvertFrom-Json
foreach ($command in 'oh-my-posh','fzf','rg','fd','bat','zoxide','lazygit','jq','z','zi','ff','cdf','cmd3r') {
    Get-Command $command -ErrorAction Stop | Out-Null
}
foreach ($tool in 'oh-my-posh','fzf','rg','fd','bat','zoxide','lazygit','jq') {
    $null = & $tool --version
    if ($LASTEXITCODE -ne 0) { throw "$tool failed to start" }
}
$rendered = prompt | Out-String
if ($rendered -match 'CONFIG ERROR|TEMPLATE ERROR' -or !$rendered.Contains([char]0xf07c) -or $rendered.Contains([char]0xfffd)) { throw 'Prompt rendering or icon decoding failed' }
if ($PWD.Provider.Name -eq 'FileSystem') {
    $folderLink = [regex]::Match($rendered, "$([char]27)\]8;;(file:[^\x07\x1b]+)")
    if (!$folderLink.Success -or ([Uri]$folderLink.Groups[1].Value).LocalPath.TrimEnd('\','/') -ne $PWD.Path.TrimEnd('\','/')) { throw 'Prompt folder hyperlink is missing or points to the wrong directory' }
}
& cmd.exe /c exit 7
$errorPrompt = prompt | Out-String
if (!$errorPrompt.Contains('7') -or $LASTEXITCODE -ne 7) { throw 'Prompt error handling failed' }
$global:LASTEXITCODE = 0
$options = Get-PSReadLineOption
if ($options.HistorySaveStyle -ne 'SaveIncrementally' -or $options.MaximumHistoryCount -ne 10000) { throw 'Persistent history is not configured' }
if ([Console]::OutputEncoding.CodePage -ne 65001 -or $OutputEncoding.CodePage -ne 65001) { throw 'Console encoding is not UTF-8' }
$selected = @('cmd3r-one','cmd3r-two') | & fzf --filter='cmd3r-two'
if ($selected -ne 'cmd3r-two') { throw 'Fuzzy search failed' }
$theme = $global:TerminalPromptTheme
$found = & rg --files-with-matches final_space $theme
if (!$found) { throw 'Content search failed' }
$jsonVersion = Get-Content $theme -Raw | & jq -r '.version'
if ($jsonVersion -ne '4') { throw 'JSON filtering failed' }
& bat --paging=never --color=never --line-range=1:3 $theme | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'File viewing failed' }
if (Test-Path (Join-Path $InstallRoot 'installation.json')) {
    $installation = Get-Content (Join-Path $InstallRoot 'installation.json') -Raw | ConvertFrom-Json
    foreach ($profilePath in @($installation.powerShellProfile,$installation.legacyProfile) | Select-Object -Unique) {
        $profileText = Get-Content -LiteralPath $profilePath -Raw -ErrorAction Stop
        if ($profileText -notmatch '(?s)# BEGIN CMD3R\r?\n.*?# END CMD3R\s*$') {
            throw "cmd3r is not the last block in the console profile: $profilePath"
        }
    }
    . (Join-Path $InstallRoot 'setup\src\setup-lib.ps1')
    $settings = ConvertFrom-Jsonc (Get-Content $installation.settings -Raw)
    $default = $settings.profiles.list | Where-Object guid -eq $settings.defaultProfile
    if ($default.guid -ne $preferences.profileGuid) { throw 'Windows Terminal default profile is incorrect' }
    Add-Type -AssemblyName System.Drawing
    if (!([Drawing.FontFamily]::Families | Where-Object Name -eq $preferences.fontFace)) { throw 'Windows cannot resolve the Geist Nerd Font' }
}
Write-Host "PASS: cmd3r tools, prompt, Unicode icons, persistent history, and available Windows Terminal configuration. Profile load: $global:TerminalProfileStartupMs ms."
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
