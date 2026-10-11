function Get-Cmd3rArchitecture {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { return 'arm64' }
    return 'x64'
}

function Get-StableRelease {
    param([string]$Repository)
    $headers = @{'User-Agent'='cmd3r-installer'}
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repository/releases/latest" -Headers $headers
    if ($release.prerelease -or $release.draft -or $release.tag_name -match '(?i)preview|rc|beta|alpha') { throw "$Repository returned a non-stable release" }
    return $release
}

function Select-ReleaseAsset {
    param($Release, [string]$Pattern)
    $assets = @($Release.assets | Where-Object name -Match $Pattern)
    if ($assets.Count -ne 1) { throw "Expected one stable asset for $Pattern; found $($assets.Count)" }
    $asset = $assets[0]
    if ($asset.digest -notmatch '^sha256:[a-fA-F0-9]{64}$') { throw "GitHub did not publish a SHA256 digest for $($asset.name)" }
    return [pscustomobject]@{name=$asset.name;url=$asset.browser_download_url;sha256=$asset.digest.Substring(7)}
}

function Get-PlatformCatalog {
    param([string]$CacheRoot, [switch]$Offline)
    $catalogPath = Join-Path $CacheRoot 'platform-releases.json'
    $architecture = Get-Cmd3rArchitecture
    if ($Offline) {
        if (!(Test-Path $catalogPath)) { throw 'Offline mode requires an earlier online run to cache platform-releases.json and the installers.' }
        $catalog = Get-Content $catalogPath -Raw | ConvertFrom-Json
        if ($catalog.architecture -ne $architecture) { throw 'Cached platform installers target a different CPU architecture' }
        return $catalog
    }
    $powershell = Get-StableRelease 'PowerShell/PowerShell'
    $terminal = Get-StableRelease 'microsoft/terminal'
    $catalog = [pscustomobject]@{
        architecture=$architecture
        resolvedAt=(Get-Date -Format o)
        powershell=[pscustomobject]@{version=$powershell.tag_name.TrimStart('v');asset=(Select-ReleaseAsset $powershell "^PowerShell-[0-9.]+-win-$architecture\.msi$")}
        terminal=[pscustomobject]@{version=$terminal.tag_name.TrimStart('v');asset=(Select-ReleaseAsset $terminal '^Microsoft\.WindowsTerminal_[0-9.]+_8wekyb3d8bbwe\.msixbundle_Windows10_PreinstallKit\.zip$')}
    }
    Write-Utf8File $catalogPath ($catalog | ConvertTo-Json -Depth 8)
    return $catalog
}

function Test-VersionCurrent {
    param([string]$Installed, [string]$Required)
    # Preview versions never satisfy the stable requirement; never downgrade a
    # newer installed stable version when using an older offline catalog.
    if (!$Installed -or $Installed -match '-') { return $false }
    try { return [version]$Installed -ge [version]$Required } catch { return $false }
}

