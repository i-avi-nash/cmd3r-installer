# Local theme selection only: no network, registry, or subprocesses at startup.
function global:Initialize-Cmd3rTheme {
    param([ValidateSet('light','dark')][string]$Mode)
    if (!$Mode) {
        $Mode = 'dark'
        $modeFile = Join-Path $env:CMD3R_HOME 'config\theme-mode.txt'
        if (Test-Path $modeFile) {
            $saved = [IO.File]::ReadAllText($modeFile).Trim()
            if ($saved -in @('light','dark')) { $Mode = $saved }
        }
    }
    $global:Cmd3rThemeMode = $Mode
    $global:TerminalPromptTheme = Join-Path $env:CMD3R_HOME "config\workspace-$Mode.omp.json"
    $env:BAT_THEME = $(if ($Mode -eq 'light') {'GitHub'} else {'TwoDark'})
    if ($Mode -eq 'light') {
        $text = '#111214'; $muted = '#66676A'; $accent = '#800020'; $selected = '#DDDAD5'
    } else {
        $text = '#F1F0ED'; $muted = '#B0AFAD'; $accent = '#800020'; $selected = '#343436'
    }
    $env:FZF_DEFAULT_OPTS = "--height=60% --layout=reverse --border --color=bg+:$selected,fg:$text,fg+:$text,hl:$accent,hl+:$accent,pointer:$accent,marker:$accent,spinner:$accent,header:$muted,border:$muted"
    if (Get-Module PSReadLine) {
        $esc = [char]27
        $rgbText = $text.TrimStart('#'); $rgbMuted = $muted.TrimStart('#'); $rgbAccent = $accent.TrimStart('#')
        function Convert-ThemeAnsi([string]$Hex) {
            $r = [Convert]::ToInt32($Hex.Substring(0,2),16)
            $g = [Convert]::ToInt32($Hex.Substring(2,2),16)
            $b = [Convert]::ToInt32($Hex.Substring(4,2),16)
            return "$esc[38;2;${r};${g};${b}m"
        }
        $normal = Convert-ThemeAnsi $rgbText
        $quiet = Convert-ThemeAnsi $rgbMuted
        $red = Convert-ThemeAnsi $rgbAccent
        $selection = $normal + (Convert-ThemeAnsi $selected.TrimStart('#')).Replace('[38;','[48;')
        $colors = @{Default=$normal;Command=$normal;String=$normal;Number=$normal;Variable=$normal;Type=$normal;Member=$normal;Operator=$quiet;Parameter=$quiet;Comment=$quiet;Keyword=$red;Error=$red;ContinuationPrompt=$quiet;Emphasis=$red;Selection=$selection}
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $colors.InlinePrediction = $quiet
            $colors.ListPrediction = $quiet
            $colors.ListPredictionSelected = $selection
        }
        Set-PSReadLineOption -Colors $colors
    }
    $global:Cmd3rThemeStamp = [IO.File]::GetLastWriteTimeUtc((Join-Path $env:CMD3R_HOME 'config\theme-mode.txt'))
}

function global:Sync-Cmd3rTheme {
    # Terminal changes the shared profile background in every open tab. Refresh
    # shell colors on the next prompt too, using only a local timestamp check.
    $stamp = [IO.File]::GetLastWriteTimeUtc((Join-Path $env:CMD3R_HOME 'config\theme-mode.txt'))
    if ($stamp -ne $global:Cmd3rThemeStamp) { Initialize-Cmd3rTheme }
}

function global:Set-Cmd3rTheme {
    param([Parameter(Mandatory)][ValidateSet('light','dark')][string]$Mode)
    $setupSource = Join-Path $env:CMD3R_HOME 'setup\src'
    . (Join-Path $setupSource 'setup-lib.ps1')
    $installation = Get-Content (Join-Path $env:CMD3R_HOME 'installation.json') -Raw | ConvertFrom-Json
    $settings = ConvertFrom-Jsonc (Get-Content $installation.settings -Raw)
    $preferences = Get-Content (Join-Path $setupSource 'preferences.json') -Raw | ConvertFrom-Json
    $schemes = @((Get-Content (Join-Path $setupSource 'scheme.json') -Raw | ConvertFrom-Json), (Get-Content (Join-Path $setupSource 'scheme-light.json') -Raw | ConvertFrom-Json))
    $schemeName = "cmd3r Workspace $((Get-Culture).TextInfo.ToTitleCase($Mode))"
    foreach ($target in @($settings.profiles.list | Where-Object { $_.guid -in @($preferences.profileGuid,'{61c54bbd-c2c6-5271-96e7-009a87ff44bf}','{574e775e-4f2a-5b96-ac1e-a2962a402336}') })) {
        Set-ObjectProperty $target 'colorScheme' $schemeName
        if (!$target.font) { Set-ObjectProperty $target 'font' ([pscustomobject]@{}) }
        Set-ObjectProperty $target.font 'builtinGlyphs' $true
    }
    $names = @($schemes | ForEach-Object name)
    Set-ObjectProperty $settings 'schemes' (@($settings.schemes | Where-Object { $_.name -notin $names }) + $schemes)
    Set-ObjectProperty $settings 'theme' $Mode
    $backup = Join-Path $env:CMD3R_HOME ('backups\theme-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    Backup-ExistingFile $installation.settings $backup
    Write-Utf8File $installation.settings ($settings | ConvertTo-Json -Depth 50)
    Write-Utf8File (Join-Path $env:CMD3R_HOME 'config\theme-mode.txt') $Mode
    Initialize-Cmd3rTheme $Mode
    Write-Host "cmd3r theme: $Mode. Other updated tabs follow on their next prompt."
}
