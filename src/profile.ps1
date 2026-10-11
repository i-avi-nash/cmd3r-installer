# Lightweight shared profile for Windows Terminal and PowerShell.
$terminalStartupTimer = [Diagnostics.Stopwatch]::StartNew()
# Nerd Font symbols from native tools must be decoded as UTF-8.
$terminalUtf8 = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $terminalUtf8
[Console]::OutputEncoding = $terminalUtf8
$global:OutputEncoding = $terminalUtf8
$terminalRoot = Split-Path $PSScriptRoot -Parent
$terminalBin = Join-Path $terminalRoot 'bin'
$terminalPwsh = Join-Path $terminalRoot 'pwsh'
if (Test-Path (Join-Path $PSScriptRoot 'paths.ps1')) { . (Join-Path $PSScriptRoot 'paths.ps1') }
$env:CMD3R_HOME = $terminalRoot
$env:POSH_CACHE_DIR = Join-Path $terminalRoot 'data\posh-cache'
$env:_ZO_DATA_DIR = Join-Path $terminalRoot 'data\zoxide'
foreach ($entry in @($terminalBin, $terminalPwsh)) {
    if (($env:PATH -split ';') -notcontains $entry) { $env:PATH = "$entry;$env:PATH" }
}
$env:BAT_PAGER = 'less -FRX'
$env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --exclude .git'
. (Join-Path $PSScriptRoot 'theme.ps1')

function global:ff {
    $selection = & fd --type f --hidden --exclude .git | & fzf --prompt='Files > ' --preview='bat --color=always --style=numbers --line-range=:200 {}'
    if ($selection) { $selection }
}
function global:cdf {
    $selection = & fd --type d --hidden --exclude .git | & fzf --prompt='Directories > '
    if ($selection) { Set-Location -LiteralPath $selection }
}
function global:ll { Get-ChildItem -Force @args }
function global:.. { Set-Location .. }
function global:... { Set-Location ../.. }
function global:gs { & git status --short --branch @args }
function global:gl { & git log --oneline --graph --decorate -20 @args }
function global:gd { & git diff @args }
function global:lg { & lazygit @args }
function global:Copy-Cmd3rGitBranch {
    $savedExitCode = $global:LASTEXITCODE
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        if ($PWD.Provider.Name -ne 'FileSystem') { return 'No Git repository here; clipboard unchanged.' }
        $git = Get-Command git.exe -ErrorAction Stop
        # Nonzero is expected outside a repository or on a detached HEAD.
        $branch = & $git.Source -C $PWD.Path symbolic-ref --quiet --short HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or !$branch) {
            return 'No named Git branch here (outside a repository or detached HEAD); clipboard unchanged.'
        }
        Set-Clipboard -Value ([string]$branch).Trim() -ErrorAction Stop
        return "Copied branch: $branch"
    } catch {
        return 'Could not copy the Git branch; check Git and clipboard availability.'
    } finally { $global:LASTEXITCODE = $savedExitCode }
}
function global:cmd3r {
    param([ValidateSet('help','doctor','update','theme')][string]$Action = 'help', [ValidateSet('light','dark')][string]$Mode)
    switch ($Action) {
        'help' { terminal-help }
        'theme' {
            if ($Mode) {
                # Reload definitions so an already-open shell picks up theme fixes.
                . (Join-Path $env:CMD3R_HOME 'config\theme.ps1')
                Set-Cmd3rTheme $Mode
            } else { Write-Host "Theme: $global:Cmd3rThemeMode. Use cmd3r theme light or cmd3r theme dark." }
        }
        'doctor' { & (Join-Path $terminalPwsh 'pwsh.exe') -NoLogo -NoProfile -File (Join-Path $env:CMD3R_HOME 'setup\src\doctor.ps1') -InstallRoot $env:CMD3R_HOME }
        'update' { & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $env:CMD3R_HOME 'setup\bootstrap.ps1') -InstallRoot $env:CMD3R_HOME -SkipLaunch }
    }
}
function global:terminal-help {
    @'
TERMINAL SHORTCUTS
  Tab              Interactive completion menu
  Right arrow      Accept an inline history suggestion
  Up / Down        Select a history suggestion or browse past commands
  F2               Switch between history list and inline suggestions
  Ctrl+R           Fuzzy search command history (inserts; Enter runs)
  Alt+F            Fuzzy pick a file and insert its quoted path
  Ctrl+L           Clear screen
  Ctrl+Shift+B     Copy the current Git branch name to the clipboard

COMMANDS
  z <name>         Jump to a previously visited directory
  zi               Fuzzy pick a previously visited directory
  cdf              Fuzzy find and enter a subdirectory
  ff               Fuzzy find a file with syntax-highlighted preview
  fd <pattern>     Find files by name
  rg <text>        Search file contents
  bat <file>       View a file with syntax highlighting
  lg               Interactive Git interface (inside a Git repository)
  gs / gl / gd     Git status / graph / diff
  jq <filter>      Query JSON
  ll / .. / ...    List hidden files / up one directory / up two
  terminal-help    Show this guide again
  cmd3r doctor     Verify this installation
  cmd3r theme light / dark   Switch prompt, Terminal, history, and search colors
  cmd3r update     Fetch the public installer and apply the latest setup
'@
}

