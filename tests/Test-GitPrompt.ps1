[CmdletBinding()]
param([string]$Posh)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path $PSScriptRoot -Parent
if (!$Posh) {
    $Posh = @((Join-Path $env:LOCALAPPDATA 'Programs\cmd3r\bin\oh-my-posh.exe'), (Join-Path $env:USERPROFILE 'AppData\Local\Programs\cmd3r\bin\oh-my-posh.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (!$Posh) { throw 'oh-my-posh.exe is required for Git prompt tests. Pass -Posh with its path.' }
$repo = Join-Path $PSScriptRoot ('.work\git-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($repo) | Out-Null
function Assert($Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Git {
    & git.exe -C $repo @args 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Git fixture command failed: $args" }
}
function Commit([string]$Message) { Git -c user.name=cmd3r-test -c user.email=cmd3r-test@example.invalid -c commit.gpgsign=false commit --quiet -m $Message }
function Render([string]$Mode) {
    return ((& $Posh print primary --config (Join-Path $root "src\workspace-$Mode.omp.json") --shell pwsh --pwd $repo --pswd $repo --terminal-width 180 --status 0 --plain) -join "`n")
}
Git init --quiet --initial-branch=main
foreach ($name in 'modify.txt','delete.txt','conflict.txt') { [IO.File]::WriteAllText((Join-Path $repo $name),"base`n") }
Git add .
Commit 'base'
[IO.File]::WriteAllText((Join-Path $repo 'modify.txt'),"changed`n")
Remove-Item -LiteralPath (Join-Path $repo 'delete.txt')
[IO.File]::WriteAllText((Join-Path $repo 'new.txt'),"untracked`n")
[IO.File]::WriteAllText((Join-Path $repo 'added.txt'),"staged`n")
Git add added.txt
foreach ($mode in 'light','dark') {
    $rendered = Render $mode
    Assert ($rendered.Contains('~1') -and $rendered.Contains('-1') -and $rendered.Contains('?1') -and $rendered.Contains("$([char]0x2713) +1")) 'Git change counts are incorrect'
    Assert ($rendered -notmatch 'CONFIG ERROR|TEMPLATE ERROR') 'Git template failed to render'
}
Git -c user.name=cmd3r-test -c user.email=cmd3r-test@example.invalid stash push --include-untracked --quiet
Assert ((Render 'dark').Contains("$([char]0xf187) 1")) 'Stash count is missing'
Git checkout --quiet -b feature
[IO.File]::WriteAllText((Join-Path $repo 'conflict.txt'),"feature`n")
Git add conflict.txt
Commit 'feature'
$feature = (& git.exe -C $repo rev-parse HEAD) -join ''
Git checkout --quiet main
[IO.File]::WriteAllText((Join-Path $repo 'conflict.txt'),"main`n")
Git add conflict.txt
Commit 'main'
foreach ($operation in 'cherry-pick','merge','rebase','revert') {
    & git.exe -C $repo -c user.name=cmd3r-test -c user.email=cmd3r-test@example.invalid -c commit.gpgsign=false $operation $feature 2>&1 | Out-Null
    Assert ($LASTEXITCODE -eq 1) "Expected a conflict for fixture operation $operation"
    foreach ($mode in 'light','dark') {
        $rendered = Render $mode
        Assert ($rendered.Contains($operation.ToUpper()) -and $rendered.Contains('!1')) "Missing $operation operation or conflict metadata"
        Assert ($rendered -notmatch 'CONFIG ERROR|TEMPLATE ERROR') 'Git operation template failed'
    }
    Git $operation --abort
}
Write-Host 'PASS: modified, deleted, untracked, staged, stash, and real cherry-pick/merge/rebase/revert conflict metadata in both themes.'
