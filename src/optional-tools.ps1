# Installer-only optional tools; never loaded during shell startup.
function Test-Cmd3rInteractiveInput { return ![Console]::IsInputRedirected }

function Read-Cmd3rOptionalChoice {
    param([string]$Label, [ValidateSet('Ask','Yes','No')][string]$Choice = 'Ask', [switch]$NonInteractive, [string]$Description, [switch]$StageOnly)
    if ($Choice -ne 'Ask') { return $Choice -eq 'Yes' }
    if ($NonInteractive -or !(Test-Cmd3rInteractiveInput)) {
        Write-Host "  Skipping $Label (no explicit opt-in)." -ForegroundColor DarkGray
        return $false
    }
    Write-Host "`n  $Label" -ForegroundColor Cyan
    if ($Description) { Write-Host "  $Description" }
    Write-Host '  Type Y for Yes, or press Enter to skip.' -ForegroundColor DarkGray
    $question = '  Install {0}? [y/N]' -f $Label
    if ($StageOnly) { $question = '  Download and cache {0} for offline installation later? [y/N]' -f $Label }
    do {
        $answer = (Read-Host -Prompt $question).Trim()
        if ($answer -notmatch '^(?i:y|yes|n|no)?$') { Write-Host '  Please enter Y or N (Enter skips).' -ForegroundColor Yellow }
    } while ($answer -notmatch '^(?i:y|yes|n|no)?$')
    Write-Host ('  {0}: {1}' -f $Label, $(if ($answer -match '^(?i:y|yes)$') {'Selected'} else {'Skipped'})) -ForegroundColor DarkGray
    return $answer -match '^(?i:y|yes)$'
}

function Update-Cmd3rProcessPath {
    # Keep the current process additions, while incorporating installer changes.
    $paths = @([Environment]::GetEnvironmentVariable('Path','User'), [Environment]::GetEnvironmentVariable('Path','Machine'), $env:PATH)
    $env:PATH = (($paths -join ';') -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'
    $env:PATH = [Environment]::ExpandEnvironmentVariables($env:PATH)
}

function Install-Cmd3rNvm {
    param([string]$CacheRoot, [switch]$Offline, [switch]$StageOnly, [switch]$NonInteractive)
    $existing = Get-Command nvm.exe -ErrorAction SilentlyContinue
    if ($existing -and !$StageOnly) {
        Write-Cmd3rNote "NVM already installed: $($existing.Source). Keeping your existing Node versions and configuration."
        return
    }
    $catalogPath = Join-Path $CacheRoot 'nvm-release.json'
    $architecture = Get-Cmd3rArchitecture
    if ($Offline) {
        if (!(Test-Path $catalogPath)) { throw 'NVM offline cache is missing. Run -StageOnly -NvmWindows Yes online with this CacheRoot first.' }
        $catalog = Get-Content $catalogPath -Raw | ConvertFrom-Json
        if ($catalog.architecture -ne $architecture) { throw 'Cached NVM installer targets a different CPU architecture.' }
    } else {
        $release = Get-StableRelease 'nvm-windows/nvm'
        $catalog = [pscustomobject]@{version=$release.tag_name;architecture=$architecture;asset=(Select-ReleaseAsset $release "^nvm-[0-9.]+-$architecture-setup\.exe$")}
        Write-Utf8File $catalogPath ($catalog | ConvertTo-Json -Depth 6)
    }
    $installer = Get-VerifiedDownload $catalog.asset.url $catalog.asset.sha256 $CacheRoot -Offline:$Offline
    if ($StageOnly) { Write-Cmd3rNote "NVM $($catalog.version) offline installer verified and cached."; return }
    if ($NonInteractive -and (Get-Command node.exe -ErrorAction SilentlyContinue)) {
        throw 'Existing Node detected. Rerun interactively to review NVM migration choices, or use -NvmWindows No.'
    }
    if ($script:Cmd3rAnimated) { [Cmd3r.CliSpinner]::Stop() }
    $arguments = '/NORESTART /LOG="{0}"' -f (Join-Path $CacheRoot 'nvm-install.log')
    if ($NonInteractive) { $arguments += ' /VERYSILENT'; $window = 'Hidden' }
    else { Write-Cmd3rNote 'Complete the NVM setup wizard; review any existing Node migration choices.'; $window = 'Normal' }
    $process = Start-Process -FilePath $installer -ArgumentList $arguments -WindowStyle $window -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "NVM setup cancelled or failed (exit $($process.ExitCode)). See nvm-install.log in $CacheRoot; rerun with -NvmWindows No to skip." }
    Update-Cmd3rProcessPath
    $nvm = Get-Command nvm.exe -ErrorAction SilentlyContinue
    if (!$nvm) { throw 'NVM installer finished, but nvm.exe is not on PATH. Open a new terminal and rerun setup.' }
    & $nvm.Source version
    if ($LASTEXITCODE -ne 0) { throw 'NVM installation verification failed.' }
    Write-Cmd3rNote 'NVM is ready. Node runtime downloads are separate; use nvm install / nvm use to choose a version.'
}

function Install-Cmd3rNpkill {
    param([string]$InstallRoot, [string]$CacheRoot, [switch]$Offline, [switch]$StageOnly)
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if (!$npm -or !$node) { throw 'npkill requires an active Node.js and npm installation. Activate Node using NVM, then rerun; or choose -Npkill No.' }
    & $node.Source --version
    if ($LASTEXITCODE -ne 0) { throw 'Node is not active. Activate a Node version before installing npkill.' }
    $manifestPath = Join-Path $CacheRoot 'npkill-release.json'
    if ($Offline) {
        if (!(Test-Path $manifestPath)) { throw 'npkill offline cache is missing. Run -StageOnly -Npkill Yes online first.' }
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    } else {
        $package = Invoke-RestMethod 'https://registry.npmjs.org/npkill/latest'
        $manifest = [pscustomobject]@{version=$package.version}
    }
    if ($manifest.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid npkill release version.' }
    $prefix = Join-Path $InstallRoot 'tools\npm'
    if ($StageOnly) { $prefix = Join-Path $CacheRoot 'npkill-stage' }
    $npmArgs = @('install','--global','--prefix',$prefix,'--cache',(Join-Path $CacheRoot 'npm-cache'),'--registry','https://registry.npmjs.org','--ignore-scripts','--engine-strict','--no-audit','--no-fund','--update-notifier=false',"npkill@$($manifest.version)")
    if ($Offline) { $npmArgs += '--offline' }
    if ($script:Cmd3rAnimated) { [Cmd3r.CliSpinner]::Stop() }
    & $npm.Source @npmArgs
    if ($LASTEXITCODE -ne 0) { throw 'npkill installation failed. Check the npm error above (Node version or incomplete offline cache); rerun after fixing it, or choose -Npkill No.' }
    Write-Utf8File $manifestPath ($manifest | ConvertTo-Json)
    $command = Join-Path $prefix 'npkill.cmd'
    if (!(Test-Path $command)) { throw 'npm finished without creating npkill.cmd.' }
    & $command --version
    if ($LASTEXITCODE -ne 0) { throw 'npkill verification failed.' }
    if (!$StageOnly) {
        Write-Utf8File (Join-Path $InstallRoot 'bin\npkill.cmd') "@echo off`r`ncall `"%~dp0..\tools\npm\npkill.cmd`" %*`r`nexit /b %errorlevel%`r`n"
    }
    Write-Cmd3rNote $(if ($StageOnly) {'npkill and its dependencies cached for offline use.'} else {'npkill installed. Run npkill yourself when you want to review node_modules folders.'})
}