function Install-StablePowerShell {
    param($Catalog, [string]$CacheRoot, [switch]$StageOnly, [switch]$Offline)
    $asset = $Catalog.powershell.asset
    $installer = Get-VerifiedDownload $asset.url $asset.sha256 $CacheRoot -Offline:$Offline
    $signature = Get-AuthenticodeSignature -LiteralPath $installer
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'PowerShell MSI does not have a valid Microsoft signature' }
    # Resolve native Program Files even when launched in a 32-bit host.
    $programFiles = $env:ProgramW6432
    if (!$programFiles) { $programFiles = $env:ProgramFiles }
    $exe = Join-Path $programFiles 'PowerShell\7\pwsh.exe'
    if ($StageOnly) { return $exe }
    $installed = ''
    if (Test-Path $exe) { $installed = (& $exe -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') -join '' }
    if (!(Test-VersionCurrent $installed $Catalog.powershell.version)) {
        $log = Join-Path $CacheRoot 'powershell-msi.log'
        $arguments = '/i "{0}" /quiet /norestart /L*v "{1}" ADD_PATH=1 ENABLE_MU=0 USE_MU=0' -f $installer,$log
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $admin = ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($admin) { $process = Start-Process msiexec.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru }
        else {
            Write-Cmd3rNote 'Approve the Windows administrator prompt to install PowerShell.'
            $process = Start-Process msiexec.exe -Verb RunAs -ArgumentList $arguments -WindowStyle Hidden -PassThru
        }
        $process.WaitForExit()
        if ($process.ExitCode -notin @(0,3010,1641)) { throw "PowerShell MSI failed (exit $($process.ExitCode)). Log: $log" }
        if ($process.ExitCode -in @(3010,1641)) { Write-Cmd3rNote 'Windows reports a reboot is required. cmd3r will not reboot automatically.' }
    }
    if (!(Test-Path $exe)) { throw 'PowerShell MSI completed but pwsh.exe was not found' }
    $version = (& $exe -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') -join ''
    if (!(Test-VersionCurrent $version $Catalog.powershell.version)) { throw "PowerShell verification failed: installed $version, expected $($Catalog.powershell.version)" }
    return $exe
}

function Install-StableTerminal {
    param($Catalog, [string]$CacheRoot, [switch]$StageOnly, [switch]$Offline)
    $asset = $Catalog.terminal.asset
    $installer = Get-VerifiedDownload $asset.url $asset.sha256 $CacheRoot -Offline:$Offline
    $kit = Join-Path $CacheRoot ("terminal-kit-$($Catalog.terminal.version)")
    if (!(Test-Path $kit)) { Expand-Archive -LiteralPath $installer -DestinationPath $kit -Force }
    $bundle = Get-ChildItem $kit -Recurse -File -Filter '*.msixbundle' | Select-Object -First 1
    if (!$bundle) { throw 'Windows Terminal offline kit does not contain its MSIX bundle' }
    if ($StageOnly) { return }
    $installed = Get-AppxPackage -Name Microsoft.WindowsTerminal | Sort-Object Version -Descending | Select-Object -First 1
    if ($installed -and (Test-VersionCurrent $installed.Version.ToString() $Catalog.terminal.version)) { return }
    $architecture = $Catalog.architecture
    $dependencies = @(Get-ChildItem $kit -Recurse -File | Where-Object {
        $_.Extension -in @('.appx','.msix') -and
        ($_.FullName -match "(?i)[\\/]$architecture[\\/]" -or $_.Name -match "(?i)(_|\.)($architecture|neutral)(_|\.)")
    } | ForEach-Object FullName)
    $runner = Join-Path $PSScriptRoot 'deploy-terminal.ps1'
    $request = Join-Path $CacheRoot 'terminal-deployment.json'
    $log = Join-Path $CacheRoot 'terminal-deployment.log'
    Write-Utf8File $request ([pscustomobject]@{bundle=$bundle.FullName;dependencies=$dependencies} | ConvertTo-Json -Depth 5)
    # A hidden Windows PowerShell child keeps AppX support consistent when the
    # installer was launched from PowerShell 7. It runs as the original user.
    $windowsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $process = Start-Process $windowsExe -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Request "{1}" -Log "{2}"' -f $runner,$request,$log) -WindowStyle Hidden -PassThru
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Windows Terminal offline installation failed. $(Get-Content $log -Raw -ErrorAction SilentlyContinue)" }
    $installed = Get-AppxPackage -Name Microsoft.WindowsTerminal | Sort-Object Version -Descending | Select-Object -First 1
    if (!$installed -or !(Test-VersionCurrent $installed.Version.ToString() $Catalog.terminal.version)) {
        $pending = [InvalidOperationException]::new('Windows Terminal update is waiting for its open windows to close.')
        $pending.Data['Cmd3rStatus'] = 'TerminalUpdatePending'
        throw $pending
    }
}
