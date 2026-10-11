$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\setup-lib.ps1')
. (Join-Path $root 'src\platform.ps1')
function Assert($Condition, [string]$Message) { if (!$Condition) { throw $Message } }

foreach ($file in @('install.ps1','bootstrap.ps1') + @(Get-ChildItem (Join-Path $root 'src') -Filter '*.ps1' | ForEach-Object { 'src\' + $_.Name })) {
    $tokens = $null; $errors = $null
    [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors) | Out-Null
    Assert ($errors.Count -eq 0) "PowerShell syntax error in $file : $errors"
}
$prefs = Get-Content (Join-Path $root 'src\preferences.json') -Raw | ConvertFrom-Json
$scheme = @((Get-Content (Join-Path $root 'src\scheme.json') -Raw | ConvertFrom-Json),(Get-Content (Join-Path $root 'src\scheme-light.json') -Raw | ConvertFrom-Json))
$fixture = @'
{
  // Keep an unrelated profile and its special characters.
  "defaultProfile": "other",
  "profiles": { "defaults": { "historySize": 9001 }, "list": [
    { "guid": "other", "name": "My shell", "commandline": "https://example.com/a/*b*/?x=,}", },
  ], },
  "schemes": [{ "name": "Existing", "foreground": "#ffffff", }],
  /* Existing custom shortcuts must survive. */
  "actions": [{ "command": "find", "keys": "ctrl+shift+f" }],
}
'@
$settings = ConvertFrom-Jsonc $fixture
$merged = Merge-TerminalSettings $settings $prefs $scheme 'C:\Other User\Apps\cmd3r\pwsh\v7.6.6\pwsh.exe'
$repeat = Merge-TerminalSettings (ConvertFrom-Jsonc ($merged | ConvertTo-Json -Depth 50)) $prefs $scheme 'C:\Other User\Apps\cmd3r\pwsh\v7.6.6\pwsh.exe'
Assert ($repeat.profiles.list.Count -eq 3) 'Repeat run duplicated the default profile'
Assert ($repeat.schemes.Count -eq 3) 'Repeat run duplicated or lost a color scheme'
Assert ($repeat.actions[0].keys -eq 'ctrl+shift+f') 'Custom shortcuts were lost'
Assert ($repeat.profiles.defaults.historySize -eq 9001) 'Profile defaults were lost'
Assert ($repeat.profiles.list[0].commandline -eq 'https://example.com/a/*b*/?x=,}') 'JSON comments parser corrupted a string'
$managed = $repeat.profiles.list | Where-Object guid -eq $prefs.profileGuid
Assert ($managed.commandline.StartsWith('"C:\Other User\')) 'Executable path with spaces is not quoted'
Assert ($managed.font.face -eq 'GeistMono NFM' -and $managed.font.weight -eq 'light') 'Personal font preference was lost'
$fresh = Merge-TerminalSettings ([pscustomobject]@{}) $prefs $scheme 'C:\Apps\pwsh.exe'
Assert ($fresh.profiles.list.Count -eq 2) 'Fresh-machine settings were not created'
$stable = $fresh.profiles.list | Where-Object guid -eq '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
Assert ($stable.font.face -eq $prefs.fontFace -and $stable.commandline -eq '"C:\Apps\pwsh.exe" -NoLogo') 'Generated stable PowerShell missed the font or installed executable'
$stable.font.face = 'GeistMono Nerd Font Mono'; $stable.font.size = 14
$fresh = Merge-TerminalSettings $fresh $prefs $scheme 'C:\Apps\pwsh.exe'
Assert ($stable.font.face -eq $prefs.fontFace -and $stable.font.size -eq 14) 'Geist family repair reset chosen font size'
$fresh.profiles.list[0].font = [pscustomobject]@{face='Consolas';size=15;weight='normal';cellHeight='1.2'}
$custom = Merge-TerminalSettings $fresh $prefs $scheme 'C:\Apps\pwsh.exe'
Assert ($custom.profiles.list[0].font.face -eq 'Consolas' -and $custom.profiles.list[0].font.size -eq 15 -and $custom.profiles.list[0].font.cellHeight -eq '1.2' -and $custom.profiles.list[0].font.weight -eq 'normal') 'Update overwrote the user font'
$inherited = [pscustomobject]@{profiles=[pscustomobject]@{defaults=[pscustomobject]@{font=[pscustomobject]@{face='Cascadia Mono';size=16;weight='normal';cellHeight='1.1'}};list=@()}}
$inherited = Merge-TerminalSettings $inherited $prefs $scheme 'C:\Apps\pwsh.exe'
Assert (!$inherited.profiles.list[0].font.PSObject.Properties['face'] -and !$inherited.profiles.list[0].font.PSObject.Properties['size']) 'New profile shadowed inherited font settings'
$inherited = Merge-TerminalSettings $inherited $prefs $scheme 'C:\Apps\pwsh.exe'
Assert (!$inherited.profiles.list[0].font.PSObject.Properties['face']) 'Update broke font inheritance'
$existing = "# Keep my custom setup`r`n`$env:MY_SETTING = 'yes'`r`n# BEGIN TERMINALTOOLS`r`n. 'C:\old\profile.ps1'`r`n# END TERMINALTOOLS`r`n"
$first = Merge-ProfileContent $existing "C:\O'Brien\cmd3r\config\profile.ps1"
$second = Merge-ProfileContent $first "C:\O'Brien\cmd3r\config\profile.ps1"
Assert ($first -eq $second) 'Profile update is not idempotent'
Assert ($second.Contains("`$env:MY_SETTING = 'yes'")) 'Existing profile content was lost'
Assert ($second.Contains("O''Brien")) 'Apostrophe in the profile path was not escaped'
Assert (!$second.Contains('C:\old\')) 'Old managed profile block survived'
$packages = Get-Content (Join-Path $root 'packages.lock.json') -Raw | ConvertFrom-Json
Assert ($packages.Count -eq 9) 'Expected nine pinned productivity/font packages (platform installers are resolved dynamically)'
foreach ($package in $packages) {
    Assert ($package.sha256 -match '^[a-f0-9]{64}$') "Missing checksum: $($package.id)"
    Assert ($package.url -match '^https://github\.com/[^/]+/[^/]+/releases/download/') "Non-official download URL: $($package.id)"
}
Assert (($packages | Where-Object id -eq 'geist-font').url.EndsWith('/GeistMono.zip')) 'Wrong font package'
Assert (Test-VersionCurrent '7.6.6' '7.6.5') 'A newer stable installation should be retained'
Assert (!(Test-VersionCurrent '7.7.0-preview.1' '7.6.6')) 'A preview must not satisfy the stable prerequisite'
Assert (!(Test-VersionCurrent '1.24.12741.0' '1.25.2733.0')) 'An older Terminal must be upgraded'
$fake = [pscustomobject]@{assets=@([pscustomobject]@{name='PowerShell-7.6.6-win-x64.msi';browser_download_url='https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/PowerShell-7.6.6-win-x64.msi';digest=('sha256:' + ('a' * 64))})}
$selectedAsset = Select-ReleaseAsset $fake '^PowerShell-[0-9.]+-win-x64\.msi$'
Assert ($selectedAsset.sha256.Length -eq 64) 'Release digest was not extracted'
$rejected = $false
try { Get-VerifiedDownload -Url $selectedAsset.url -Sha256 $selectedAsset.sha256 -CacheRoot (Join-Path $PSScriptRoot '.work\missing-cache') -Offline | Out-Null } catch { $rejected = $_.Exception.Message -like 'Offline cache*' }
Assert $rejected 'Offline mode must fail without contacting the network if the installer is missing'
& {
    # Reproduce a host where Get-FileHash cannot be used, without weakening checks.
    function Get-FileHash { throw 'Get-FileHash unavailable in this host' }
    $hashCache = Join-Path $PSScriptRoot '.work\hash cache'
    [IO.Directory]::CreateDirectory($hashCache) | Out-Null
    $hashFile = Join-Path $hashCache 'hash [test].zip'
    [IO.File]::WriteAllText($hashFile, 'abc', [Text.UTF8Encoding]::new($false))
    $expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    Assert ((Get-Cmd3rSha256 $hashFile) -eq $expected) 'SHA256 does not match known test vector'
    $hashUrl = 'https://github.com/test/test/releases/download/v1/hash%20%5Btest%5D.zip'
    Assert ((Get-VerifiedDownload $hashUrl $expected $hashCache -Offline) -eq $hashFile) 'Verified offline cache could not be used without Get-FileHash'
    [IO.File]::WriteAllText($hashFile, 'corrupted')
    $corruptRejected = $false
    try { Get-VerifiedDownload $hashUrl $expected $hashCache -Offline | Out-Null } catch { $corruptRejected = $_.Exception.Message -like 'Offline cache*' }
    Assert $corruptRejected 'Corrupted cached installer passed verification'
}
$installerText = Get-Content (Join-Path $root 'install.ps1') -Raw
Assert ($installerText.IndexOf('Install-StablePowerShell') -lt $installerText.IndexOf('foreach ($package in $packages)')) 'PowerShell must be installed before other tools'
Assert ($installerText.IndexOf('Install-StableTerminal') -lt $installerText.IndexOf('foreach ($package in $packages)')) 'Terminal must be installed before other tools'
# Exercise the real installer entry point in a child process with local platform
# stubs. These failure cases must not make network requests or install software.
$failureFixture = Join-Path $PSScriptRoot '.work\failure fixture'
[IO.Directory]::CreateDirectory((Join-Path $failureFixture 'src')) | Out-Null
Copy-Item (Join-Path $root 'install.ps1') $failureFixture -Force
Copy-Item (Join-Path $root 'Install.cmd') $failureFixture -Force
foreach ($name in 'setup-lib.ps1','progress.ps1','optional-tools.ps1','installer-host.ps1') { Copy-Item (Join-Path $root "src\$name") (Join-Path $failureFixture 'src') -Force }
foreach ($kind in 'pending','unexpected') {
    $stub = @'
function Get-PlatformCatalog { return [pscustomobject]@{powershell=@{version='7.6.6'};terminal=@{version='1.25.2733.0'};architecture='x64'} }
function Install-StablePowerShell { return 'C:\Program Files\PowerShell\7\pwsh.exe' }
function Install-StableTerminal {
'@
    if ($kind -eq 'pending') {
        $stub += "`n`$e = [InvalidOperationException]::new('TEST_PENDING'); `$e.Data['Cmd3rStatus'] = 'TerminalUpdatePending'; throw `$e`n}"
    } else { $stub += "`nthrow 'TEST_UNEXPECTED'`n}" }
    Write-Utf8File (Join-Path $failureFixture 'src\platform.ps1') $stub
    $fixtureCache = Join-Path $failureFixture "cache-$kind"
    $fixtureInstall = Join-Path $failureFixture "install-$kind"
    foreach ($entryPoint in 'powershell','cmd') {
    $processInfo = [Diagnostics.ProcessStartInfo]::new()
    if ($entryPoint -eq 'cmd') {
        $processInfo.FileName = $env:ComSpec
        $processInfo.Arguments = '/d /s /c ""{0}" -NoAnimation -SkipLaunch -CacheRoot "{1}" -InstallRoot "{2}""' -f (Join-Path $failureFixture 'Install.cmd'),$fixtureCache,$fixtureInstall
    } else {
        $processInfo.FileName = (Get-Command powershell.exe).Source
        $processInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -NoAnimation -SkipLaunch -CacheRoot "{1}" -InstallRoot "{2}"' -f (Join-Path $failureFixture 'install.ps1'),$fixtureCache,$fixtureInstall
    }
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $child = [Diagnostics.Process]::Start($processInfo)
    $stdout = $child.StandardOutput.ReadToEndAsync()
    $stderr = $child.StandardError.ReadToEndAsync()
    $child.WaitForExit()
    $outText = $stdout.Result
    Assert ($stderr.Result.Length -eq 0) 'Handled failure emitted a raw exception to stderr'
    Assert (!$outText.Contains('CategoryInfo') -and !$outText.Contains('FullyQualifiedErrorId')) 'Raw PowerShell exception appeared in CLI output'
    Assert (!(Test-Path $fixtureInstall)) 'Failure during platform prerequisites started the remaining configuration'
    $logs = @(Get-ChildItem (Join-Path $fixtureCache 'logs') -Filter '*.log')
    Assert ($logs.Count -ge 1) 'Handled failure did not save a diagnostic log'
    $latestLog = $logs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Assert ((Get-Content $latestLog.FullName -Raw).Contains('ScriptStackTrace')) 'Diagnostic log lost technical exception details'
    if ($kind -eq 'pending') {
        Assert ($child.ExitCode -eq 2) 'Pending Terminal update must return exit code 2'
        Assert ($outText.Contains('Setup paused:') -and $outText.Contains('Close all Windows Terminal')) 'Pending update did not show recovery guidance'
    } else {
        Assert ($child.ExitCode -eq 1) 'Unexpected failure must return exit code 1'
        Assert (($outText.Split(@('TEST_UNEXPECTED'),[StringSplitOptions]::None).Count - 1) -eq 1) 'Unexpected failure was not printed exactly once'
    }
    $child.Dispose()
    }
}
$doctorFixture = Join-Path $failureFixture 'doctor fixture.ps1'
Write-Utf8File $doctorFixture "param([string]`$InstallRoot)`r`n[Console]::Error.WriteLine('TEST_DOCTOR_DETAIL'); exit 23"
$doctorCache = Join-Path $failureFixture 'doctor cache'
$doctorFailed = $false
try { Invoke-Cmd3rVerification -PowerShellPath (Get-Command powershell.exe).Source -DoctorPath $doctorFixture -InstallRoot ($failureFixture + '\') -CacheRoot $doctorCache | Out-Null }
catch { $doctorFailed = $_.Exception.Message.Contains('TEST_DOCTOR_DETAIL') }
Assert $doctorFailed 'Verifier discarded the actual doctor failure reason'
Assert ((Get-Content (Join-Path $doctorCache 'verification.log') -Raw).Contains('Exit code: 23')) 'Verifier lost the child exit code'
Write-Utf8File $doctorFixture "param([string]`$InstallRoot)`r`nif (!`$InstallRoot.EndsWith('\')) { exit 9 }; Write-Output 'TEST_DOCTOR_PASS'"
$doctorResult = Invoke-Cmd3rVerification -PowerShellPath (Get-Command powershell.exe).Source -DoctorPath $doctorFixture -InstallRoot ($failureFixture + '\') -CacheRoot $doctorCache
Assert ($doctorResult -eq 'TEST_DOCTOR_PASS') 'Verifier failed to capture success or quote a trailing slash'
Write-Host 'PASS: configuration preservation, stable prerequisites, offline cache, clean failures, diagnostic logs, doctor failure details, and PowerShell/CMD exit codes with spaced paths.'
