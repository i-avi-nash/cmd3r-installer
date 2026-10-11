# Download the public cmd3r installer snapshot without GitHub credentials.
[CmdletBinding()]
param(
    [string]$Repository = 'i-avi-nash/cmd3r-installer',
    [string]$Ref = 'main',
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'Programs\cmd3r'),
    [switch]$SkipLaunch,
    [switch]$StageOnly,
    [switch]$NoAnimation,
    [ValidateSet('Ask','Yes','No')][string]$NvmWindows = 'Ask',
    [ValidateSet('Ask','Yes','No')][string]$Npkill = 'Ask',
    [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
# The web bootstrap can be evaluated without a local src directory. Bind its
# own inbox modules before it downloads and extracts the installer source.
foreach ($moduleName in @('Microsoft.PowerShell.Utility','Microsoft.PowerShell.Management','Microsoft.PowerShell.Security','Microsoft.PowerShell.Archive')) {
    Import-Module -Name ([IO.Path]::Combine($PSHOME, "Modules\$moduleName\$moduleName.psd1")) -Global -Force -ErrorAction Stop
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid GitHub repository name' }
$sourceRoot = Join-Path $env:LOCALAPPDATA ('cmd3r\sources\' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($sourceRoot) | Out-Null
$zip = Join-Path $sourceRoot 'source.zip'
$client = [Net.WebClient]::new()
$client.Headers['User-Agent'] = 'cmd3r-bootstrap'
try {
    Write-Host "Fetching $Repository ($Ref)..."
    $client.DownloadFile("https://codeload.github.com/$Repository/zip/refs/heads/$([Uri]::EscapeDataString($Ref))", $zip)
} finally {
    $client.Dispose()
}
Expand-Archive -LiteralPath $zip -DestinationPath $sourceRoot -Force
$installer = Get-ChildItem -LiteralPath $sourceRoot -Directory | ForEach-Object { Join-Path $_.FullName 'install.ps1' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$installer) { throw 'Repository archive does not contain install.ps1' }
# Permit this fetched installer in this process only; normal profile policy is
# configured separately by install.ps1 and managed policies still take precedence.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& $installer -InstallRoot $InstallRoot -SkipLaunch:$SkipLaunch -StageOnly:$StageOnly -NoAnimation:$NoAnimation -NvmWindows $NvmWindows -Npkill $Npkill -NonInteractive:$NonInteractive
