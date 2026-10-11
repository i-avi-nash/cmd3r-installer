param([string]$ForeignModulePath = 'C:\Program Files\PowerShell\7\Modules')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$originalPath = $env:PSModulePath
try {
    # Simulate a module path inherited from a different PowerShell edition.
    $env:PSModulePath = $ForeignModulePath + ';' + $env:PSModulePath
    . (Join-Path $root 'src\installer-host.ps1')
    foreach ($name in 'Get-FileHash','Get-AuthenticodeSignature','Expand-Archive','Get-Item') {
        $command = Get-Command $name -ErrorAction Stop
        if (!$command.Module.Path.StartsWith($PSHOME, [StringComparison]::OrdinalIgnoreCase)) { throw "$name loaded from the wrong host: $($command.Module.Path)" }
    }
    $signature = Get-AuthenticodeSignature -LiteralPath ([IO.Path]::Combine($PSHOME, $(if ($PSVersionTable.PSVersion.Major -eq 5) {'powershell.exe'} else {'pwsh.exe'})))
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'Real Microsoft signature verification failed' }
    . (Join-Path $root 'src\installer-host.ps1')
    Get-Command Get-AuthenticodeSignature -ErrorAction Stop | Out-Null
    Write-Host 'PASS: mixed-edition module path, native module selection, real signature verification, and repeated initialization.'
} finally { $env:PSModulePath = $originalPath }
