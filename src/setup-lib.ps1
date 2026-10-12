function Write-Utf8File {
    param([string]$Path, [string]$Text, [switch]$Bom)
    [IO.Directory]::CreateDirectory((Split-Path $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new([bool]$Bom))
}

function ConvertFrom-Jsonc {
    param([string]$Text)
    # Windows Terminal accepts comments and trailing commas. Remove them only
    # outside JSON strings, preserving URLs and commas in user configuration.
    $builder = [Text.StringBuilder]::new()
    $inString = $false; $escaped = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $char = $Text[$i]
        if ($inString) {
            [void]$builder.Append($char)
            if ($escaped) { $escaped = $false }
            elseif ($char -eq '\') { $escaped = $true }
            elseif ($char -eq '"') { $inString = $false }
            continue
        }
        if ($char -eq '"') { $inString = $true; [void]$builder.Append($char); continue }
        if ($char -eq '/' -and $i + 1 -lt $Text.Length) {
            if ($Text[$i + 1] -eq '/') {
                while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
                [void]$builder.Append("`n"); continue
            }
            if ($Text[$i + 1] -eq '*') {
                $i += 2
                while ($i + 1 -lt $Text.Length -and !($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }
                if ($i + 1 -ge $Text.Length) { throw 'Unclosed JSON comment' }
                $i++; [void]$builder.Append(' '); continue
            }
        }
        [void]$builder.Append($char)
    }
    $clean = $builder.ToString(); $builder.Clear() | Out-Null
    $inString = $false; $escaped = $false
    for ($i = 0; $i -lt $clean.Length; $i++) {
        $char = $clean[$i]
        if ($inString) {
            [void]$builder.Append($char)
            if ($escaped) { $escaped = $false }
            elseif ($char -eq '\') { $escaped = $true }
            elseif ($char -eq '"') { $inString = $false }
            continue
        }
        if ($char -eq '"') { $inString = $true }
        if ($char -eq ',') {
            $next = $i + 1
            while ($next -lt $clean.Length -and [char]::IsWhiteSpace($clean[$next])) { $next++ }
            if ($next -lt $clean.Length -and $clean[$next] -in @('}', ']')) { continue }
        }
        [void]$builder.Append($char)
    }
    ConvertFrom-Json -InputObject $builder.ToString()
}

function Set-ObjectProperty {
    param($Object, [string]$Name, $Value)
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Merge-TerminalSettings {
    param($Settings, $Preferences, $Scheme, [string]$PowerShellPath)
    if (!$Settings.profiles) { Set-ObjectProperty $Settings 'profiles' ([pscustomobject]@{defaults=[pscustomobject]@{};list=@()}) }
    if (!$Settings.profiles.defaults) { Set-ObjectProperty $Settings.profiles 'defaults' ([pscustomobject]@{}) }
    $profile = @($Settings.profiles.list | Where-Object guid -eq $Preferences.profileGuid) | Select-Object -First 1
    if (!$profile) {
        $profile = [pscustomobject]@{guid=$Preferences.profileGuid;font=[pscustomobject]@{}}
        # Defaults are only for a new cmd3r profile. Respect inherited font choices.
        $fontDefaults = @{face=$Preferences.fontFace;size=$Preferences.fontSize;weight=$Preferences.fontWeight;cellHeight=$Preferences.cellHeight}
        foreach ($key in $fontDefaults.Keys) {
            if (!$Settings.profiles.defaults.font -or !$Settings.profiles.defaults.font.PSObject.Properties[$key]) {
                Set-ObjectProperty $profile.font $key $fontDefaults[$key]
            }
        }
    }
    Set-ObjectProperty $profile 'name' $Preferences.profileName
    Set-ObjectProperty $profile 'commandline' ('"' + $PowerShellPath + '" -NoLogo')
    Set-ObjectProperty $profile 'startingDirectory' '%USERPROFILE%'
    Set-ObjectProperty $profile 'hidden' $false
    # Terminal generates this stable PowerShell profile separately from cmd3r.
    $stableGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    $stable = @($Settings.profiles.list | Where-Object guid -eq $stableGuid) | Select-Object -First 1
    if (!$stable) {
        $stable = [pscustomobject]@{guid=$stableGuid;name='PowerShell';source='Windows.Terminal.PowershellCore'}
        Set-ObjectProperty $Settings.profiles 'list' (@($Settings.profiles.list) + @($stable))
    }
    Set-ObjectProperty $stable 'commandline' ('"' + $PowerShellPath + '" -NoLogo')
    if (!$stable.font) { Set-ObjectProperty $stable 'font' ([pscustomobject]@{}) }
    foreach ($key in @('face','size','weight','cellHeight')) {
        if (!$stable.font.PSObject.Properties[$key] -and (!$Settings.profiles.defaults.font -or !$Settings.profiles.defaults.font.PSObject.Properties[$key]) -and $profile.font -and $profile.font.PSObject.Properties[$key]) {
            Set-ObjectProperty $stable.font $key $profile.font.$key
        }
    }
    # The downloaded Geist release registers this family under its short name.
    if ($stable.font.face -eq 'GeistMono Nerd Font Mono') { Set-ObjectProperty $stable.font 'face' $Preferences.fontFace }
    foreach ($target in @($profile,$stable) + @($Settings.profiles.list | Where-Object guid -eq '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}')) {
        if (!$target.font) { Set-ObjectProperty $target 'font' ([pscustomobject]@{}) }
        Set-ObjectProperty $target.font 'builtinGlyphs' $true
        Set-ObjectProperty $target 'colorScheme' $Preferences.colorScheme
        Set-ObjectProperty $target 'padding' $Preferences.padding
        Set-ObjectProperty $target 'opacity' 100
        Set-ObjectProperty $target 'useAcrylic' $false
    }
    Set-ObjectProperty $Settings.profiles 'list' (@($Settings.profiles.list | Where-Object guid -ne $Preferences.profileGuid) + @($profile))
    $schemeNames = @($Scheme | ForEach-Object name)
    Set-ObjectProperty $Settings 'schemes' (@($Settings.schemes | Where-Object { $_.name -notin $schemeNames }) + @($Scheme))
    Set-ObjectProperty $Settings 'defaultProfile' $Preferences.profileGuid
    return $Settings
}

function Remove-Cmd3rProfileBlock {
    param([AllowEmptyString()][string]$Existing)
    return $Existing -replace '(?ms)\r?\n?# BEGIN (?:TERMINALTOOLS|CMD3R)\r?\n.*?# END (?:TERMINALTOOLS|CMD3R)\r?\n?', ''
}

function Merge-ProfileContent {
    param([AllowEmptyString()][string]$Existing, [string]$SharedProfile)
    $clean = Remove-Cmd3rProfileBlock $Existing
    $source = ". '$($SharedProfile.Replace("'", "''"))'"
    return $clean.TrimEnd() + "`r`n# BEGIN CMD3R`r`n$source`r`n# END CMD3R`r`n"
}

function Get-Cmd3rSha256 {
    param([Parameter(Mandatory)][string]$LiteralPath)
    # Stream large installers directly through .NET. Hash verification must not
    # depend on Get-FileHash or PowerShell's module discovery in the parent shell.
    $stream = $null
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($LiteralPath)
        return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
    } finally {
        if ($stream) { $stream.Dispose() }
        $hasher.Dispose()
    }
}

function Get-VerifiedDownload {
    param([string]$Url, [string]$Sha256, [string]$CacheRoot, [switch]$Offline)
    if ($Url -notmatch '^https://github\.com/[^/]+/[^/]+/releases/download/') { throw "Unsupported package URL: $Url" }
    if ($Sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Missing pinned SHA256 checksum' }
    [IO.Directory]::CreateDirectory($CacheRoot) | Out-Null
    $file = Join-Path $CacheRoot ([Uri]::UnescapeDataString(([Uri]$Url).Segments[-1]))
    if (Test-Path -LiteralPath $file) {
        if ((Get-Cmd3rSha256 -LiteralPath $file) -eq $Sha256) { return $file }
    }
    if ($Offline) { throw "Offline cache is missing a verified copy of $([IO.Path]::GetFileName($file))" }
    $partial = "$file.partial"
    $client = [Net.WebClient]::new()
    $client.Headers['User-Agent'] = 'cmd3r-installer'
    try { $client.DownloadFile($Url, $partial) } finally { $client.Dispose() }
    if ((Get-Cmd3rSha256 -LiteralPath $partial) -ne $Sha256) { throw "Checksum mismatch: $Url" }
    Move-Item -LiteralPath $partial -Destination $file -Force
    return $file
}

function Backup-ExistingFile {
    param([string]$Path, [string]$BackupRoot)
    if (Test-Path -LiteralPath $Path) {
        [IO.Directory]::CreateDirectory($BackupRoot) | Out-Null
        $name = ($Path -replace '[:\\/]', '_')
        Copy-Item -LiteralPath $Path -Destination (Join-Path $BackupRoot $name) -Force
    }
}

function Invoke-Cmd3rVerification {
    param([string]$PowerShellPath, [string]$DoctorPath, [string]$InstallRoot, [string]$CacheRoot)
    [IO.Directory]::CreateDirectory($CacheRoot) | Out-Null
    $stdout = Join-Path $CacheRoot 'verification.stdout.log'
    $stderr = Join-Path $CacheRoot 'verification.stderr.log'
    $log = Join-Path $CacheRoot 'verification.log'
    # Escape trailing slashes before the closing quote for Windows argv parsing.
    $quotedRoot = '"' + ($InstallRoot -replace '(\\+)$','$1$1') + '"'
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -InstallRoot {1}' -f $DoctorPath,$quotedRoot
    $child = Start-Process -FilePath $PowerShellPath -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
    $output = Get-Content $stdout -Raw -ErrorAction SilentlyContinue
    $errors = Get-Content $stderr -Raw -ErrorAction SilentlyContinue
    Write-Utf8File $log ("Exit code: $($child.ExitCode)`r`n$output`r`n$errors")
    if ($child.ExitCode -ne 0) {
        $detail = ($errors -replace '\x1b\[[0-9;]*m','').Trim()
        if (!$detail) { $detail = ([string]$output).Trim() }
        if (!$detail) { $detail = "Doctor exited with code $($child.ExitCode) without output." }
        throw "Installation verification failed: $detail`nVerification log: $log"
    }
    return ([string]$output).Trim()
}
