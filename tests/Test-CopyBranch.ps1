$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src\profile.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Profile syntax error' }
$function = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'global:Copy-Cmd3rGitBranch'}, $true)
. ([scriptblock]::Create($function.Extent.Text))
# Test branch resolution without replacing the user's real clipboard.
function Set-Clipboard { param([string]$Value, [string]$ErrorAction); $script:copied = $Value }
$fixture = Join-Path $PSScriptRoot ('.work\copy branch ' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$oldCeiling = $env:GIT_CEILING_DIRECTORIES
$env:GIT_CEILING_DIRECTORIES = Split-Path $fixture -Parent
Push-Location $fixture
try {
    $script:copied = 'untouched'
    Copy-Cmd3rGitBranch | Out-Null
    if ($script:copied -ne 'untouched') { throw 'Outside repository overwrote clipboard' }
    git init -q -b feature/copy-branch
    $global:LASTEXITCODE = 7
    $message = Copy-Cmd3rGitBranch
    if ($script:copied -ne 'feature/copy-branch' -or $global:LASTEXITCODE -ne 7 -or $message -notlike 'Copied branch:*') { throw 'Branch copy or exit-code preservation failed' }
    git -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm test
    git checkout --detach -q
    $script:copied = 'untouched'
    Copy-Cmd3rGitBranch | Out-Null
    if ($script:copied -ne 'untouched') { throw 'Detached HEAD overwrote clipboard' }
    Import-Module PSReadLine
    $binding = $ast.Find({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.Extent.Text -like '*-BriefDescription CopyGitBranch*'}, $true)
    if ($binding.Extent.Text -match 'InvokePrompt') { throw 'Shortcut redraws an extra prompt' }
    . ([scriptblock]::Create($binding.Extent.Text))
    if (!(Get-PSReadLineKeyHandler | Where-Object Function -eq 'CopyGitBranch')) { throw 'Shortcut was not registered' }
    Write-Host 'PASS: shortcut registration, branch with slash, unborn branch, detached HEAD, outside repository, and exit-code preservation.'
} finally { Pop-Location; $env:GIT_CEILING_DIRECTORIES = $oldCeiling }