if ($Host.Name -eq 'ConsoleHost') {
    if (!(Get-Module PSReadLine)) {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            Import-Module (Join-Path $PSHOME 'Modules\PSReadLine\PSReadLine.psd1')
        } else {
            Import-Module PSReadLine
        }
    }
    Set-PSReadLineOption -EditMode Windows -HistoryNoDuplicates -HistorySaveStyle SaveIncrementally -MaximumHistoryCount 10000 -HistorySearchCursorMovesToEnd -BellStyle None
    if ($PSVersionTable.PSVersion.Major -ge 7 -and ![Console]::IsOutputRedirected) {
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView
    }
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function PreviousHistory
    Set-PSReadLineKeyHandler -Key DownArrow -Function NextHistory
    Set-PSReadLineKeyHandler -Chord Ctrl+Shift+b -BriefDescription CopyGitBranch -LongDescription 'Copy the current Git branch name to the clipboard' -ScriptBlock {
        $message = Copy-Cmd3rGitBranch
        Write-Host "`n$message"
    }
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Set-PSReadLineKeyHandler -Key F2 -Function SwitchPredictionView
    }
    Set-PSReadLineKeyHandler -Key Ctrl+r -ScriptBlock {
        $historyFile = (Get-PSReadLineOption).HistorySavePath
        if (Test-Path -LiteralPath $historyFile) {
            $items = @(Get-Content -LiteralPath $historyFile)
            [array]::Reverse($items)
            $selected = $items | Select-Object -Unique | & fzf --prompt='History > ' --no-sort
            if ($selected) { [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, [int]::MaxValue, [string]$selected) }
        }
    }
    Set-PSReadLineKeyHandler -Key Alt+f -ScriptBlock {
        $selected = & fd --type f --hidden --exclude .git | & fzf --prompt='Insert file > ' --preview='bat --color=always --style=numbers --line-range=:200 {}'
        if ($selected) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("'" + $selected.Replace("'", "''") + "'")
        }
    }
}
Initialize-Cmd3rTheme
if ($Host.Name -eq 'ConsoleHost') {
    . (Join-Path $PSScriptRoot 'zoxide-init.ps1')
    $global:TerminalPromptExecutable = Join-Path $terminalBin 'oh-my-posh.exe'
    # Render with the native engine directly: avoid a generated module and its
    # extra startup subprocesses. Search tools stay idle until requested.
    function global:prompt {
        $previousSuccess = $?
        $previousExitCode = $global:LASTEXITCODE
        $statusCode = 0
        if (!$previousSuccess) {
            $statusCode = 1
            if ($previousExitCode) { $statusCode = $previousExitCode }
        }
        $duration = 0
        $lastCommand = Get-History -Count 1
        if ($lastCommand) { $duration = ($lastCommand.EndExecutionTime - $lastCommand.StartExecutionTime).TotalMilliseconds }
        try {
            Sync-Cmd3rTheme
            $width = 100
            if (![Console]::IsOutputRedirected) {
                try { if ([Console]::WindowWidth -ge 20) { $width = [Console]::WindowWidth } } catch { }
            }
            $rendered = & $global:TerminalPromptExecutable print primary --config $global:TerminalPromptTheme --shell pwsh --pswd $PWD.Path --status $statusCode --execution-time $duration --terminal-width $width
            $null = __zoxide_hook
            return (($rendered -join "`n") + ' ')
        } finally {
            $global:LASTEXITCODE = $previousExitCode
        }
    }
}
$terminalStartupTimer.Stop()
$global:TerminalProfileStartupMs = [math]::Round($terminalStartupTimer.Elapsed.TotalMilliseconds, 1)
