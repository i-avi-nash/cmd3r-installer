param([switch]$DownloadIntegration)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\setup-lib.ps1')
. (Join-Path $root 'src\platform.ps1')
. (Join-Path $root 'src\optional-tools.ps1')
function Assert($Condition, [string]$Message) { if (!$Condition) { throw $Message } }
function Write-Cmd3rNote([string]$Message) { Write-Host $Message }
$fixture = Join-Path $PSScriptRoot ('.work\optional tools ' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
Assert (Read-Cmd3rOptionalChoice test Yes -NonInteractive) 'Explicit opt-in was ignored'
Assert (!(Read-Cmd3rOptionalChoice test No -NonInteractive)) 'Explicit opt-out was ignored'
Assert (!(Read-Cmd3rOptionalChoice test Ask -NonInteractive)) 'Unattended install must not opt in'
# Exercise the actual interactive branch, including the prompt passed to Read-Host.
& {
    function Test-Cmd3rInteractiveInput { return $true }
    $script:questions = @()
    $script:answers = [Collections.Generic.Queue[string]]::new()
    foreach ($answer in @('invalid','y','','yes')) { $script:answers.Enqueue($answer) }
    function Read-Host { param([string]$Prompt); $script:questions += $Prompt; return $script:answers.Dequeue() }
    Assert (Read-Cmd3rOptionalChoice -Label 'NVM for Windows' -Description 'Manage Node.js versions.') 'Interactive NVM opt-in failed'
    Assert (!(Read-Cmd3rOptionalChoice -Label 'npkill' -Description 'Review node_modules folders.')) 'Enter must skip npkill'
    Assert (Read-Cmd3rOptionalChoice -Label 'npkill' -StageOnly) 'Staging opt-in failed'
    Assert ($script:questions.Count -eq 4) 'Invalid input should retry'
    Assert ($script:questions[0] -eq '  Install NVM for Windows? [y/N]') 'NVM question lost the tool name'
    Assert ($script:questions[2] -eq '  Install npkill? [y/N]') 'npkill question lost the tool name'
    Assert ($script:questions[3] -like '*Download and cache npkill*') 'Staging question incorrectly promised installation'
}
$failed = $false
try { Install-Cmd3rNvm -CacheRoot $fixture -Offline -StageOnly } catch { $failed = $_.Exception.Message -like '*offline cache is missing*' }
Assert $failed 'NVM missing offline cache did not produce an actionable failure'
Write-Utf8File (Join-Path $fixture 'nvm-release.json') (@{architecture='wrong'} | ConvertTo-Json)
$failed = $false
try { Install-Cmd3rNvm -CacheRoot $fixture -Offline -StageOnly } catch { $failed = $_.Exception.Message -like '*different CPU*' }
Assert $failed 'NVM accepted an incompatible offline installer'
if ($DownloadIntegration) {
    Install-Cmd3rNvm -CacheRoot $fixture -StageOnly
    # Offline mode must not resolve releases or contact npm metadata endpoints.
    Install-Cmd3rNpkill -CacheRoot $fixture -InstallRoot $fixture -StageOnly
    function Get-StableRelease { throw 'Unexpected network release lookup' }
    function Invoke-RestMethod { throw 'Unexpected HTTP request' }
    Install-Cmd3rNvm -CacheRoot $fixture -StageOnly -Offline
    $target = Join-Path $fixture 'fresh offline install'
    Install-Cmd3rNpkill -CacheRoot $fixture -InstallRoot $target -Offline
    & (Join-Path $target 'bin\npkill.cmd') --version
    Assert ($LASTEXITCODE -eq 0) 'Installed wrapper failed with a spaced path'
}
Write-Host 'PASS: optional choices, offline cache errors, architecture checks, and requested integration checks.'
